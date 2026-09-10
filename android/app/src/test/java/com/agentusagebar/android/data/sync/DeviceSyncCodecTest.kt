package com.agentusagebar.android.data.sync

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URLEncoder

class DeviceSyncCodecTest {
    @Test
    fun decodesPairingCodeWithoutCredentialPayload() {
        val desktopKey = DeviceSyncCrypto.generateDeviceKeyPair()
        val publicKey = DeviceSyncCodec.base64URLEncode(
            DeviceSyncCrypto.rawPublicKey(desktopKey.public),
        )
        val code = DeviceSyncCodec.decodePairingCode(
            "agentusagebar://pair/v2?v=2" +
                "&session=session-123" +
                "&host=192.168.1.10" +
                "&port=48321" +
                "&desktop=desktop-123" +
                "&name=${URLEncoder.encode("Test Mac", "UTF-8")}" +
                "&key=$publicKey",
        )

        assertEquals("session-123", code.sessionID)
        assertEquals("192.168.1.10", code.host)
        assertEquals(48_321, code.port)
        assertEquals("Test Mac", code.desktopName)
        assertEquals(65, code.desktopPublicKey.size)
    }

    @Test
    fun bothSidesDeriveSameSharedSecretAndConfirmationCode() {
        val desktop = DeviceSyncCrypto.generateDeviceKeyPair()
        val phone = DeviceSyncCrypto.generateDeviceKeyPair()
        val desktopSecret = DeviceSyncCrypto.sharedSecret(
            desktop.private,
            DeviceSyncCrypto.rawPublicKey(phone.public),
        )
        val phoneSecret = DeviceSyncCrypto.sharedSecret(
            phone.private,
            DeviceSyncCrypto.rawPublicKey(desktop.public),
        )

        assertTrue(desktopSecret.contentEquals(phoneSecret))
        assertEquals(
            DeviceSyncCrypto.confirmationCode(desktopSecret, "session"),
            DeviceSyncCrypto.confirmationCode(phoneSecret, "session"),
        )
    }

    @Test
    fun hkdfMatchesCrossPlatformProtocolVector() {
        val secret = ByteArray(32) { it.toByte() }

        val derived = DeviceSyncCrypto.deriveKey(
            secret,
            "session",
            DeviceSyncCodec.PAIRING_INFO,
        )

        assertEquals(
            "3231269fb3db3487dedcd8abef9031471e1ee65e2a7b9efe2b69661955c4b964",
            derived.joinToString("") { "%02x".format(it) },
        )
        assertEquals("081951", DeviceSyncCrypto.confirmationCode(secret, "session"))
    }

    @Test
    fun rejectsExpiredTransferredSettings() {
        val json = """
            {"version":1,"issuedAtEpochSeconds":100,"expiresAtEpochSeconds":200}
        """.trimIndent()

        val error = assertThrows(IllegalArgumentException::class.java) {
            DeviceSyncCodec.decodePayload(
                json.toByteArray(),
                nowSeconds = 201,
            )
        }

        assertEquals(
            "The pairing transfer expired. Generate a new code on your Mac.",
            error.message,
        )
    }

    @Test
    fun decodesSyncedPrimaryAndSecondaryStats() {
        val json = """
            {
              "version": 1,
              "issuedAtEpochSeconds": 100,
              "expiresAtEpochSeconds": 300,
              "appearance": {
                "preferredProvider": "cursor",
                "menuBarStyle": "bars",
                "primaryMetric": "cursor.total",
                "secondaryMetric": "cursor.models",
                "detailStyle": "orbit",
                "textSize": "comfortable"
              }
            }
        """.trimIndent()

        val payload = DeviceSyncCodec.decodePayload(
            json.toByteArray(),
            nowSeconds = 200,
        )

        assertEquals("cursor.total", payload.appearance?.primaryMetric)
        assertEquals("cursor.models", payload.appearance?.secondaryMetric)
    }

    @Test
    fun acceptsQueuedResyncAfterOriginalPayloadExpiry() {
        val json = """
            {"version":1,"issuedAtEpochSeconds":100,"expiresAtEpochSeconds":200}
        """.trimIndent()

        val payload = DeviceSyncCodec.decodeResyncPayload(json.toByteArray())

        assertEquals(1, payload.version)
        assertEquals(200, payload.expiresAtEpochSeconds)
    }

    @Test
    fun decodesSyncStatusEnvelope() {
        val json = """
            {
              "action":"sync",
              "issuedAtEpochSeconds":100,
              "syncID":"sync-123",
              "syncEnvelope":{"nonce":"n","ciphertext":"c","tag":"t"}
            }
        """.trimIndent()

        val command = DeviceSyncCodec.json.decodeFromString<DeviceStatusCommand>(json)

        assertEquals("sync", command.action)
        assertEquals("sync-123", command.syncID)
        assertEquals("c", command.syncEnvelope?.ciphertext)
    }

