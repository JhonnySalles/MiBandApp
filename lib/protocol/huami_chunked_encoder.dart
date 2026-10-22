import 'dart:typed_data';
import '../core/crypto/crc32.dart';
import '../core/crypto/huami_crypto.dart';

class EncodedChunksResult {
  final List<Uint8List> chunks;
  final int nextEncryptedSeq;

  EncodedChunksResult({required this.chunks, required this.nextEncryptedSeq});
}

class HuamiChunkedEncoder {
  static const int mtu = 23;

  /// Fraciona e empacota mensagens para o protocolo Huami 2021 (canal 0x0016 / endpoint 0x0090 ou 130)
  static EncodedChunksResult encodeChunked2021({
    required int typeEndpoint,
    required Uint8List data,
    required int handle,
    bool encrypt = false,
    Uint8List? sessionKey,
    int encryptedSeq = 0,
  }) {
    Uint8List dataToSend;
    int remaining;
    int nextSeq = encryptedSeq;

    if (encrypt) {
      if (sessionKey == null || sessionKey.length != 16) {
        throw ArgumentError("Session Key de 16 bytes é obrigatória para pacotes criptografados");
      }

      final messageKey = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        messageKey[i] = sessionKey[i] ^ (handle & 0xFF);
      }

      final length = data.length;
      int encryptedLength = length + 8;
      final overflow = encryptedLength % 16;
      if (overflow > 0) {
        encryptedLength += (16 - overflow);
      }

      final encryptablePayload = Uint8List(encryptedLength);
      encryptablePayload.setRange(0, length, data);

      // Sequence number (4 bytes Little Endian)
      final byteData = ByteData.sublistView(encryptablePayload);
      byteData.setUint32(length, nextSeq & 0xFFFFFFFF, Endian.little);
      nextSeq++;

      // CRC32 dos dados + sequência (4 bytes Little Endian)
      final crc = Crc32.compute(encryptablePayload.sublist(0, length + 4));
      byteData.setUint32(length + 4, crc, Endian.little);

      // Criptografia AES-128 ECB
      dataToSend = HuamiCryptoService.encryptAesEcb(encryptablePayload, messageKey);
      remaining = encryptedLength;
    } else {
      dataToSend = data;
      remaining = data.length;
    }

    final chunks = <Uint8List>[];
    int count = 0;
    int headerSize = 11;
    final totalLen = data.length;

    while (remaining > 0) {
      final maxChunk = mtu - 3 - headerSize;
      final copyBytes = remaining < maxChunk ? remaining : maxChunk;
      final chunk = Uint8List(copyBytes + headerSize);

      int flags = encrypt ? 0x08 : 0x00;
      if (count == 0) {
        flags |= 0x01; // primeiro chunk
        chunk[5] = totalLen & 0xFF;
        chunk[6] = (totalLen >> 8) & 0xFF;
        chunk[7] = (totalLen >> 16) & 0xFF;
        chunk[8] = (totalLen >> 24) & 0xFF;
        chunk[9] = typeEndpoint & 0xFF;
        chunk[10] = (typeEndpoint >> 8) & 0xFF;
      }

      if (remaining <= maxChunk) {
        flags |= 0x02; // último chunk
        flags |= 0x04; // requer confirmação/ack
      }

      chunk[0] = 0x03;
      chunk[1] = flags;
      chunk[2] = 0;
      chunk[3] = handle & 0xFF;
      chunk[4] = count & 0xFF;

      final startIdx = dataToSend.length - remaining;
      chunk.setRange(headerSize, headerSize + copyBytes, dataToSend.sublist(startIdx, startIdx + copyBytes));
      chunks.add(chunk);

      remaining -= copyBytes;
      headerSize = 5;
      count++;
    }

    return EncodedChunksResult(chunks: chunks, nextEncryptedSeq: nextSeq);
  }

  /// Fraciona mensagens no padrão Huami Legado (canal 0x0020)
  static List<Uint8List> encodeLegacyChunked(int msgType, Uint8List data) {
    const maxChunk = mtu - 6;
    int remaining = data.length;
    int count = 0;
    final chunks = <Uint8List>[];

    while (remaining > 0) {
      final copyBytes = remaining < maxChunk ? remaining : maxChunk;
      final chunk = Uint8List(copyBytes + 3);
      int flags = 0;

      if (remaining <= maxChunk) {
        flags |= 0x80;
        if (count == 0) flags |= 0x40;
      } else if (count > 0) {
        flags |= 0x40;
      }

      chunk[0] = 0;
      chunk[1] = (flags | msgType) & 0xFF;
      chunk[2] = count & 0xFF;

      final startIdx = count * maxChunk;
      chunk.setRange(3, 3 + copyBytes, data.sublist(startIdx, startIdx + copyBytes));
      chunks.add(chunk);

      remaining -= copyBytes;
      count++;
    }

    return chunks;
  }
}
