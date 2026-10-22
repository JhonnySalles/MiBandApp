import 'package:flutter/foundation.dart';
import '../core/database/app_database.dart';
import '../models/alarm_item.dart';

class AlarmProvider extends ChangeNotifier {
  List<AlarmItem> _alarms = [];
  List<AlarmItem> get alarms => _alarms;

  String? _currentMac;

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
}
