class DeviceConfig {
  final int? id;
  final String macAddress;
  final String authKey;
  final String deviceName;
  final bool isActive;
  final int syncIntervalHours;
  final bool autoWeather;
  final DateTime? lastSyncTime;

  DeviceConfig({
    this.id,
    required this.macAddress,
    required this.authKey,
    this.deviceName = "Mi Smart Band 6",
    this.isActive = true,
    this.syncIntervalHours = 1,
    this.autoWeather = true,
    this.lastSyncTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'mac_address': macAddress,
      'auth_key': authKey,
      'device_name': deviceName,
      'is_active': isActive ? 1 : 0,
      'sync_interval_hours': syncIntervalHours,
      'auto_weather': autoWeather ? 1 : 0,
      'last_sync_time': lastSyncTime?.toIso8601String(),
    };
  }

  factory DeviceConfig.fromMap(Map<String, dynamic> map) {
    return DeviceConfig(
      id: map['id'] as int?,
      macAddress: map['mac_address'] as String,
      authKey: map['auth_key'] as String,
      deviceName: map['device_name'] as String? ?? "Mi Smart Band 6",
      isActive: (map['is_active'] as int? ?? 1) == 1,
      syncIntervalHours: map['sync_interval_hours'] as int? ?? 1,
      autoWeather: (map['auto_weather'] as int? ?? 1) == 1,
      lastSyncTime: map['last_sync_time'] != null ? DateTime.tryParse(map['last_sync_time'] as String) : null,
    );
  }

  DeviceConfig copyWith({
    int? id,
    String? macAddress,
    String? authKey,
    String? deviceName,
    bool? isActive,
    int? syncIntervalHours,
    bool? autoWeather,
    DateTime? lastSyncTime,
  }) {
    return DeviceConfig(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      authKey: authKey ?? this.authKey,
      deviceName: deviceName ?? this.deviceName,
      isActive: isActive ?? this.isActive,
      syncIntervalHours: syncIntervalHours ?? this.syncIntervalHours,
      autoWeather: autoWeather ?? this.autoWeather,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}
