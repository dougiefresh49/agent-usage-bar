package com.agentusagebar.android.data.sync

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.math.BigInteger
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

@Serializable
data class DeviceSyncGeneral(
    val pollingMinutes: Int,
)

@Serializable
data class DeviceSyncAppearance(
    val preferredProvider: String,
    val menuBarStyle: String,
    val primaryMetric: String,
    val secondaryMetric: String,
    val detailStyle: String,
    val textSize: String,
)

@Serializable
data class DeviceSyncNotifications(
    val claudeSession: Int,
    val claudeSevenDay: Int,
    val claudeFable: Int,
    val openAIWeekly: Int,
    val openAIResetCredits: Int,
    val cursorAPI: Int,
    val cursorAuto: Int,
    val cursorCredit: Int,
)

@Serializable
data class DeviceSyncConnections(
    val openAISessionToken: String? = null,
    val cursorSessionToken: String? = null,
    val elevenLabsAPIKey: String? = null,
) {
    val count: Int
        get() = listOf(openAISessionToken, cursorSessionToken, elevenLabsAPIKey)
            .count { !it.isNullOrBlank() }
}

@Serializable
data class DeviceSyncPayload(
    val version: Int,
    val issuedAtEpochSeconds: Long,
    val expiresAtEpochSeconds: Long,
    val general: DeviceSyncGeneral? = null,
    val appearance: DeviceSyncAppearance? = null,
    val notifications: DeviceSyncNotifications? = null,
    val connections: DeviceSyncConnections? = null,
)

data class DevicePairingCode(
    val sessionID: String,
    val host: String,
    val port: Int,
    val desktopID: String,
    val desktopName: String,
    val desktopPublicKey: ByteArray,
)

@Serializable
data class DevicePairRequest(
    val sessionID: String,
    val deviceID: String,
    val deviceName: String,
    val publicKey: String,
)

@Serializable
data class DevicePairStartResponse(
    val status: String,
    val confirmationCode: String,
)

@Serializable
data class DevicePairPollResponse(
    val status: String,
    val desktopID: String? = null,
    val desktopName: String? = null,
    val envelope: DeviceEncryptedEnvelope? = null,
    val message: String? = null,
)

@Serializable
data class DeviceEncryptedEnvelope(
    val nonce: String,
    val ciphertext: String,
    val tag: String,
)

@Serializable
data class DeviceStatusCommand(
    val action: String,
    val issuedAtEpochSeconds: Long,
)

@Serializable
data class DeviceWipeAcknowledgement(
    val desktopID: String,
    val deviceID: String,
    val timestamp: Long,
    val proof: String,
)

object DeviceSyncCodec {
    const val PAIRING_INFO = "agentusagebar-device-pair-v2"
    const val STATUS_INFO = "agentusagebar-device-status-v2"
    const val CURRENT_PAIRING_VERSION = 2
    const val CURRENT_PAYLOAD_VERSION = 1

    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun decodePairingCode(rawValue: String): DevicePairingCode {
        require(rawValue.length <= 4_096) { "This QR code is too large." }
        val uri = runCatching { URI(rawValue) }
            .getOrElse { throw IllegalArgumentException("This is not an Agent Usage Bar pairing code.") }
        require(uri.scheme == "agentusagebar" && uri.host == "pair" && uri.path == "/v2") {
            "This is not an Agent Usage Bar pairing code."
        }
        val query = queryItems(uri.rawQuery)
        require(query["v"]?.toIntOrNull() == CURRENT_PAIRING_VERSION) {
            "Update Agent Usage Bar to use this pairing code."
        }
        val session = query["session"] ?: error("Pairing session is missing.")
        val host = query["host"] ?: error("Mac network address is missing.")
        val port = query["port"]?.toIntOrNull()?.takeIf { it in 1..65_535 }
            ?: error("Pairing port is invalid.")
        val desktop = query["desktop"] ?: error("Mac identity is missing.")
        val name = query["name"] ?: "Mac"
        val key = query["key"]?.let(::base64URLDecode)
            ?: error("Mac public key is missing.")
        require(key.size == 65 && key.first() == 4.toByte()) {
            "Mac public key is invalid."
        }
        return DevicePairingCode(session, host, port, desktop, name, key)
    }

    fun decodePayload(data: ByteArray, nowSeconds: Long = System.currentTimeMillis() / 1_000): DeviceSyncPayload {
        val payload = runCatching {
            json.decodeFromString<DeviceSyncPayload>(data.toString(Charsets.UTF_8))
        }.getOrElse { throw IllegalArgumentException("The transferred settings are damaged.") }
        require(payload.version == CURRENT_PAYLOAD_VERSION) {
            "Update Agent Usage Bar to import these settings."
        }
        require(payload.expiresAtEpochSeconds >= nowSeconds) {
            "The pairing transfer expired. Generate a new code on your Mac."
        }
        return payload
    }

