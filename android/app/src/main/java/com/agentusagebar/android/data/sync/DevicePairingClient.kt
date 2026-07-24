package com.agentusagebar.android.data.sync

import kotlinx.coroutines.delay
import kotlinx.serialization.encodeToString
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URLEncoder
import java.security.KeyPair
import java.util.UUID

data class DevicePairingResult(
    val payload: DeviceSyncPayload,
    val trustedDevice: TrustedDesktopDevice,
)

class DevicePairingClient(
    private val trustedDeviceStore: TrustedDeviceStore,
) {
    suspend fun pair(
        rawCode: String,
        onWaitingForApproval: (desktopName: String, confirmationCode: String) -> Unit,
    ): DevicePairingResult {
        val code = DeviceSyncCodec.decodePairingCode(rawCode)
        val existing = trustedDeviceStore.load().firstOrNull {
            it.desktopID == code.desktopID && it.devicePublicKey != null
        }
        val keyPair = existing?.let {
            KeyPair(
                DeviceSyncCrypto.parseRawPublicKey(
                    DeviceSyncCodec.base64URLDecode(requireNotNull(it.devicePublicKey)),
                ),
                DeviceSyncCrypto.restorePrivateKey(it.privateKey),
            )
        } ?: DeviceSyncCrypto.generateDeviceKeyPair()
        val deviceID = existing?.deviceID ?: UUID.randomUUID().toString().lowercase()
        val deviceName = TrustedDeviceStore.androidDeviceName()
        val sharedSecret = DeviceSyncCrypto.sharedSecret(
            keyPair.private,
            code.desktopPublicKey,
        )
        val expectedCode = DeviceSyncCrypto.confirmationCode(sharedSecret, code.sessionID)
        val request = DevicePairRequest(
            sessionID = code.sessionID,
            deviceID = deviceID,
            deviceName = deviceName,
            publicKey = DeviceSyncCodec.base64URLEncode(
                DeviceSyncCrypto.rawPublicKey(keyPair.public),
            ),
        )
        val start = LocalPairingHttpClient.request(
            host = code.host,
            port = code.port,
            method = "POST",
            path = "/v2/pair",
            body = DeviceSyncCodec.json.encodeToString(request).toByteArray(),
        )
        require(start.status in 200..299) { start.errorMessage() }
        val startResponse = DeviceSyncCodec.json.decodeFromString<DevicePairStartResponse>(
            start.body.toString(Charsets.UTF_8),
        )
        require(startResponse.confirmationCode == expectedCode) {
            "The Mac returned a different security code. Pairing was stopped."
        }
        onWaitingForApproval(code.desktopName, expectedCode)

        val deadline = System.currentTimeMillis() + 10 * 60 * 1_000
        while (System.currentTimeMillis() < deadline) {
            delay(1_000)
            val proof = DeviceSyncCrypto.authenticationProof(
                sharedSecret,
                code.sessionID,
                DeviceSyncCodec.PAIRING_INFO,
                "poll:${code.sessionID}:$deviceID",
            )
            val poll = LocalPairingHttpClient.request(
                host = code.host,
                port = code.port,
                method = "GET",
                path = "/v2/pair?session=${url(code.sessionID)}" +
                    "&device=${url(deviceID)}&proof=${url(proof)}",
            )
            if (poll.status == 202) continue
            require(poll.status in 200..299) { poll.errorMessage() }
            val response = DeviceSyncCodec.json.decodeFromString<DevicePairPollResponse>(
                poll.body.toString(Charsets.UTF_8),
            )
            require(response.status == "approved") {
                response.message ?: "The Mac did not approve this device."
            }
            require(response.desktopID == code.desktopID) {
                "The responding Mac identity changed during pairing."
            }
            val envelope = response.envelope ?: error("The Mac sent no encrypted settings.")
            val payload = DeviceSyncCodec.decodePayload(
                DeviceSyncCrypto.open(
                    envelope,
                    sharedSecret,
                    code.sessionID,
                    DeviceSyncCodec.PAIRING_INFO,
                ),
            )
            val connections = payload.connections
            return DevicePairingResult(
                payload = payload,
                trustedDevice = TrustedDesktopDevice(
                    desktopID = code.desktopID,
                    desktopName = response.desktopName ?: code.desktopName,
                    host = code.host,
                    port = code.port,
                    desktopPublicKey = DeviceSyncCodec.base64URLEncode(code.desktopPublicKey),
                    deviceID = deviceID,
                    deviceName = deviceName,
                    privateKey = DeviceSyncCodec.base64URLEncode(keyPair.private.encoded),
                    devicePublicKey = DeviceSyncCodec.base64URLEncode(
                        DeviceSyncCrypto.rawPublicKey(keyPair.public),
                    ),
                    pairedAtEpochMs = System.currentTimeMillis(),
                    openAITokenHash = DeviceSyncCodec.credentialHash(
                        connections?.openAISessionToken,
                    ),
                    cursorTokenHash = DeviceSyncCodec.credentialHash(
                        connections?.cursorSessionToken,
                    ),
                    elevenLabsKeyHash = DeviceSyncCodec.credentialHash(
                        connections?.elevenLabsAPIKey,
                    ),
                ),
            )
        }
        error("The pairing request expired. Generate a new code on your Mac.")
    }

    fun checkStatus(device: TrustedDesktopDevice): DeviceStatusCommand {
        val secret = DeviceSyncCrypto.sharedSecret(
            DeviceSyncCrypto.restorePrivateKey(device.privateKey),
            DeviceSyncCodec.base64URLDecode(device.desktopPublicKey),
        )
        val timestamp = System.currentTimeMillis() / 1_000
        val proof = DeviceSyncCrypto.authenticationProof(
            secret,
            device.desktopID,
            DeviceSyncCodec.STATUS_INFO,
            "status:${device.desktopID}:${device.deviceID}:$timestamp",
        )
        val response = LocalPairingHttpClient.request(
            host = device.host,
            port = device.port,
            method = "GET",
            path = "/v2/status?desktop=${url(device.desktopID)}" +
                "&device=${url(device.deviceID)}&ts=$timestamp&proof=${url(proof)}",
            connectTimeoutMs = 1_500,
            readTimeoutMs = 3_000,
        )
        require(response.status in 200..299) { response.errorMessage() }
        val envelope = DeviceSyncCodec.json.decodeFromString<DeviceEncryptedEnvelope>(
            response.body.toString(Charsets.UTF_8),
        )
        val plaintext = DeviceSyncCrypto.open(
            envelope,
            secret,
            device.desktopID,
            DeviceSyncCodec.STATUS_INFO,
        )
        return DeviceSyncCodec.json.decodeFromString<DeviceStatusCommand>(
            plaintext.toString(Charsets.UTF_8),
        )
    }

    fun acknowledgeWipe(device: TrustedDesktopDevice) {
        val secret = DeviceSyncCrypto.sharedSecret(
            DeviceSyncCrypto.restorePrivateKey(device.privateKey),
            DeviceSyncCodec.base64URLDecode(device.desktopPublicKey),
        )
        val timestamp = System.currentTimeMillis() / 1_000
        val acknowledgement = DeviceWipeAcknowledgement(
            desktopID = device.desktopID,
            deviceID = device.deviceID,
            timestamp = timestamp,
            proof = DeviceSyncCrypto.authenticationProof(
                secret,
                device.desktopID,
                DeviceSyncCodec.STATUS_INFO,
                "wipe-ack:${device.desktopID}:${device.deviceID}:$timestamp",
            ),
        )
        val response = LocalPairingHttpClient.request(
            host = device.host,
            port = device.port,
            method = "POST",
            path = "/v2/status/ack",
            body = DeviceSyncCodec.json.encodeToString(acknowledgement).toByteArray(),
        )
        require(response.status in 200..299) { response.errorMessage() }
    }

    private fun url(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())
}

