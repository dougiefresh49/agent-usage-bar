package com.agentusagebar.android.data.sync

import org.junit.Assert.assertEquals
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
}
