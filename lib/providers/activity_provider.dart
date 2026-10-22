import 'package:flutter/foundation.dart';
import '../core/database/app_database.dart';
import '../models/activity_data.dart';
import '../models/heart_rate_record.dart';
import '../models/sync_log.dart';

class ActivityProvider extends ChangeNotifier {
  ActivityData? _todayActivity;
  ActivityData? get todayActivity => _todayActivity;

  int _dailyStepGoal = 10000;
  int get dailyStepGoal => _dailyStepGoal;

  List<ActivityData> _history = [];
  List<ActivityData> get history => _history;

  List<HeartRateRecord> _recentHeartRates = [];
  List<HeartRateRecord> get recentHeartRates => _recentHeartRates;

  List<SyncLog> _syncLogs = [];
  List<SyncLog> get syncLogs => _syncLogs;

  ActivityProvider() {
    loadData();
  }

  Future<void> loadData([String? deviceMac]) async {
    final mac = deviceMac ?? (await AppDatabase.instance.getPrimaryDevice())?.macAddress;
    if (mac != null) {
      _todayActivity = await AppDatabase.instance.getLatestActivity(mac);
      _history = await AppDatabase.instance.getActivitiesForDays(mac, 7);
      _recentHeartRates = await AppDatabase.instance.getRecentHeartRates(mac);
    }
    _syncLogs = await AppDatabase.instance.getRecentSyncLogs();
    notifyListeners();
  }

  void updateActivity(ActivityData activity) {
    _todayActivity = activity;
    _history.add(activity);
    if (activity.heartRate != null) {
      _recentHeartRates.insert(0, HeartRateRecord(
        deviceMac: activity.deviceMac,
        bpm: activity.heartRate!,
        timestamp: activity.timestamp,
      ));
    }
    notifyListeners();
  }

  void setStepGoal(int goal) {
    _dailyStepGoal = goal;
    notifyListeners();
  }
}
