class ActivityData {
  final int? id;
  final String deviceMac;
  final DateTime timestamp;
  final int steps;
  final int distanceMeters;
  final int calories;
  final int? heartRate;
  final int? batteryLevel;
  final int? spo2;
  final int? stress;

  ActivityData({
    this.id,
    required this.deviceMac,
    required this.timestamp,
    this.steps = 0,
    this.distanceMeters = 0,
    this.calories = 0,
    this.heartRate,
    this.batteryLevel,
    this.spo2,
    this.stress,
  });

  double get distanceKm => distanceMeters / 1000.0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_mac': deviceMac,
      'timestamp': timestamp.toIso8601String(),
      'steps': steps,
      'distance_meters': distanceMeters,
      'calories': calories,
      'heart_rate': heartRate,
      'battery_level': batteryLevel,
      'spo2': spo2,
      'stress': stress,
    };
  }

  factory ActivityData.fromMap(Map<String, dynamic> map) {
    return ActivityData(
      id: map['id'] as int?,
      deviceMac: map['device_mac'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      steps: map['steps'] as int? ?? 0,
      distanceMeters: map['distance_meters'] as int? ?? 0,
      calories: map['calories'] as int? ?? 0,
      heartRate: map['heart_rate'] as int?,
      batteryLevel: map['battery_level'] as int?,
      spo2: map['spo2'] as int?,
      stress: map['stress'] as int?,
    );
  }

  ActivityData copyWith({
    int? id,
    String? deviceMac,
    DateTime? timestamp,
    int? steps,
    int? distanceMeters,
    int? calories,
    int? heartRate,
    int? batteryLevel,
    int? spo2,
    int? stress,
  }) {
    return ActivityData(
      id: id ?? this.id,
      deviceMac: deviceMac ?? this.deviceMac,
      timestamp: timestamp ?? this.timestamp,
      steps: steps ?? this.steps,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      calories: calories ?? this.calories,
      heartRate: heartRate ?? this.heartRate,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      spo2: spo2 ?? this.spo2,
      stress: stress ?? this.stress,
    );
  }
}
