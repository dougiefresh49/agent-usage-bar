package com.agentusagebar.android.data.sync

import com.agentusagebar.android.data.model.ConnectedCredentials
import com.agentusagebar.android.data.model.CursorAuth
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
    fun decodesV2ConnectionsWithCodexAndCursorCliTokens() {
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

        assertEquals(2, payload.version)
        assertEquals("codex-cli", connections.codexAccessToken)
        assertEquals("acct-1", connections.codexAccountId)
        assertEquals("cursor-cli", connections.cursorAccessToken)
        assertEquals(6, connections.count)
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
    fun phonePrecedenceHelpersPreferCliTokens() {
        val both = ConnectedCredentials(
            openAISessionToken = "paste-openai",
            cursorSessionToken = "paste-cursor",
            codexAccessToken = "codex-cli",
            codexAccountId = "acct-1",
            cursorAccessToken = "cursor-cli",
        )

        assertEquals("codex-cli", both.openAIBearer)
        assertEquals("acct-1", both.openAIAccountId)
        assertEquals(CursorAuth.CliToken("cursor-cli"), both.cursorAuth)

        val pastedOnly = ConnectedCredentials(
            openAISessionToken = "paste-openai",
            cursorSessionToken = "paste-cursor",
        )

        assertEquals("paste-openai", pastedOnly.openAIBearer)
        assertNull(pastedOnly.openAIAccountId)
        assertEquals(CursorAuth.Cookie("paste-cursor"), pastedOnly.cursorAuth)
    }

    @Test
    fun mergingImportedV1LeavesExistingV2FieldsUntouched() {
        val current = ConnectedCredentials(
            openAISessionToken = "old-paste",
            codexAccessToken = "keep-cli",
            codexAccountId = "keep-acct",
            cursorAccessToken = "keep-cursor-cli",
        )
        val imported = DeviceSyncConnections(
            openAISessionToken = "new-paste",
            cursorSessionToken = "new-cursor-paste",
        )

        val merged = current.mergingImported(imported)

        assertEquals("new-paste", merged.openAISessionToken)
        assertEquals("new-cursor-paste", merged.cursorSessionToken)
        assertEquals("keep-cli", merged.codexAccessToken)
        assertEquals("keep-acct", merged.codexAccountId)
        assertEquals("keep-cursor-cli", merged.cursorAccessToken)
    }

    @Test
    fun mergingImportedV2OverwritesOwnKeysOnly() {
        val current = ConnectedCredentials(
            openAISessionToken = "old-paste",
            elevenLabsAPIKey = "keep-el",
            codexAccessToken = "old-cli",
        )
        val imported = DeviceSyncConnections(
            codexAccessToken = "new-cli",
            codexAccountId = "new-acct",
            cursorAccessToken = "new-cursor-cli",
        )

        val merged = current.mergingImported(imported)

        assertEquals("old-paste", merged.openAISessionToken)
        assertEquals("keep-el", merged.elevenLabsAPIKey)
        assertEquals("new-cli", merged.codexAccessToken)
        assertEquals("new-acct", merged.codexAccountId)
        assertEquals("new-cursor-cli", merged.cursorAccessToken)
    }
}
