package com.miband.app.mibandapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.bouncycastle.asn1.sec.SECNamedCurves
import org.bouncycastle.crypto.agreement.ECDHBasicAgreement
import org.bouncycastle.crypto.generators.ECKeyPairGenerator
import org.bouncycastle.crypto.params.ECDomainParameters
import org.bouncycastle.crypto.params.ECKeyGenerationParameters
import org.bouncycastle.crypto.params.ECPrivateKeyParameters
import org.bouncycastle.crypto.params.ECPublicKeyParameters
import org.bouncycastle.jce.provider.BouncyCastleProvider
import java.math.BigInteger
import java.security.SecureRandom
import java.security.Security

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.miband.app/crypto"

    companion object {
        init {
            Security.removeProvider("BC")
            Security.addProvider(BouncyCastleProvider())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateEcdhKeys" -> {
                    try {
                        val x9 = SECNamedCurves.getByName("sect163r1")
                        val domainParams = ECDomainParameters(x9.curve, x9.g, x9.n, x9.h)
                        val generator = ECKeyPairGenerator()
                        generator.init(ECKeyGenerationParameters(domainParams, SecureRandom()))
                        val keyPair = generator.generateKeyPair()

                        val priv = keyPair.private as ECPrivateKeyParameters
                        val pub = keyPair.public as ECPublicKeyParameters

                        val privBytes = toByteArrayPadded(priv.d, 24)
                        val pubX = toByteArrayPadded(pub.q.affineXCoord.toBigInteger(), 24)
                        val pubY = toByteArrayPadded(pub.q.affineYCoord.toBigInteger(), 24)
                        val pubBytes = pubX + pubY // 48 bytes uncompressed X+Y

                        result.success(mapOf(
                            "privateKey" to bytesToHex(privBytes),
                            "publicKey" to bytesToHex(pubBytes)
                        ))
                    } catch (e: Exception) {
                        result.error("CRYPTO_ERR", e.message, null)
                    }
                }
                "computeSharedSecret" -> {
                    try {
                        val privHex = call.argument<String>("privateKey") ?: ""
                        val pubHex = call.argument<String>("publicKey") ?: ""

                        val privBytes = hexToBytes(privHex)
                        val pubBytes = hexToBytes(pubHex)

                        val x9 = SECNamedCurves.getByName("sect163r1")
                        val domainParams = ECDomainParameters(x9.curve, x9.g, x9.n, x9.h)

                        val privD = BigInteger(1, privBytes)
                        val xBytes = pubBytes.copyOfRange(0, 24)
                        val yBytes = pubBytes.copyOfRange(24, 48)
                        val pubPoint = x9.curve.createPoint(BigInteger(1, xBytes), BigInteger(1, yBytes))

                        val sharedPoint = pubPoint.multiply(privD).normalize()
                        val secX = toByteArrayPadded(sharedPoint.affineXCoord.toBigInteger(), 24)
                        val secY = toByteArrayPadded(sharedPoint.affineYCoord.toBigInteger(), 24)
                        val secBytes = secX + secY // 48 bytes X+Y

                        result.success(mapOf(
                            "sharedSecret" to bytesToHex(secBytes)
                        ))
                    } catch (e: Exception) {
                        result.error("CRYPTO_ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun toByteArrayPadded(bi: BigInteger, length: Int): ByteArray {
        val b = bi.toByteArray()
        val res = ByteArray(length)
        if (b.size >= length) {
            System.arraycopy(b, b.size - length, res, 0, length)
        } else {
            System.arraycopy(b, 0, res, length - b.size, b.size)
        }
        return res
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }

    private fun hexToBytes(s: String): ByteArray {
        val len = s.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(s[i], 16) shl 4) + Character.digit(s[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }
}
