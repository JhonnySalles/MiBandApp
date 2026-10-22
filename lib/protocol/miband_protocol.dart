import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants/ble_constants.dart';
import '../core/crypto/huami_crypto.dart';
import '../models/weather_data.dart';
import '../models/alarm_item.dart';
import 'huami_chunked_encoder.dart';
import 'huami_weather_encoder.dart';

typedef TraceLogger = void Function(String level, String message);

class MiBandProtocol {
  final BluetoothDevice device;
  final Uint8List? authKey;
  TraceLogger? onTrace;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  Uint8List? sessionKey;
  int _encryptedSeq = 0;
  int _writeHandle = 0;

  // Cache de características descobertas
  final Map<String, BluetoothCharacteristic> _charMap = {};

  MiBandProtocol(this.device, String authKeyHex, {this.onTrace})
      : authKey = _parseAuthKey(authKeyHex);

  static Uint8List? _parseAuthKey(String hex) {
    String clean = hex.trim();
    if (clean.startsWith("0x") || clean.startsWith("0X")) {
      clean = clean.substring(2);
    }
    if (clean.length != 32) return null;
    final res = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      res[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return res;
  }

  void _trace(String level, String msg) {
    onTrace?.call(level, msg);
  }

  Future<void> discoverServices() async {
    _charMap.clear();
    final services = await device.discoverServices();
    for (final s in services) {
      for (final c in s.characteristics) {
        _charMap[c.uuid.toString().toLowerCase()] = c;
      }
    }
  }

  BluetoothCharacteristic? _findChar(String uuid) {
    return _charMap[uuid.toLowerCase()];
  }

  /// Autentica na pulseira (Huami 2021 ECDH B-163 ou Legado AES)
  Future<bool> authenticate() async {
    if (authKey == null) {
      _trace("ERROR", "Auth Key inválida (deve conter 32 caracteres hexadecimais).");
      return false;
    }

    if (_charMap.isEmpty) {
      await discoverServices();
    }

    final hasChunkedWrite = _findChar(BleConstants.uuidCharChunkedWrite) != null;
    final hasChunkedRead = _findChar(BleConstants.uuidCharChunkedRead) != null;

    if (hasChunkedWrite && hasChunkedRead) {
      _trace("INFO", "Protocolo Huami 2021 detectado. Iniciando handshake ECDH B-163...");
      return await _authenticateEcdh2021();
    } else {
      _trace("INFO", "Executando autenticação legado Huami (AES-ECB)...");
      return await _authenticateLegacyHuami();
    }
  }

  // -------------------------------------------------------------
  // Handshake Huami 2021 ECDH B-163 (Mi Band 6 / 7)
  // -------------------------------------------------------------
  Future<bool> _authenticateEcdh2021() async {
    final charRead = _findChar(BleConstants.uuidCharChunkedRead);
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charRead == null || charWrite == null) return false;

    try {
      final keys = await HuamiCryptoService.generateEcdhKeys();
      final privKey = keys['privateKey']!;
      final pubKey = keys['publicKey']!;

      final authCompleter = Completer<bool>();
      final reassembleBuf = <int>[];
      int expectedBytes = 0;
      int lastSeq = -1;
      StreamSubscription? sub;

      await charRead.setNotifyValue(true);
      sub = charRead.onValueReceived.listen((data) async {
        if (data.length <= 1 || data[0] != 3) return;
        final seq = data[4];

        // Resposta ao desafio (etapa 1 da pulseira: 4, 1)
        if (seq == 0 && data.length >= 14 &&
            data[9] == BleConstants.chunked2021EndpointAuth && data[10] == 0 &&
            data[11] == 16 && data[12] == 4 && data[13] == 1) {
          reassembleBuf.clear();
          expectedBytes = data[5] - 3;
          lastSeq = 0;
          reassembleBuf.addAll(data.sublist(14));
          _trace("INFO", "Desafio inicial recebido da pulseira (esperando $expectedBytes bytes)...");
        } else if (seq > 0 && seq == lastSeq + 1) {
          lastSeq = seq;
          reassembleBuf.addAll(data.sublist(5));
        } else if (data.length >= 14 &&
            data[9] == BleConstants.chunked2021EndpointAuth && data[10] == 0 &&
            data[11] == 16 && data[12] == 5 && data[13] == 1) {
          _trace("INFO", "Mi Smart Band autenticada com SUCESSO via ECDH B-163!");
          if (data.length >= 18) {
            final bd = ByteData.sublistView(Uint8List.fromList(data.sublist(14, 18)));
            _encryptedSeq = bd.getUint32(0, Endian.little);
          }
          if (!authCompleter.isCompleted) authCompleter.complete(true);
          return;
        }

        // Processar assim que todos os bytes chegarem
        if (expectedBytes > 0 && reassembleBuf.length >= expectedBytes) {
          final remoteRandom = Uint8List.fromList(reassembleBuf.sublist(0, 16));
          final remotePublic = Uint8List.fromList(reassembleBuf.sublist(16, 64));

          try {
            final sharedSecret = await HuamiCryptoService.computeSharedSecret(privKey, remotePublic);
            sessionKey = HuamiCryptoService.deriveSessionKey(sharedSecret, authKey!);
            _encryptedSeq = HuamiCryptoService.extractInitialSeq(sharedSecret);
            _trace("INFO", "Chave de sessão derivada com sucesso.");

            // Criptografar nonce com AES-CBC (IV nulo)
            final out1 = HuamiCryptoService.encryptAesCbcZeroIv(remoteRandom, authKey!);
            final out2 = HuamiCryptoService.encryptAesCbcZeroIv(remoteRandom, sessionKey!);

            final cmd = BytesBuilder();
            cmd.addByte(0x05);
            cmd.add(out1);
            cmd.add(out2);

            _writeHandle = (_writeHandle + 1) & 0xFF;
            final res = HuamiChunkedEncoder.encodeChunked2021(
              typeEndpoint: BleConstants.chunked2021EndpointAuth,
              data: cmd.toBytes(),
              handle: _writeHandle,
            );

            _trace("INFO", "Transmitindo segunda etapa de autenticação criptografada...");
            for (final chunk in res.chunks) {
              await charWrite.write(chunk, withoutResponse: true);
              await Future.delayed(const Duration(milliseconds: 35));
            }
            expectedBytes = 0;
          } catch (e) {
            _trace("ERROR", "Erro no cálculo criptográfico ECDH: $e");
            if (!authCompleter.isCompleted) authCompleter.complete(false);
          }
        }
      });

      // Enviar primeiro comando: [4, 2, 0, 2] + pubKey
      final initCmd = BytesBuilder();
      initCmd.add([4, 2, 0, 2]);
      initCmd.add(pubKey);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointAuth,
        data: initCmd.toBytes(),
        handle: _writeHandle,
      );

      _trace("INFO", "Enviando chave pública efêmera para a pulseira...");
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }

