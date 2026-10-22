import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/database/app_database.dart';
import '../models/activity_data.dart';
import '../models/device_config.dart';
import '../models/heart_rate_record.dart';
import '../models/sync_log.dart';
import '../models/weather_data.dart';
import '../protocol/miband_protocol.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  syncing,
  error,
}

class DiscoveredBand {
  final String name;
  final String address;
  final int rssi;
  final BluetoothDevice device;

  DiscoveredBand({
    required this.name,
    required this.address,
    required this.rssi,
    required this.device,
  });
}

class BleService {
  static final BleService instance = BleService._init();
  BleService._init();

  BleConnectionState _state = BleConnectionState.disconnected;
  BleConnectionState get state => _state;

  final StreamController<BleConnectionState> _stateController = StreamController.broadcast();
  Stream<BleConnectionState> get stateStream => _stateController.stream;

  final List<String> _liveLogs = [];
  List<String> get liveLogs => List.unmodifiable(_liveLogs);
  final StreamController<List<String>> _logsController = StreamController.broadcast();
  Stream<List<String>> get logsStream => _logsController.stream;

  void _setState(BleConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _log(String level, String msg) {
    final entry = "[${DateTime.now().toIso8601String().substring(11, 19)}] [$level] $msg";
    _liveLogs.insert(0, entry);
    if (_liveLogs.length > 100) _liveLogs.removeLast();
    _logsController.add(_liveLogs);
  }

  /// Escaneia dispositivos BLE por proximidade (ordena por RSSI)
  Future<List<DiscoveredBand>> scanDevices({Duration timeout = const Duration(seconds: 4)}) async {
    _setState(BleConnectionState.scanning);
    _log("INFO", "Iniciando escaneamento de dispositivos BLE próximos...");

    final discovered = <String, DiscoveredBand>{};

    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _log("WARN", "Bluetooth não suportado neste dispositivo.");
        _setState(BleConnectionState.disconnected);
        return [];
      }

      await FlutterBluePlus.startScan(timeout: timeout);
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName.isNotEmpty ? r.device.platformName : (r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : "Dispositivo BLE");
          final addr = r.device.remoteId.str;
          discovered[addr] = DiscoveredBand(
            name: name,
            address: addr,
            rssi: r.rssi,
            device: r.device,
          );
        }
      });

      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      await sub.cancel();
    } catch (e) {
      _log("ERROR", "Erro durante escaneamento BLE: $e");
    } finally {
      _setState(BleConnectionState.disconnected);
    }

    final list = discovered.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    _log("INFO", "Escaneamento concluído: ${list.length} dispositivos encontrados.");
    return list;
  }

  /// Executa o fluxo completo de sincronização com a Mi Band
  Future<ActivityData?> syncDevice({
    required DeviceConfig config,
    WeatherData? weather,
    bool measureHr = true,
  }) async {
    if (_state == BleConnectionState.syncing || _state == BleConnectionState.connecting) {
      _log("WARN", "Já existe uma sincronização em andamento.");
      return null;
    }

    _setState(BleConnectionState.connecting);
    _log("INFO", "Conectando com a Mi Band (${config.macAddress})...");

    BluetoothDevice? device;
    ActivityData? resultActivity;
    DateTime syncStart = DateTime.now();

    try {
      device = BluetoothDevice(remoteId: DeviceIdentifier(config.macAddress));
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      _setState(BleConnectionState.connected);
      _log("INFO", "Conexão BLE estabelecida com sucesso!");

      _setState(BleConnectionState.syncing);
      final protocol = MiBandProtocol(
        device,
        config.authKey,
        onTrace: (lvl, msg) => _log(lvl, msg),
      );


      _log("INFO", "Iniciando autenticação na pulseira...");
      final authOk = await protocol.authenticate();
      if (!authOk) {
        throw Exception("Falha de autenticação com a pulseira. Verifique se a Auth Key de 32 hex está correta.");
      }

      _log("INFO", "Pulseira autenticada! Sincronizando horário...");
      await protocol.syncTime();

      _log("INFO", "Lendo métricas físicas (Passos, Calorias, Distância)...");
      final stepsData = await protocol.readSteps();
      final battery = await protocol.readBattery();

      int? hrBpm;
      if (measureHr) {
        _log("INFO", "Acionando sensor óptico PPG para aferir frequência cardíaca (BPM)...");
        hrBpm = await protocol.measureHeartRate(timeout: const Duration(seconds: 12));
        if (hrBpm != null && hrBpm > 0) {
          _log("INFO", "Frequência cardíaca aferida: $hrBpm BPM");
          await AppDatabase.instance.insertHeartRate(HeartRateRecord(
            deviceMac: config.macAddress,
            bpm: hrBpm,
            timestamp: DateTime.now(),
          ));
        }
      }

      if (weather != null) {
        _log("INFO", "Transmitindo dados climáticos para o display do relógio...");
        await protocol.sendWeather(weather);
      }

      resultActivity = ActivityData(
        deviceMac: config.macAddress,
        timestamp: DateTime.now(),
        steps: stepsData['steps'] ?? 0,
        distanceMeters: stepsData['distance_meters'] ?? 0,
        calories: stepsData['calories'] ?? 0,
        heartRate: hrBpm,
        batteryLevel: battery,
      );

      // Salva no banco SQLite
      await AppDatabase.instance.insertActivity(resultActivity);
      await AppDatabase.instance.saveDevice(config.copyWith(lastSyncTime: DateTime.now()));
      await AppDatabase.instance.insertSyncLog(SyncLog(
        deviceMac: config.macAddress,
        timestamp: DateTime.now(),
        status: "SUCCESS",
        message: "Sincronização concluída com sucesso (${resultActivity.steps} passos)",
        details: "Duração: ${DateTime.now().difference(syncStart).inMilliseconds}ms | Bateria: ${battery ?? 0}%",
      ));

      _log("INFO", "Sincronização finalizada com êxito!");
      _setState(BleConnectionState.connected);
      return resultActivity;
    } catch (e) {
      _log("ERROR", "Erro na sincronização: $e");
      await AppDatabase.instance.insertSyncLog(SyncLog(
        deviceMac: config.macAddress,
        timestamp: DateTime.now(),
        status: "ERROR",
        message: "Falha na sincronização",
        details: e.toString(),
      ));
      _setState(BleConnectionState.error);
      return null;
    } finally {
      try {
        await device?.disconnect();
      } catch (_) {}
      _setState(BleConnectionState.disconnected);
    }
  }

  /// Aciona vibração de teste / localização
  Future<bool> triggerVibrate(DeviceConfig config, {int count = 2}) async {
    _log("INFO", "Disparando vibração física para localizar pulseira...");
    BluetoothDevice? device;
    try {
      device = BluetoothDevice(remoteId: DeviceIdentifier(config.macAddress));
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 12));
      final protocol = MiBandProtocol(device, config.authKey, onTrace: (lvl, msg) => _log(lvl, msg));

      if (config.authKey.length == 32) {
        await protocol.authenticate();
      }
      final ok = await protocol.triggerVibrate(count: count, text: "Localizar");
      await device.disconnect();
      return ok;
    } catch (e) {
      _log("WARN", "Falha ao vibrar pulseira: $e");
      try { await device?.disconnect(); } catch (_) {}
      return false;
    }
  }

  /// Envia notificação de texto personalizada para a tela
  Future<bool> sendNotification(DeviceConfig config, String title, String text) async {
    BluetoothDevice? device;
    try {
      device = BluetoothDevice(remoteId: DeviceIdentifier(config.macAddress));
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 12));
      final protocol = MiBandProtocol(device, config.authKey, onTrace: (lvl, msg) => _log(lvl, msg));
      if (config.authKey.length == 32) {
        await protocol.authenticate();
      }
      final ok = await protocol.sendNotification(category: 3, title: title, text: text);
      await device.disconnect();
      return ok;
    } catch (e) {
      _log("WARN", "Falha ao enviar notificação: $e");
      try { await device?.disconnect(); } catch (_) {}
      return false;
    }
  }
}
