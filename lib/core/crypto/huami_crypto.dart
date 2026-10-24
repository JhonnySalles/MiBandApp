import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

class HuamiCryptoService {
  static const MethodChannel _cryptoChannel = MethodChannel('com.miband.app/crypto');

  /// Gera par de chaves ECDH na curva sect163r2 (NIST B-163 - Huami 2021)
  /// Retorna: { 'privateKey': Uint8List (24 bytes Little-Endian), 'publicKey': Uint8List (48 bytes Little-Endian) }
  static Future<Map<String, Uint8List>> generateEcdhKeys() async {
    try {
      final res = await _cryptoChannel.invokeMapMethod<String, dynamic>('generateEcdhKeys');
      if (res != null && res.containsKey('privateKey') && res.containsKey('publicKey')) {
        return {
          'privateKey': _hexToBytes(res['privateKey'] as String),
          'publicKey': _hexToBytes(res['publicKey'] as String),
        };
      }
      throw StateError("Canal nativo não retornou as chaves ECDH esperadas");
    } on MissingPluginException {
      throw UnsupportedError("Plugin nativo de criptografia ECDH B-163 não está disponível nesta plataforma");
    } catch (e) {
      throw StateError("Falha ao gerar chaves ECDH B-163 nativas: $e");
    }
  }

  /// Calcula o segredo compartilhado ECDH B-163 entre a chave privada local e a chave pública remota
  /// Retorna: Uint8List (48 bytes Little-Endian)
  static Future<Uint8List> computeSharedSecret(Uint8List privateKey, Uint8List remotePublicKey) async {
    try {
      final res = await _cryptoChannel.invokeMapMethod<String, dynamic>('computeSharedSecret', {
        'privateKey': _bytesToHex(privateKey),
        'publicKey': _bytesToHex(remotePublicKey),
      });
      if (res != null && res.containsKey('sharedSecret')) {
        return _hexToBytes(res['sharedSecret'] as String);
      }
      throw StateError("Canal nativo não retornou o segredo compartilhado ECDH");
    } on MissingPluginException {
      throw UnsupportedError("Plugin nativo de criptografia ECDH B-163 não está disponível nesta plataforma");
    } catch (e) {
      throw StateError("Falha ao computar segredo compartilhado ECDH B-163 nativo: $e");
    }
  }

  /// Deriva a session_key de 16 bytes a partir do segredo ECDH e da authKey do usuário
  static Uint8List deriveSessionKey(Uint8List sharedSecret, Uint8List authKey) {
    final sessionKey = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      sessionKey[i] = sharedSecret[i + 8] ^ authKey[i];
    }
    return sessionKey;
  }

  /// Extrai a sequência inicial criptográfica (uint32 Little Endian dos primeiros 4 bytes do segredo)
  static int extractInitialSeq(Uint8List sharedSecret) {
    final byteData = ByteData.sublistView(sharedSecret);
    return byteData.getUint32(0, Endian.little);
  }

  /// Criptografia AES-128 no modo ECB (sem padding / blocos de 16 bytes)
  static Uint8List encryptAesEcb(Uint8List data, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine());
    cipher.init(true, KeyParameter(key));

    final output = Uint8List(data.length);
    for (int offset = 0; offset < data.length; offset += 16) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  /// Descriptografia AES-128 no modo ECB
  static Uint8List decryptAesEcb(Uint8List data, Uint8List key) {
    final cipher = ECBBlockCipher(AESEngine());
    cipher.init(false, KeyParameter(key));

    final output = Uint8List(data.length);
    for (int offset = 0; offset < data.length; offset += 16) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  /// Criptografia AES-128 no modo CBC com IV nulo (usado na autenticação Huami 2021)
  static Uint8List encryptAesCbcZeroIv(Uint8List data, Uint8List key) {
    final zeroIv = Uint8List(16);
    final cipher = CBCBlockCipher(AESEngine());
    final params = ParametersWithIV(KeyParameter(key), zeroIv);
    cipher.init(true, params);

    final output = Uint8List(data.length);
    for (int offset = 0; offset < data.length; offset += 16) {
      cipher.processBlock(data, offset, output, offset);
    }
    return output;
  }

  // Helpers de conversão
  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '').replaceAll('0x', '');
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}


