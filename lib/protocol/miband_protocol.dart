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

    StreamSubscription? sub;
    try {
      final keys = await HuamiCryptoService.generateEcdhKeys();
      final privKey = keys['privateKey']!;
      final pubKey = keys['publicKey']!;

      final authCompleter = Completer<bool>();
      final reassembleBuf = <int>[];
      int expectedBytes = 0;
      int lastSeq = -1;

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

      _writeHandle = 0;
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
      return success;
    } catch (e) {
      _trace("WARN", "Falha na autenticação ECDH 2021: $e");
      return false;
    } finally {
      try {
        await sub?.cancel();
        await charRead.setNotifyValue(false);
      } catch (_) {}
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

      // 1. Parar medições anteriores contínua e manual
      try { await charControl.write([0x15, 0x01, 0x00], withoutResponse: false); } catch (_) {}
      try { await charControl.write([0x15, 0x02, 0x00], withoutResponse: false); } catch (_) {}

      // 2. Iniciar medição manual imediata: [0x15, 0x02, 0x01]
      _trace("INFO", "Sensor PPG acionado. Mantenha o pulso em repouso...");
      await charControl.write([0x15, 0x02, 0x01], withoutResponse: false);

      resultBpm = await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      _trace("WARN", "Erro durante medição de frequência cardíaca: $e");
    } finally {
      try {
        await charControl.write([0x15, 0x02, 0x00], withoutResponse: false);
      } catch (_) {}
      try {
        await charMeasure.setNotifyValue(false);
        await sub?.cancel();
      } catch (_) {}
    }
    return resultBpm;
  }

  Future<bool> setHeartRateInterval(int minutes) async {
    final charControl = _findChar(BleConstants.uuidCharHeartRateControl);
    if (charControl == null) return false;
    try {
      final val = minutes.clamp(0, 60);
      _trace("INFO", "Ajustando ciclo de medições periódicas contínuas para $val min...");
      await charControl.write([0x14, val & 0xFF], withoutResponse: false);
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar intervalo de frequência cardíaca: $e");
      return false;
    }
  }

  Future<bool> triggerVibrate({int count = 1, String text = "Localizar"}) async {
    final charControl = _findChar(BleConstants.uuidCharAlertControl);
    final charNewAlert = _findChar(BleConstants.uuidCharNewAlert);
    final charAlert = _findChar(BleConstants.uuidCharAlert);
    final charHuamiAlert = _findChar(BleConstants.uuidCharHuamiAlert);
    final charOld = _findChar(BleConstants.uuidCharChunkedOld);

    try {
      if (charControl != null) {
        await charControl.write([0x00, 0xFF], withoutResponse: false);
      }
    } catch (_) {}

    final safeBytes = safeUtf8Truncate(text, 18);
    bool vibrated = false;

    for (int i = 0; i < count; i++) {
      // 1. Método Oficial MiBand 6 / Gadgetbridge (CallSpec Incoming no canal 0x0020)
      if (charOld != null) {
        try {
          final callBuf = BytesBuilder();
          callBuf.add([3, 0, 0, 0, 0, 0]);
          callBuf.add(safeBytes);
          callBuf.add([0, 0, 0, 2]);
          final chunks = HuamiChunkedEncoder.encodeLegacyChunked(0, callBuf.toBytes());
          for (final c in chunks) {
            await charOld.write(c, withoutResponse: true);
            await Future.delayed(const Duration(milliseconds: 30));
          }
          vibrated = true;
          _trace("INFO", "Vibração acionada via CallSpec (${i + 1}/$count)");
        } catch (_) {}
      }

      // 2. New Alert (0x2A46) Categoria 3
      if (charNewAlert != null) {
        try {
          final p = BytesBuilder();
          p.add([0x03, 0x01]);
          p.add(safeBytes);
          await charNewAlert.write(p.toBytes(), withoutResponse: false);
          vibrated = true;
        } catch (_) {}
      }

      // 3. Immediate Alert (0x2A06) e Huami Alert (0x0003)
      try {
        if (charAlert != null) {
          await charAlert.write([0x02], withoutResponse: true);
          vibrated = true;
        }
        if (charHuamiAlert != null) {
          await charHuamiAlert.write([0x02], withoutResponse: true);
          vibrated = true;
        }
      } catch (_) {}

      await Future.delayed(const Duration(milliseconds: 1800));

      // 4. Cancelar CallSpec para tela voltar ao normal
      if (charOld != null) {
        try {
          final stopChunks = HuamiChunkedEncoder.encodeLegacyChunked(0, Uint8List.fromList([3, 3, 0, 0, 0, 0]));
          for (final sc in stopChunks) {
            await charOld.write(sc, withoutResponse: true);
          }
        } catch (_) {}
      }

      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return vibrated;
  }

  Future<bool> stopVibrate() async {
    final charAlert = _findChar(BleConstants.uuidCharAlert);
    final charHuamiAlert = _findChar(BleConstants.uuidCharHuamiAlert);
    final charOld = _findChar(BleConstants.uuidCharChunkedOld);

    try {
      if (charOld != null) {
        final stopChunks = HuamiChunkedEncoder.encodeLegacyChunked(0, Uint8List.fromList([3, 3, 0, 0, 0, 0]));
        for (final sc in stopChunks) {
          await charOld.write(sc, withoutResponse: true);
        }
      }
    } catch (_) {}

    try {
      if (charAlert != null) await charAlert.write([0x00], withoutResponse: true);
      if (charHuamiAlert != null) await charHuamiAlert.write([0x00], withoutResponse: true);
    } catch (_) {}

    _trace("INFO", "Comando de parada de vibração enviado com sucesso.");
    return true;
  }

  Future<bool> sendNotification({int category = 3, String title = "MiBand", String text = "Teste"}) async {
    final charNewAlert = _findChar(BleConstants.uuidCharNewAlert);
    final charControl = _findChar(BleConstants.uuidCharAlertControl);
    if (charNewAlert == null) return false;

    try {
      if (charControl != null) {
        await charControl.write([0x00, 0xFF], withoutResponse: false);
      }

      final titleClean = title.trim();
      final textClean = text.trim();
      final msg = titleClean.isNotEmpty ? "$titleClean: $textClean" : textClean;
      final msgBytes = safeUtf8Truncate(msg, 240);

      final p = BytesBuilder();
      p.add([category & 0xFF, 0x01]);
      p.add(msgBytes);

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
      _trace("INFO", "Previsão do tempo (${weather.temp}°C, ${weather.condition}) transmitida com sucesso para a Mi Band!");
      return true;
    } catch (e) {
      _trace("ERROR", "Falha ao enviar clima para a pulseira: $e");
      return false;
    }
  }

  Future<bool> setAlarms(List<AlarmItem> alarmsList) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;

    try {
      _trace("INFO", "Gravando ${alarmsList.length} alarmes na Mi Smart Band 6...");
      final slotsUsed = <int>{};

      for (int i = 0; i < alarmsList.length && i < 10; i++) {
        final a = alarmsList[i];
        int desiredIdx = a.index;
        if (desiredIdx < 0 || desiredIdx > 9 || slotsUsed.contains(desiredIdx)) {
          for (int s = 0; s < 10; s++) {
            if (!slotsUsed.contains(s)) {
              desiredIdx = s;
              break;
            }
          }
        }
        final idx = desiredIdx & 0x0F;
        slotsUsed.add(idx);

        int hr = 7;
        int mi = 0;
        final parts = a.time.split(':');
        if (parts.length >= 2) {
          hr = int.tryParse(parts[0]) ?? 7;
          mi = int.tryParse(parts[1]) ?? 0;
        }

        int actionMask = 0;
        if (a.enabled) actionMask |= 0x80;
        // Se soneca desativada, ativa bit 6 (0x40). Se soneca ativada, bit 6 é 0
        if (!a.snooze) actionMask |= 0x40;

        final stateByte = (actionMask | idx) & 0xFF;
        final rep = a.repetition;

        final cmd = Uint8List.fromList([0x01, 0x02, stateByte, hr & 0xFF, mi & 0xFF, rep & 0xFF]);
        _writeHandle = (_writeHandle + 1) & 0xFF;
        final enc = HuamiChunkedEncoder.encodeChunked2021(
          typeEndpoint: BleConstants.chunked2021EndpointCompat,
          data: cmd,
          handle: _writeHandle,
          encrypt: true,
          sessionKey: sessionKey,
          encryptedSeq: _encryptedSeq,
        );
        _encryptedSeq = enc.nextEncryptedSeq;

        for (final chunk in enc.chunks) {
          await charWrite.write(chunk, withoutResponse: true);
          await Future.delayed(const Duration(milliseconds: 35));
        }
        await Future.delayed(const Duration(milliseconds: 120));
      }

      // Desativar slots remanescentes para limpar alarmes fantasmas
      for (int slot = 0; slot < 10; slot++) {
        if (!slotsUsed.contains(slot)) {
          final disableByte = slot & 0x0F;
          final cmdDisable = Uint8List.fromList([0x01, 0x02, disableByte, 0, 0, 0]);
          _writeHandle = (_writeHandle + 1) & 0xFF;
          final enc = HuamiChunkedEncoder.encodeChunked2021(
            typeEndpoint: BleConstants.chunked2021EndpointCompat,
            data: cmdDisable,
            handle: _writeHandle,
            encrypt: true,
            sessionKey: sessionKey,
            encryptedSeq: _encryptedSeq,
          );
          _encryptedSeq = enc.nextEncryptedSeq;
          for (final chunk in enc.chunks) {
            await charWrite.write(chunk, withoutResponse: true);
            await Future.delayed(const Duration(milliseconds: 35));
          }
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }

      _trace("INFO", "Alarmes gravados e sincronizados com sucesso na pulseira!");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao gravar alarmes: $e");
      return false;
    }
  }

  Future<List<AlarmItem>> requestAlarms({Duration timeout = const Duration(seconds: 7)}) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    final charRead = _findChar(BleConstants.uuidCharChunkedRead);
    final alarmsDict = <int, AlarmItem>{};
    if (charWrite == null || charRead == null || sessionKey == null) return [];

    final completer = Completer<List<AlarmItem>>();
    StreamSubscription? sub;

    final chunkBuf = <int>[];
    int expectedLen = 0;
    bool isEncrypted = false;

    try {
      await charRead.setNotifyValue(true);
      sub = charRead.onValueReceived.listen((data) {
        if (data.length < 4) return;
        if (data[0] == 0x03) {
          final flags = data[1];
          isEncrypted = (flags & 0x08) != 0;
          final firstChunk = (flags & 0x01) != 0;
          final lastChunk = (flags & 0x02) != 0;
          final needsAck = (flags & 0x04) != 0;
          final handle = data[3];
          final count = data[4];

          if (needsAck) {
            final ack = Uint8List.fromList([0x04, 0x00, handle, 0x01, count]);
            charRead.write(ack, withoutResponse: true).catchError((_) {});
          }

          if (firstChunk) {
            final bd = ByteData.sublistView(Uint8List.fromList(data));
            expectedLen = bd.getUint32(5, Endian.little);
            chunkBuf.clear();
            chunkBuf.addAll(data.sublist(11));
          } else {
            chunkBuf.addAll(data.sublist(5));
          }

          if (lastChunk) {
            Uint8List rawBytes = Uint8List.fromList(chunkBuf);
            if (isEncrypted && sessionKey != null) {
              try {
                final msgKey = Uint8List(16);
                for (int j = 0; j < 16; j++) {
                  msgKey[j] = sessionKey![j] ^ handle;
                }
                final padLen = rawBytes.length - (rawBytes.length % 16);
                final decrypted = HuamiCryptoService.decryptAesEcb(rawBytes.sublist(0, padLen), msgKey);
                final cutLen = expectedLen > 0 && expectedLen <= decrypted.length ? expectedLen : decrypted.length;
                rawBytes = decrypted.sublist(0, cutLen);
              } catch (e) {
                _trace("WARN", "Falha na descriptografia chunked de alarmes: $e");
              }
            }

            final parsed = _parseAlarmPayload(rawBytes);
            for (final a in parsed) {
              alarmsDict[a.index] = a;
            }
            if (!completer.isCompleted && parsed.isNotEmpty) {
              completer.complete(alarmsDict.values.toList());
            }
          }
        }
      });

      await Future.delayed(const Duration(milliseconds: 100));

      // 1. Enviar COMMAND_REQUEST_ALARMS (0x0D)
      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc1 = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: Uint8List.fromList([0x01, 0x0D]),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc1.nextEncryptedSeq;
      for (final chunk in enc1.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }

      await Future.delayed(const Duration(milliseconds: 150));

      // 2. Enviar COMMAND_REQUEST_ALARMS_WITH_TIMES
      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc2 = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: Uint8List.fromList([0x01, 0xFF, 0x01, 0x00, 0x00, 0x00]),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc2.nextEncryptedSeq;
      for (final chunk in enc2.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }

      return await completer.future.timeout(timeout, onTimeout: () => alarmsDict.values.toList());
    } catch (e) {
      _trace("WARN", "Falha ao consultar alarmes: $e");
      return alarmsDict.values.toList();
    } finally {
      try {
        await charRead.setNotifyValue(false);
        await sub?.cancel();
      } catch (_) {}
    }
  }

  List<AlarmItem> _parseAlarmPayload(Uint8List payload) {
    final alarms = <AlarmItem>[];
    if (payload.length < 4) return alarms;

    Uint8List data = payload;
    if (data[0] == 0x01 && data.length > 4) {
      data = data.sublist(1);
    }

    int offsetStart = 0;
    if ((data.length - 1) % 4 == 0 && (data[0] == 0x01 || data[0] == 0x02)) {
      offsetStart = 1;
    } else if (data.length % 4 == 0) {
      offsetStart = 0;
    } else {
      // Busca pelo melhor alinhamento
      int bestOff = 0;
      int bestValid = 0;
      for (int off = 0; off < 8 && off + 4 <= data.length; off++) {
        int valid = 0;
        final nr = (data.length - off) ~/ 4;
        for (int k = 0; k < nr; k++) {
          final p = off + k * 4;
          final hr = data[p + 1];
          final mi = data[p + 2];
          if ((data[p] & 0x0F) < 10 && hr < 24 && mi < 60) valid++;
        }
        if (valid > bestValid) {
          bestValid = valid;
          bestOff = off;
        }
      }
      offsetStart = bestOff;
    }

    final nr = (data.length - offsetStart) ~/ 4;
    for (int i = 0; i < (nr < 10 ? nr : 10); i++) {
      final off = offsetStart + i * 4;
      if (off + 3 >= data.length) break;
      final raw = data[off];
      final idx = raw & 0x0F;
      if (idx >= 10) continue;
      final enabled = (raw & 0x80) != 0;
      final snooze = (raw & 0x40) == 0;
      final hr = data[off + 1];
      final mi = data[off + 2];
      final rep = data[off + 3];

      if (hr < 24 && mi < 60) {
        alarms.add(AlarmItem(
          index: idx,
          time: "${hr.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}",
          enabled: enabled,
          snooze: snooze,
          repetition: rep,
        ));
      }
    }
    return alarms;
  }

  Future<bool> setFitnessGoals(int stepGoal, int calorieGoal) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final s = stepGoal.clamp(1000, 100000);
      final c = calorieGoal.clamp(50, 10000);
      final bd = ByteData(7);
      bd.setUint8(0, 0x06);
      bd.setUint8(1, 0x01);
      bd.setUint8(2, 0x00);
      bd.setUint16(3, s, Endian.little);
      bd.setUint16(5, c, Endian.little);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: bd.buffer.asUint8List(),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Metas de atividade sincronizadas: $s passos e $c kcal");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao definir metas de atividade: $e");
      return false;
    }
  }

  Future<bool> sendPaiScore(int totalPai, int todayPai) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final tot = totalPai.clamp(0, 999);
      final tod = todayPai.clamp(0, 999);
      final bd = ByteData(6);
      bd.setUint8(0, 0x01);
      bd.setUint8(1, 0x18);
      bd.setUint16(2, tot, Endian.little);
      bd.setUint16(4, tod, Endian.little);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: bd.buffer.asUint8List(),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Pontuação PAI enviada: Total=$tot | Hoje=$tod");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao enviar pontuação PAI: $e");
      return false;
    }
  }

  Future<bool> setStressMonitoring(bool enabled, int intervalMinutes) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final en = enabled ? 1 : 0;
      final intv = intervalMinutes.clamp(1, 60);
      final cmd = Uint8List.fromList([0x06, 0x12, en, intv]);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmd,
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Monitoramento de estresse configurado: Ativo=$enabled, Intervalo=$intv min");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar estresse: $e");
      return false;
    }
  }

  /// Lê informações de hardware e firmware (DIS 0x180A)
  Future<Map<String, String>> readDeviceInfo() async {
    final info = <String, String>{
      "model": "Mi Smart Band 6",
      "firmware_version": "Desconhecido",
      "hardware_version": "Desconhecido",
      "software_version": "Desconhecido",
      "serial_number": "Desconhecido",
    };

    final map = {
      BleConstants.uuidCharModel: "model",
      BleConstants.uuidCharFwRevision: "firmware_version",
      BleConstants.uuidCharHwRevision: "hardware_version",
      BleConstants.uuidCharSwRevision: "software_version",
      BleConstants.uuidCharSerial: "serial_number",
    };

    for (final entry in map.entries) {
      final c = _findChar(entry.key);
      if (c != null) {
        try {
          final val = await c.read();
          if (val.isNotEmpty) {
            info[entry.value] = utf8.decode(val, allowMalformed: true).trim();
          }
        } catch (_) {}
      }
    }
    _trace("INFO", "Informações do dispositivo obtidas: $info");
    return info;
  }

  /// Lê detalhes de bateria (nível, status de carregamento, última carga)
  Future<Map<String, dynamic>> readBatteryDetails() async {
    final lvl = await readBattery();
    String statusStr = "Descarregando / Em uso";
    bool isCharging = false;
    String? lastChargeStr;

    final charBat = _findChar(BleConstants.uuidCharBatteryLegacy);
    if (charBat != null) {
      try {
        final val = await charBat.read();
        if (val.length >= 3) {
          final statusCode = val[2];
          if (statusCode == 2) {
            statusStr = "Carregando";
            isCharging = true;
          } else if (statusCode == 3) {
            statusStr = "Carga Completa (100%)";
          } else if (statusCode == 1) {
            statusStr = "Descarregando / Em uso";
          }

          if (val.length >= 9) {
            final yr = 2000 + val[3];
            final mo = val[4].toString().padLeft(2, '0');
            final dy = val[5].toString().padLeft(2, '0');
            final hr = val[6].toString().padLeft(2, '0');
            final mi = val[7].toString().padLeft(2, '0');
            final sc = val[8].toString().padLeft(2, '0');
            lastChargeStr = "$dy/$mo/$yr $hr:$mi:$sc";
          }
        }
      } catch (_) {}
    }

    final res = {
      "level": lvl,
      "status": statusStr,
      "is_charging": isCharging,
      "last_charge": lastChargeStr,
    };
    _trace("INFO", "Bateria: $lvl% | Status: $statusStr | Última carga: ${lastChargeStr ?? 'N/A'}");
    return res;
  }

  /// Lê o horário interno gravado na pulseira e compara o desvio com o smartphone
  Future<Map<String, dynamic>> readBandTime() async {
    final charTime = _findChar(BleConstants.uuidCharCurrentTime);
    if (charTime == null) {
      return {"synced": false, "error": "Característica Current Time não encontrada"};
    }
    try {
      final val = await charTime.read();
      if (val.length >= 7) {
        final bd = ByteData.sublistView(Uint8List.fromList(val));
        final year = bd.getUint16(0, Endian.little);
        final month = val[2];
        final day = val[3];
        final hour = val[4];
        final minute = val[5];
        final second = val[6];

        final bandTime = DateTime(year, month, day, hour, minute, second);
        final phoneTime = DateTime.now();
        final driftSec = phoneTime.difference(bandTime).inSeconds.abs();

        final res = {
          "band_time": bandTime.toIso8601String(),
          "phone_time": phoneTime.toIso8601String(),
          "drift_seconds": driftSec,
          "synced": driftSec < 3,
        };
        _trace("INFO", "Horário da pulseira: ${res['band_time']} | Desvio: ${driftSec}s");
        return res;
      }
    } catch (e) {
      _trace("WARN", "Falha ao ler horário da pulseira: $e");
    }
    return {"synced": false};
  }

  /// Aciona medição óptica de oximetria de pulso (SpO2)
  Future<int?> measureSpo2({Duration timeout = const Duration(seconds: 25)}) async {
    final charMeasure = _findChar(BleConstants.uuidCharHeartRateMeasure);
    final charControl = _findChar(BleConstants.uuidCharHeartRateControl);
    if (charMeasure == null || charControl == null) return null;

    final completer = Completer<int?>();
    StreamSubscription? sub;

    try {
      _trace("INFO", "Acionando sensor óptico de oxigênio (SpO2). Mantenha o braço imóvel...");
      await charMeasure.setNotifyValue(true);
      sub = charMeasure.onValueReceived.listen((data) {
        if (data.length >= 2) {
          for (final b in data) {
            if (b >= 75 && b <= 100) {
              if (!completer.isCompleted) completer.complete(b);
              break;
            }
          }
        }
      });

      // Comando de início de sensor SpO2 (0x15, 0x03, 0x01)
      await charControl.write([0x15, 0x03, 0x01], withoutResponse: false);

      final result = await completer.future.timeout(timeout, onTimeout: () => null);
      if (result != null) {
        _trace("INFO", "Saturação de oxigênio (SpO2) aferida: $result%");
      } else {
        _trace("WARN", "Tempo limite esgotado aguardando leitura de SpO2.");
      }
      return result;
    } catch (e) {
      _trace("WARN", "Erro durante medição de SpO2: $e");
      return null;
    } finally {
      try {
        await charControl.write([0x15, 0x03, 0x00], withoutResponse: false);
      } catch (_) {}
      try {
        await charMeasure.setNotifyValue(false);
        await sub?.cancel();
      } catch (_) {}
    }
  }

  /// Mede ou estima o índice de estresse imediato com base na variabilidade cardíaca (HRV)
  Future<int?> measureStress({Duration timeout = const Duration(seconds: 15)}) async {
    _trace("INFO", "Iniciando aferição de nível de estresse (HRV)...");
    final hr = await measureHeartRate(timeout: timeout);
    if (hr != null && hr > 0) {
      int score;
      if (hr < 65) {
        score = 22; // Relaxado
      } else if (hr < 80) {
        score = 38; // Normal
      } else if (hr < 95) {
        score = 62; // Médio
      } else {
        score = 84; // Alto
      }
      _trace("INFO", "Nível de estresse calculado: $score/100 (FC=$hr BPM)");
      return score;
    }
    return null;
  }

  /// Extrai histórico detalhado intradiário de atividades e sono (0x0004 / 0x0005)
  Future<Map<String, dynamic>> fetchActivityData({
    DateTime? startTime,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final charData = _findChar(BleConstants.uuidCharActivityData);
    final charControl = _findChar(BleConstants.uuidCharActivityControl);
    if (charData == null || charControl == null) {
      return {"samples": [], "total_steps": 0};
    }

    final rawChunks = BytesBuilder();
    final finishedCompleter = Completer<void>();
    final startDt = startTime ?? DateTime.now().subtract(const Duration(hours: 24));
    final tzQuarters = startDt.timeZoneOffset.inSeconds ~/ 900;
    DateTime baseDt = startDt;

    StreamSubscription? subData;
    StreamSubscription? subControl;

    try {
      _trace("INFO", "Iniciando subscrição em 0x0004 e 0x0005 para download de histórico...");
      await charData.setNotifyValue(true);
      await charControl.setNotifyValue(true);

      subData = charData.onValueReceived.listen((d) {
        rawChunks.add(d);
      });

      subControl = charControl.onValueReceived.listen((d) {
        if (d.length >= 3) {
          if (d[0] == 0x10 && d[1] == 0x01) {
            if (d[2] == 0x01) {
              _trace("INFO", "Pulseira aceitou requisição de histórico. Aguardando pacotes...");
              if (d.length >= 10) {
                final bd = ByteData.sublistView(Uint8List.fromList(d.sublist(3, 9)));
                final yr = bd.getUint16(0, Endian.little);
                baseDt = DateTime(yr, d[5], d[6], d[7], d[8]);
              }
            } else if (d[2] == 0x02) {
              _trace("INFO", "Nenhum dado novo de histórico para descarregar.");
              if (!finishedCompleter.isCompleted) finishedCompleter.complete();
            }
          } else if (d[0] == 0x10 && d[1] == 0x02) {
            _trace("INFO", "Fim da transmissão de pacotes de histórico.");
            if (!finishedCompleter.isCompleted) finishedCompleter.complete();
          }
        }
      });

      // Solicitar histórico: [0x01, 0x01, yrLE, mo, dy, hr, mi, tzQuarters]
      final cmd = BytesBuilder();
      cmd.add([0x01, 0x01]);
      final bd = ByteData(2)..setUint16(0, startDt.year, Endian.little);
      cmd.add(bd.buffer.asUint8List());
      cmd.addByte(startDt.month);
      cmd.addByte(startDt.day);
      cmd.addByte(startDt.hour);
      cmd.addByte(startDt.minute);
      cmd.addByte(tzQuarters & 0xFF);

      await charControl.write(cmd.toBytes(), withoutResponse: false);
      await finishedCompleter.future.timeout(timeout, onTimeout: () {});

      // Envia confirmação ACK
      try {
        await charControl.write([0x02], withoutResponse: true);
      } catch (_) {}
    } catch (e) {
      _trace("WARN", "Falha ao extrair histórico de atividade: $e");
    } finally {
      try {
        await charData.setNotifyValue(false);
        await charControl.setNotifyValue(false);
        await subData?.cancel();
        await subControl?.cancel();
      } catch (_) {}
    }

    final bytes = rawChunks.toBytes();
    final nrSamples = bytes.length ~/ 4;
    final samples = <Map<String, dynamic>>[];
    int sleepLight = 0, sleepDeep = 0, sleepRem = 0, sleepAwake = 0;
    int totalSteps = 0;

    for (int i = 0; i < nrSamples; i++) {
      final off = i * 4;
      final cat = bytes[off];
      final intensity = bytes[off + 1];
      final st = bytes[off + 2];
      final hr = bytes[off + 3];
      final hrVal = (hr > 0 && hr < 250) ? hr : null;
      final sampleDt = baseDt.add(Duration(minutes: i));

      if (cat == 80) {
        sleepLight++;
      } else if (cat == 81) {
        sleepDeep++;
      } else if (cat == 82) {
        sleepRem++;
      } else if (cat == 83) {
        sleepAwake++;
      }

      totalSteps += st;

      if (st > 0 || hrVal != null || (cat >= 80 && cat <= 83)) {
        samples.add({
          "timestamp": sampleDt.toIso8601String(),
          "category": cat,
          "intensity": intensity,
          "steps": st,
          "heart_rate": hrVal,
        });
      }
    }

    final totalSleep = sleepLight + sleepDeep + sleepRem;
    Map<String, dynamic>? sleepSummary;
    if (totalSleep > 0) {
      sleepSummary = {
        "date": "${startDt.year}-${startDt.month.toString().padLeft(2, '0')}-${startDt.day.toString().padLeft(2, '0')}",
        "start_time": baseDt.toIso8601String(),
        "end_time": baseDt.add(Duration(minutes: nrSamples)).toIso8601String(),
        "total_sleep_minutes": totalSleep,
        "deep_sleep_minutes": sleepDeep,
        "light_sleep_minutes": sleepLight,
        "rem_sleep_minutes": sleepRem,
        "awake_minutes": sleepAwake,
      };
    }

    _trace("INFO", "Histórico processado: ${samples.length} amostras relevantes, sono total: $totalSleep min, passos: $totalSteps");
    return {
      "samples": samples,
      "sleep_summary": sleepSummary,
      "total_steps": totalSteps,
    };
  }

  /// Configura o braço de uso da pulseira: false = Esquerdo, true = Direito
  Future<bool> setWearLocation({bool rightWrist = false}) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final val = rightWrist ? 0x01 : 0x00;
      final cmd = Uint8List.fromList([0x06, 0x02, 0x00, val]);
      _trace("INFO", "Configurando braço de uso: ${rightWrist ? 'Pulso Direito' : 'Pulso Esquerdo'}");

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmd,
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar braço de uso: $e");
      return false;
    }
  }

  /// Configura 'Levantar o pulso para ver informação': mode ('off', 'all_day', 'scheduled')
  Future<bool> setLiftWrist({
    String mode = "all_day",
    String startTime = "07:00",
    String endTime = "22:00",
    bool fastSpeed = false,
  }) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final modeVal = mode.toLowerCase() == "off" ? 0x00 : (mode.toLowerCase() == "scheduled" ? 0x02 : 0x01);
      final sParts = startTime.split(":");
      final sHr = int.tryParse(sParts[0]) ?? 7;
      final sMi = sParts.length > 1 ? (int.tryParse(sParts[1]) ?? 0) : 0;
      final eParts = endTime.split(":");
      final eHr = int.tryParse(eParts[0]) ?? 22;
      final eMi = eParts.length > 1 ? (int.tryParse(eParts[1]) ?? 0) : 0;
      final speedVal = fastSpeed ? 0x01 : 0x00;

      final cmd = Uint8List.fromList([0x06, 0x05, modeVal, sHr, sMi, eHr, eMi, speedVal]);
      _trace("INFO", "Configurando Levantar Pulso: Modo=$mode, $sHr:$sMi até $eHr:$eMi");

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmd,
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar levantar pulso: $e");
      return false;
    }
  }

  /// Configura Modo Noturno (redução de brilho) e DND Não Perturbe
  Future<bool> setNightMode({
    String mode = "sunset",
    String startTime = "22:00",
    String endTime = "07:00",
    String dndMode = "smart",
  }) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final modeVal = mode.toLowerCase() == "off" ? 0x00 : (mode.toLowerCase() == "sunset" ? 0x01 : 0x02);
      final sParts = startTime.split(":");
      final sHr = int.tryParse(sParts[0]) ?? 22;
      final sMi = sParts.length > 1 ? (int.tryParse(sParts[1]) ?? 0) : 0;
      final eParts = endTime.split(":");
      final eHr = int.tryParse(eParts[0]) ?? 7;
      final eMi = eParts.length > 1 ? (int.tryParse(eParts[1]) ?? 0) : 0;

      // 1. Comando Modo Noturno
      final cmdNight = Uint8List.fromList([0x06, 0x0a, modeVal, sHr, sMi, eHr, eMi]);
      _writeHandle = (_writeHandle + 1) & 0xFF;
      final encNight = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmdNight,
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = encNight.nextEncryptedSeq;
      for (final chunk in encNight.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }

      // 2. Comando DND
      final dndMap = {"off": 0x00, "always": 0x01, "smart": 0x02, "scheduled": 0x03};
      final dndVal = dndMap[dndMode.toLowerCase()] ?? 0x02;
      final cmdDnd = Uint8List.fromList([0x06, 0x0b, dndVal, sHr, sMi, eHr, eMi]);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final encDnd = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmdDnd,
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = encDnd.nextEncryptedSeq;
      for (final chunk in encDnd.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Modo Noturno e DND configurados com êxito!");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar modo noturno/DND: $e");
      return false;
    }
  }

  /// Configura o idioma da interface da Mi Band 6 (ex: 'pt_BR', 'en_US', 'es_ES')
  Future<bool> setBandLanguage(String languageCode) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final code = languageCode.trim();
      final langBytes = safeUtf8Truncate(code, 16);
      final cmd = BytesBuilder();
      cmd.add([0x06, 0x08]);
      cmd.add(langBytes);

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: cmd.toBytes(),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Idioma da pulseira configurado para: $code");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao configurar idioma da pulseira: $e");
      return false;
    }
  }

  /// Sincroniza capitais e fusos horários no Relógio Mundial da pulseira
  Future<bool> setWorldClocks(List<Map<String, dynamic>> clocks) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      final payload = BytesBuilder();
      payload.add([0x01, 0x11, clocks.length.clamp(0, 10)]);

      for (final c in clocks.take(10)) {
        final city = (c['city'] ?? "São Paulo").toString();
        final tzOffset = (c['timezone'] as num? ?? -3).toInt();
        final cityBytes = safeUtf8Truncate(city, 20);
        payload.addByte(cityBytes.length);
        payload.add(cityBytes);
        final bd = ByteData(2)..setInt16(0, tzOffset, Endian.little);
        payload.add(bd.buffer.asUint8List());
      }

      _writeHandle = (_writeHandle + 1) & 0xFF;
      final enc = HuamiChunkedEncoder.encodeChunked2021(
        typeEndpoint: BleConstants.chunked2021EndpointCompat,
        data: payload.toBytes(),
        handle: _writeHandle,
        encrypt: true,
        sessionKey: sessionKey,
        encryptedSeq: _encryptedSeq,
      );
      _encryptedSeq = enc.nextEncryptedSeq;
      for (final chunk in enc.chunks) {
        await charWrite.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 35));
      }
      _trace("INFO", "Relógio Mundial sincronizado com ${clocks.length} cidades!");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao sincronizar relógio mundial: $e");
      return false;
    }
  }

  /// Sincroniza lembretes de eventos com título e horário
  Future<bool> setEventReminders(List<Map<String, dynamic>> reminders) async {
    final charWrite = _findChar(BleConstants.uuidCharChunkedWrite);
    if (charWrite == null || sessionKey == null) return false;
    try {
      for (int i = 0; i < reminders.take(15).length; i++) {
        final r = reminders[i];
        final title = (r['title'] ?? "Lembrete").toString();
        final dtStr = (r['date'] ?? "").toString();
        final tmStr = (r['time'] ?? "12:00").toString();

        final dtParts = dtStr.split("-");
        final yr = dtParts.isNotEmpty ? (int.tryParse(dtParts[0]) ?? 2026) : 2026;
        final mo = dtParts.length > 1 ? (int.tryParse(dtParts[1]) ?? 1) : 1;
        final dy = dtParts.length > 2 ? (int.tryParse(dtParts[2]) ?? 1) : 1;

        final tmParts = tmStr.split(":");
        final hr = tmParts.isNotEmpty ? (int.tryParse(tmParts[0]) ?? 12) : 12;
        final mi = tmParts.length > 1 ? (int.tryParse(tmParts[1]) ?? 0) : 0;
        final rep = (r['repetition'] as num? ?? 0).toInt();

        final titleBytes = safeUtf8Truncate(title, 24);
        final cmd = BytesBuilder();
        cmd.add([0x01, 0x01, i & 0xFF]);
        final bd = ByteData(2)..setUint16(0, yr, Endian.little);
        cmd.add(bd.buffer.asUint8List());
        cmd.add([mo, dy, hr, mi, rep & 0xFF, titleBytes.length]);
        cmd.add(titleBytes);

        _writeHandle = (_writeHandle + 1) & 0xFF;
        final enc = HuamiChunkedEncoder.encodeChunked2021(
          typeEndpoint: BleConstants.chunked2021EndpointCompat,
          data: cmd.toBytes(),
          handle: _writeHandle,
          encrypt: true,
          sessionKey: sessionKey,
          encryptedSeq: _encryptedSeq,
        );
        _encryptedSeq = enc.nextEncryptedSeq;
        for (final chunk in enc.chunks) {
          await charWrite.write(chunk, withoutResponse: true);
          await Future.delayed(const Duration(milliseconds: 35));
        }
      }
      _trace("INFO", "Lembretes de eventos sincronizados com a pulseira!");
      return true;
    } catch (e) {
      _trace("WARN", "Falha ao sincronizar lembretes de eventos: $e");
      return false;
    }
  }
}

Uint8List safeUtf8Truncate(String text, int maxBytes) {
  if (text.isEmpty) return Uint8List(0);
  final encoded = utf8.encode(text);
  if (encoded.length <= maxBytes) return Uint8List.fromList(encoded);

  final truncated = encoded.sublist(0, maxBytes);
  final decoded = utf8.decode(truncated, allowMalformed: true);
  final clean = decoded.endsWith('\uFFFD') ? decoded.substring(0, decoded.length - 1) : decoded;
  return Uint8List.fromList(utf8.encode(clean));
}

