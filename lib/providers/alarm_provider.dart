import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/database/app_database.dart';
import '../models/alarm_item.dart';
import '../models/device_config.dart';
import '../protocol/miband_protocol.dart';

class AlarmProvider extends ChangeNotifier {
  List<AlarmItem> _alarms = [];
  List<AlarmItem> get alarms => _alarms;

  String? _currentMac;
  bool _isSyncingAlarms = false;
  bool get isSyncingAlarms => _isSyncingAlarms;

  Future<void> loadAlarms(String deviceMac) async {
    _currentMac = deviceMac;
    _alarms = await AppDatabase.instance.getAlarms(deviceMac);
    if (_alarms.isEmpty) {
      _alarms = [
        AlarmItem(index: 0, time: "07:00", enabled: true, repetition: 31), // Seg a Sex
        AlarmItem(index: 1, time: "08:30", enabled: false, repetition: 128), // Uma vez
      ];
      await AppDatabase.instance.saveAlarms(deviceMac, _alarms);
    }
    notifyListeners();
  }

  Future<void> toggleAlarm(int index) async {
    final idx = _alarms.indexWhere((a) => a.index == index);
    if (idx != -1) {
      _alarms[idx] = _alarms[idx].copyWith(enabled: !_alarms[idx].enabled);
      notifyListeners();
      if (_currentMac != null) {
        await AppDatabase.instance.saveAlarms(_currentMac!, _alarms);
      }
    }
  }

  Future<void> addOrUpdateAlarm(AlarmItem alarm) async {
    final idx = _alarms.indexWhere((a) => a.index == alarm.index);
    if (idx != -1) {
      _alarms[idx] = alarm;
    } else {
      _alarms.add(alarm);
    }
    notifyListeners();
    if (_currentMac != null) {
      await AppDatabase.instance.saveAlarms(_currentMac!, _alarms);
    }
  }

  Future<void> deleteAlarm(int index) async {
    _alarms.removeWhere((a) => a.index == index);
    notifyListeners();
    if (_currentMac != null) {
      await AppDatabase.instance.saveAlarms(_currentMac!, _alarms);
    }
  }

  /// Grava a lista atual de alarmes na memória da Mi Smart Band 6 via BLE
  Future<bool> sendAlarmsToBand(DeviceConfig config) async {
    if (_isSyncingAlarms) return false;
    _isSyncingAlarms = true;
    notifyListeners();

    BluetoothDevice? device;
    try {
      device = BluetoothDevice(remoteId: DeviceIdentifier(config.macAddress));
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 12));
      final protocol = MiBandProtocol(device, config.authKey);

      final authOk = await protocol.authenticate();
      if (!authOk) {
        throw Exception("Falha de autenticação ao tentar enviar alarmes.");
      }

      final ok = await protocol.setAlarms(_alarms);
      await device.disconnect();
      return ok;
    } catch (_) {
      try { await device?.disconnect(); } catch (_) {}
      return false;
    } finally {
      _isSyncingAlarms = false;
      notifyListeners();
    }
  }

  /// Consulta os alarmes salvos diretamente no firmware da pulseira
  Future<bool> readAlarmsFromBand(DeviceConfig config) async {
    if (_isSyncingAlarms) return false;
    _isSyncingAlarms = true;
    notifyListeners();

    BluetoothDevice? device;
    try {
      device = BluetoothDevice(remoteId: DeviceIdentifier(config.macAddress));
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 12));
      final protocol = MiBandProtocol(device, config.authKey);

      final authOk = await protocol.authenticate();
      if (!authOk) {
        throw Exception("Falha de autenticação ao tentar ler alarmes.");
      }

      final bandAlarms = await protocol.requestAlarms();
      if (bandAlarms.isNotEmpty) {
        _alarms = bandAlarms;
        await AppDatabase.instance.saveAlarms(config.macAddress, _alarms);
        notifyListeners();
      }
      await device.disconnect();
      return bandAlarms.isNotEmpty;
    } catch (_) {
      try { await device?.disconnect(); } catch (_) {}
      return false;
    } finally {
      _isSyncingAlarms = false;
      notifyListeners();
    }
  }
}