      final success = await authCompleter.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
      _isAuthenticated = success;
      await sub.cancel();
      return success;
    } catch (e) {
      _trace("WARN", "Falha na autenticação ECDH 2021: $e");
      return false;
    }
  }

  // -------------------------------------------------------------
  // Handshake Huami Legado (Mi Band 2 / 3 / 4 / 5)
  // -------------------------------------------------------------
  Future<bool> _authenticateLegacyHuami() async {
    final charAuth = _findChar(BleConstants.uuidCharAuth);
    if (charAuth == null) return false;

    try {
      final authCompleter = Completer<bool>();
      StreamSubscription? sub;

      await charAuth.setNotifyValue(true);
      sub = charAuth.onValueReceived.listen((data) async {
        if (data.length >= 3) {
          if (data[0] == 0x10 && data[1] == 0x02 && data[2] == 0x01) {
            // Desafio recebido
            final randomChallenge = Uint8List.fromList(data.sublist(3, 19));
            final encrypted = HuamiCryptoService.encryptAesEcb(randomChallenge, authKey!);

            final resp = BytesBuilder();
            resp.add([0x03, 0x08]);
            resp.add(encrypted);
            await charAuth.write(resp.toBytes(), withoutResponse: true);
          } else if (data[0] == 0x10 && data[1] == 0x03 && data[2] == 0x01) {
            _trace("INFO", "Autenticação legada Huami concluída com SUCESSO!");
            if (!authCompleter.isCompleted) authCompleter.complete(true);
          } else if (data[0] == 0x10 && (data[1] == 0x03 || data[1] == 0x02) && data[2] == 0x07) {
            // Pareamento necessário
            final pairPkt = BytesBuilder();
            pairPkt.add([0x01, 0x08]);
            pairPkt.add(authKey!);
            await charAuth.write(pairPkt.toBytes(), withoutResponse: true);
          } else if (data[0] == 0x10 && data[2] == 0x81) {
            if (!authCompleter.isCompleted) authCompleter.complete(false);
          }
        }
      });

      // Solicitar desafio: [0x02, 0x08]
      await charAuth.write([0x02, 0x08], withoutResponse: true);
      final success = await authCompleter.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
      _isAuthenticated = success;
      await sub.cancel();
      return success;
    } catch (e) {
      _trace("WARN", "Falha na autenticação legado: $e");
      return false;
    }
  }

  // -------------------------------------------------------------
  // Operações de Leitura
  // -------------------------------------------------------------
  Future<Map<String, int>> readSteps() async {
    final charSteps = _findChar(BleConstants.uuidCharSteps);
    if (charSteps == null) return {'steps': 0, 'distance_meters': 0, 'calories': 0};

    try {
      final val = await charSteps.read();
      if (val.length >= 13) {
        final bd = ByteData.sublistView(Uint8List.fromList(val));
        final steps = bd.getUint32(1, Endian.little);
        final meters = bd.getUint32(5, Endian.little);
        final calories = bd.getUint32(9, Endian.little);
        _trace("INFO", "Passos lidos: $steps | Distância: ${meters}m | Calorias: $calories kcal");
        return {'steps': steps, 'distance_meters': meters, 'calories': calories};
      }
    } catch (e) {
      _trace("WARN", "Erro ao ler passos: $e");
    }
    return {'steps': 0, 'distance_meters': 0, 'calories': 0};
  }

  Future<int?> readBattery() async {
    final charStd = _findChar(BleConstants.uuidCharBatteryStandard);
    if (charStd != null) {
      try {
        final val = await charStd.read();
        if (val.isNotEmpty) return val[0];
      } catch (_) {}
    }

    final charLegacy = _findChar(BleConstants.uuidCharBatteryLegacy);
    if (charLegacy != null) {
      try {
        final val = await charLegacy.read();
        if (val.length >= 2) return val[1];
      } catch (_) {}
    }
    return null;
  }

  Future<bool> syncTime([DateTime? customTime]) async {
    final charTime = _findChar(BleConstants.uuidCharCurrentTime);
    if (charTime == null) return false;

    try {
      final now = customTime ?? DateTime.now();
      final tzOffsetSec = now.timeZoneOffset.inSeconds;
      final tzQuarters = tzOffsetSec ~/ 900;

      final b = BytesBuilder();
      final bd = ByteData(2)..setUint16(0, now.year, Endian.little);
      b.add(bd.buffer.asUint8List());
      b.addByte(now.month);
      b.addByte(now.day);
      b.addByte(now.hour);
      b.addByte(now.minute);
      b.addByte(now.second);
      b.addByte(now.weekday);
      b.addByte(0);
      b.addByte(0);
      b.addByte(tzQuarters & 0xFF);

      await charTime.write(b.toBytes(), withoutResponse: false);
      _trace("INFO", "Horário sincronizado com a Mi Band: ${now.toIso8601String()}");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao sincronizar horário: $e");
      return false;
    }
  }

  Future<int?> measureHeartRate({Duration timeout = const Duration(seconds: 15)}) async {
    final charMeasure = _findChar(BleConstants.uuidCharHeartRateMeasure);
    final charControl = _findChar(BleConstants.uuidCharHeartRateControl);
    if (charMeasure == null || charControl == null) return null;

    int? resultBpm;
    final completer = Completer<int?>();
    StreamSubscription? sub;

    try {
      await charMeasure.setNotifyValue(true);
      sub = charMeasure.onValueReceived.listen((data) {
        if (data.length >= 2) {
          final is16Bit = (data[0] & 0x01) == 1;
          final bpm = is16Bit && data.length >= 3
              ? (data[1] | (data[2] << 8))
              : data[1];

          if (bpm > 0) {
            _trace("INFO", "Leitura de Batimentos recebida: $bpm BPM");
            if (!completer.isCompleted) completer.complete(bpm);
          }
        }
      });

      // Configurar monitoramento e iniciar medição manual imediata: [0x15, 0x02, 0x01]
      await charControl.write([0x14, 0x05], withoutResponse: false);
      await charControl.write([0x15, 0x02, 0x01], withoutResponse: false);

      resultBpm = await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      _trace("WARN", "Erro durante medição de frequência cardíaca: $e");
    } finally {
      try {
        await charControl.write([0x15, 0x02, 0x00], withoutResponse: false);
        await sub?.cancel();
      } catch (_) {}
    }
    return resultBpm;
  }

  Future<bool> triggerVibrate({int count = 1, String text = "Localizar"}) async {
    final charControl = _findChar(BleConstants.uuidCharAlertControl);
    final charNewAlert = _findChar(BleConstants.uuidCharNewAlert);
    final charAlert = _findChar(BleConstants.uuidCharAlert);

    try {
      if (charControl != null) {
        await charControl.write([0x00, 0xFF], withoutResponse: false);
      }
    } catch (_) {}

    final msgBytes = utf8.encode(text);
    bool vibrated = false;

    for (int i = 0; i < count; i++) {
      if (charNewAlert != null) {
        try {
          final p = BytesBuilder();
          p.add([0x03, 0x01]);
          p.add(msgBytes.take(18).toList());
          await charNewAlert.write(p.toBytes(), withoutResponse: false);
          vibrated = true;
        } catch (_) {}
      }

      if (charAlert != null) {
        try {
          await charAlert.write([0x02], withoutResponse: true);
          vibrated = true;
        } catch (_) {}
      }

      if (i < count - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return vibrated;
  }

  Future<bool> sendNotification({int category = 3, String title = "MiBand", String text = "Teste"}) async {
    final charNewAlert = _findChar(BleConstants.uuidCharNewAlert);
    final charControl = _findChar(BleConstants.uuidCharAlertControl);
    if (charNewAlert == null) return false;

    try {
      if (charControl != null) {
        await charControl.write([0x00, 0xFF], withoutResponse: false);
      }

      final msg = title.isNotEmpty ? "$title: $text" : text;
      final p = BytesBuilder();
      p.add([category & 0xFF, 0x01]);
      p.add(utf8.encode(msg).take(36).toList());

      await charNewAlert.write(p.toBytes(), withoutResponse: false);
      _trace("INFO", "Notificação transmitida à tela da pulseira: '$msg'");
      return true;
    } catch (e) {
      _trace("WARN", "Erro ao enviar notificação: $e");
      return false;
    }
  }

  Future<bool> sendWeather(WeatherData weather) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    final charOld = _findChar(BleConstants.uuidCharChunkedOld);

    try {
      await syncTime();
      await Future.delayed(const Duration(milliseconds: 300));

      final packets = HuamiWeatherEncoder.generateWeatherPackets(weather);

      if (sessionKey != null && charWrite != null) {
        _trace("INFO", "Transmitindo pacotes de clima no canal 0x0090 (Huami 2021 Chunked)...");
        for (final pkt in packets) {
          final cmd = BytesBuilder();
          cmd.add([0x00, 0x00, 0xC1, 0x00]);
          cmd.add(pkt.payload);

          _writeHandle = (_writeHandle + 1) & 0xFF;
          final enc = HuamiChunkedEncoder.encodeChunked2021(
            typeEndpoint: BleConstants.chunked2021EndpointCompat,
            data: cmd.toBytes(),
            handle: _writeHandle,
            encrypt: pkt.shouldEncrypt,
            sessionKey: sessionKey,
            encryptedSeq: _encryptedSeq,
          );
          _encryptedSeq = enc.nextEncryptedSeq;

          for (final chunk in enc.chunks) {
            await charWrite.write(chunk, withoutResponse: true);
            await Future.delayed(const Duration(milliseconds: 40));
          }
          await Future.delayed(const Duration(milliseconds: 120));
        }
      } else if (charOld != null) {
        _trace("INFO", "Transmitindo clima no canal legado 0x0020...");
        for (final pkt in packets) {
          final chunks = HuamiChunkedEncoder.encodeLegacyChunked(1, pkt.payload);
          for (final chunk in chunks) {
            await charOld.write(chunk, withoutResponse: true);
            await Future.delayed(const Duration(milliseconds: 40));
          }
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }
      _trace("INFO", "Previsão do tempo transmitida com sucesso para a Mi Band!");
      return true;
    } catch (e) {
      _trace("ERROR", "Falha ao enviar clima para a pulseira: $e");
      return false;
    }
  }

  Future<List<AlarmItem>> requestAlarms({Duration timeout = const Duration(seconds: 6)}) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    final charRead = _findChar(BleConstants.uuidCharChunkedRead);
    final alarmsList = <AlarmItem>[];
    if (charWrite == null || charRead == null || sessionKey == null) return alarmsList;

    final completer = Completer<List<AlarmItem>>();
    StreamSubscription? sub;

    try {
      await charRead.setNotifyValue(true);
      sub = charRead.onValueReceived.listen((data) {
        if (data.length < 4) return;
        try {
          if (data.length >= 8) {
            final nr = (data.length > 8 && data[0] == 0x10) ? data[8] : (data.length - 1) ~/ 4;
            for (int i = 0; i < (nr < 10 ? nr : 10); i++) {
              final offset = (data[0] == 0x10) ? (9 + i) : (i * 4 + 1);
              if (offset + 3 < data.length) {
                final alarmRaw = data[offset];
                final idx = alarmRaw & 0x0F;
                final enabled = (alarmRaw & 0x80) != 0 || (alarmRaw & 0x10) != 0;
                final hr = data[offset + 1];
                final mi = data[offset + 2];
                final rep = data[offset + 3];
                alarmsList.add(AlarmItem(
                  index: idx,
                  time: "${hr.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}",
                  enabled: enabled,
                  repetition: rep,
                ));
              }
            }
            if (!completer.isCompleted) completer.complete(alarmsList);
          }
        } catch (_) {}
      });

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: Uint8List.fromList([0x01, 0x02]),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;

      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 40));
      }

      return await completer.future.timeout(timeout, onTimeout: () => alarmsList);
    } catch (e) {
      _trace("WARN", "Falha ao consultar alarmes: $e");
      return alarmsList;
    } finally {
      await sub?.cancel();
    }
  }
}