    @Test
    fun v2PayloadWithTokensDecodesAndTokensAreNotStoredOnTrustedDevice() {
        val json = """
            {
              "version": 2,
              "issuedAtEpochSeconds": 100,
              "expiresAtEpochSeconds": 300,
              "connections": {
                "openAISessionToken": "paste-openai",
                "cursorSessionToken": "paste-cursor",
                "elevenLabsAPIKey": "el-key",
                "codexAccessToken": "codex-cli",
                "codexAccountId": "acct-1",
                "cursorAccessToken": "cursor-cli"
              }
            }
        """.trimIndent()

        val payload = DeviceSyncCodec.decodePayload(json.toByteArray(), nowSeconds = 200)
        val connections = payload.connections!!

        assertEquals("codex-cli", connections.codexAccessToken)
        assertEquals("paste-openai", connections.openAISessionToken)
        assertEquals(6, connections.count)

        val device = TrustedDesktopDevice(
            desktopID = "desktop-1",
            desktopName = "Mac",
            host = "100.64.1.5",
            port = 48_321,
            desktopPublicKey = "pk",
            deviceID = "device-1",
            deviceName = "Pixel",
            privateKey = "sk",
            pairedAtEpochMs = 1L,
        )
        assertNull(device.openAITokenHash)
        assertNull(device.cursorTokenHash)
        assertNull(device.elevenLabsKeyHash)
    }

    @Test
    fun v1DecodeLeavesV2ConnectionFieldsNull() {
        val json = """
            {
              "version": 1,
              "issuedAtEpochSeconds": 100,
              "expiresAtEpochSeconds": 300,
              "connections": {
                "openAISessionToken": "paste-openai",
                "cursorSessionToken": "paste-cursor",
                "elevenLabsAPIKey": "el-key"
              }
            }
        """.trimIndent()

        val payload = DeviceSyncCodec.decodePayload(json.toByteArray(), nowSeconds = 200)
        val connections = payload.connections!!

        assertNull(connections.codexAccessToken)
        assertNull(connections.codexAccountId)
        assertNull(connections.cursorAccessToken)
        assertEquals(3, connections.count)
    }

    @Test
    fun rejectsPayloadVersionAboveSupported() {
        val json = """
            {"version":3,"issuedAtEpochSeconds":100,"expiresAtEpochSeconds":300}
        """.trimIndent()

        val error = assertThrows(IllegalArgumentException::class.java) {
            DeviceSyncCodec.decodePayload(json.toByteArray(), nowSeconds = 200)
        }

        assertEquals(
            "Update Agent Usage Bar to import these settings.",
            error.message,
        )
    }

    @Test
    fun sealThenOpenRoundTripsSnapshotInfo() {
        val secret = ByteArray(32) { it.toByte() }
        val envelope = DeviceSyncCrypto.seal(
            "snapshot-body".toByteArray(),
            secret,
            "desktop-1",
            DeviceSyncCodec.SNAPSHOT_INFO,
        )
        val opened = DeviceSyncCrypto.open(
            envelope,
            secret,
            "desktop-1",
            DeviceSyncCodec.SNAPSHOT_INFO,
        )
        assertEquals("snapshot-body", opened.toString(Charsets.UTF_8))
    }

    @Test
    fun decodesFillModeWhenPresent() {
        val json = """
            {
              "version": 1,
              "issuedAtEpochSeconds": 100,
              "expiresAtEpochSeconds": 300,
              "appearance": {
                "preferredProvider": "cursor",
                "menuBarStyle": "bars",
                "primaryMetric": "cursor.total",
                "secondaryMetric": "cursor.models",
                "detailStyle": "orbit",
                "textSize": "comfortable",
                "fillMode": "fill"
              }
            }
        """.trimIndent()

        val payload = DeviceSyncCodec.decodePayload(json.toByteArray(), nowSeconds = 200)
        assertEquals("fill", payload.appearance?.fillMode)
    }

    @Test
    fun missingFillModeDecodesAsNull() {
        val json = """
            {
              "version": 1,
              "issuedAtEpochSeconds": 100,
              "expiresAtEpochSeconds": 300,
              "appearance": {
                "preferredProvider": "cursor",
                "menuBarStyle": "bars",
                "primaryMetric": "cursor.total",
                "secondaryMetric": "cursor.models",
                "detailStyle": "orbit",
                "textSize": "comfortable"
              }
            }
        """.trimIndent()

        val payload = DeviceSyncCodec.decodePayload(json.toByteArray(), nowSeconds = 200)
        assertNull(payload.appearance?.fillMode)
    }
}