    fun base64URLEncode(value: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value)

    fun base64URLDecode(value: String): ByteArray = Base64.getUrlDecoder().decode(value)

    fun credentialHash(value: String?): String? = value
        ?.takeIf { it.isNotBlank() }
        ?.let { base64URLEncode(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }

    private fun queryItems(rawQuery: String?): Map<String, String> =
        rawQuery.orEmpty().split("&").mapNotNull { item ->
            val split = item.indexOf('=')
            if (split < 0) null else {
                URLDecoder.decode(item.substring(0, split), StandardCharsets.UTF_8.name()) to
                    URLDecoder.decode(item.substring(split + 1), StandardCharsets.UTF_8.name())
            }
        }.toMap()
}

object DeviceSyncCrypto {
    fun generateDeviceKeyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec("secp256r1"))
        }.generateKeyPair()

    fun restorePrivateKey(encoded: String): PrivateKey =
        KeyFactory.getInstance("EC").generatePrivate(
            PKCS8EncodedKeySpec(DeviceSyncCodec.base64URLDecode(encoded)),
        )

    fun rawPublicKey(publicKey: PublicKey): ByteArray {
        val ec = publicKey as ECPublicKey
        return byteArrayOf(4) +
            fixedWidth(ec.w.affineX, 32) +
            fixedWidth(ec.w.affineY, 32)
    }

    fun parseRawPublicKey(raw: ByteArray): PublicKey {
        require(raw.size == 65 && raw[0] == 4.toByte()) { "Invalid P-256 public key." }
        val parameters = AlgorithmParameters.getInstance("EC").apply {
            init(ECGenParameterSpec("secp256r1"))
        }.getParameterSpec(ECParameterSpec::class.java)
        val point = ECPoint(
            BigInteger(1, raw.copyOfRange(1, 33)),
            BigInteger(1, raw.copyOfRange(33, 65)),
        )
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, parameters))
    }

    fun sharedSecret(privateKey: PrivateKey, peerPublicKey: ByteArray): ByteArray =
        KeyAgreement.getInstance("ECDH").run {
            init(privateKey)
            doPhase(parseRawPublicKey(peerPublicKey), true)
            generateSecret()
        }

    fun deriveKey(sharedSecret: ByteArray, salt: String, info: String): ByteArray {
        val extract = Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(salt.toByteArray(), "HmacSHA256"))
            doFinal(sharedSecret)
        }
        return Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(extract, "HmacSHA256"))
            doFinal(info.toByteArray() + byteArrayOf(1)).copyOf(32)
        }
    }

    fun confirmationCode(sharedSecret: ByteArray, sessionID: String): String {
        val key = deriveKey(sharedSecret, sessionID, DeviceSyncCodec.PAIRING_INFO)
        val number = (
            ((key[0].toLong() and 0xff) shl 24) or
                ((key[1].toLong() and 0xff) shl 16) or
                ((key[2].toLong() and 0xff) shl 8) or
                (key[3].toLong() and 0xff)
            ) % 1_000_000
        return number.toString().padStart(6, '0')
    }

    fun authenticationProof(
        sharedSecret: ByteArray,
        salt: String,
        info: String,
        message: String,
    ): String {
        val key = deriveKey(sharedSecret, salt, info)
        val proof = Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(message.toByteArray())
        }
        return DeviceSyncCodec.base64URLEncode(proof)
    }

    fun open(
        envelope: DeviceEncryptedEnvelope,
        sharedSecret: ByteArray,
        salt: String,
        info: String,
    ): ByteArray {
        val key = deriveKey(sharedSecret, salt, info)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(key, "AES"),
            GCMParameterSpec(128, DeviceSyncCodec.base64URLDecode(envelope.nonce)),
        )
        return cipher.doFinal(
            DeviceSyncCodec.base64URLDecode(envelope.ciphertext) +
                DeviceSyncCodec.base64URLDecode(envelope.tag),
        )
    }

    private fun fixedWidth(value: BigInteger, size: Int): ByteArray {
        val bytes = value.toByteArray()
        return when {
            bytes.size == size -> bytes
            bytes.size > size -> bytes.copyOfRange(bytes.size - size, bytes.size)
            else -> ByteArray(size - bytes.size) + bytes
        }
    }
}