private data class LocalHTTPResult(
    val status: Int,
    val body: ByteArray,
) {
    fun errorMessage(): String =
        body.toString(Charsets.UTF_8).takeIf { it.isNotBlank() }
            ?: "The Mac could not complete device pairing."
}

private object LocalPairingHttpClient {
    fun request(
        host: String,
        port: Int,
        method: String,
        path: String,
        body: ByteArray = ByteArray(0),
        connectTimeoutMs: Int = 5_000,
        readTimeoutMs: Int = 8_000,
    ): LocalHTTPResult {
        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), connectTimeoutMs)
            socket.soTimeout = readTimeoutMs
            val headers = buildString {
                append("$method $path HTTP/1.1\r\n")
                append("Host: $host:$port\r\n")
                append("Content-Type: application/json\r\n")
                append("Content-Length: ${body.size}\r\n")
                append("Connection: close\r\n\r\n")
            }.toByteArray()
            socket.getOutputStream().apply {
                write(headers)
                write(body)
                flush()
            }
            val bytes = ByteArrayOutputStream()
            val chunk = ByteArray(8_192)
            while (true) {
                val read = socket.getInputStream().read(chunk)
                if (read < 0) break
                bytes.write(chunk, 0, read)
            }
            val response = bytes.toByteArray()
            val separator = "\r\n\r\n".toByteArray()
            val bodyIndex = response.indexOfSubArray(separator)
            require(bodyIndex >= 0) { "The Mac returned an invalid response." }
            val header = response.copyOfRange(0, bodyIndex).toString(Charsets.UTF_8)
            val status = header.lineSequence().first().split(" ").getOrNull(1)?.toIntOrNull()
                ?: error("The Mac returned an invalid status.")
            return LocalHTTPResult(
                status,
                response.copyOfRange(bodyIndex + separator.size, response.size),
            )
        }
    }

    private fun ByteArray.indexOfSubArray(needle: ByteArray): Int {
        for (index in 0..size - needle.size) {
            if (needle.indices.all { this[index + it] == needle[it] }) return index
        }
        return -1
    }
}
