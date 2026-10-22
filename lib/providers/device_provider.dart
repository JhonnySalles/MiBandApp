import 'package:flutter/foundation.dart';
import '../core/database/app_database.dart';
import '../models/device_config.dart';
import '../models/activity_data.dart';
import '../models/weather_data.dart';
import '../services/ble_service.dart';

class DeviceProvider extends ChangeNotifier {
  DeviceConfig? _device;
  DeviceConfig? get device => _device;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<DiscoveredBand> _discoveredDevices = [];
  List<DiscoveredBand> get discoveredDevices => _discoveredDevices;

  List<String> _liveLogs = [];
  List<String> get liveLogs => _liveLogs;

  DeviceProvider() {
    _loadDevice();
    BleService.instance.stateStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });
    BleService.instance.logsStream.listen((logs) {
      _liveLogs = logs;
      notifyListeners();
    });
  }

  Future<void> _loadDevice() async {
    _device = await AppDatabase.instance.getPrimaryDevice();
    notifyListeners();
  }

  Future<void> saveConfig({
    required String macAddress,
    required String authKey,
    String deviceName = "Mi Smart Band 6",
    bool autoWeather = true,
  }) async {
    final updated = DeviceConfig(
      id: _device?.id,
      macAddress: macAddress.trim().toUpperCase(),
      authKey: authKey.trim().replaceAll("0x", "").replaceAll("0X", ""),
      deviceName: deviceName,
      autoWeather: autoWeather,
      lastSyncTime: _device?.lastSyncTime,
    );

    await AppDatabase.instance.saveDevice(updated);
    _device = updated;
    notifyListeners();
  }

  Future<void> scanNearby() async {
    _isScanning = true;
    _discoveredDevices = [];
    notifyListeners();

    _discoveredDevices = await BleService.instance.scanDevices();
    _isScanning = false;
    notifyListeners();
  }

  Future<ActivityData?> sync({WeatherData? weather, bool measureHr = true}) async {
    if (_device == null) return null;
    final activity = await BleService.instance.syncDevice(
      config: _device!,
      weather: weather,
      measureHr: measureHr,
    );
    await _loadDevice();
    return activity;
  }

  Future<bool> vibrate() async {
    if (_device == null) return false;
    return await BleService.instance.triggerVibrate(_device!);
  }

  Future<bool> sendNotification(String title, String text) async {
    if (_device == null) return false;
    return await BleService.instance.sendNotification(_device!, title, text);
  }
}
