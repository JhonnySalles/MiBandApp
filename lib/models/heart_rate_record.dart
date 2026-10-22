class HeartRateRecord {
  final int? id;
  final String deviceMac;
  final int bpm;
  final DateTime timestamp;

  HeartRateRecord({
    this.id,
    required this.deviceMac,
    required this.bpm,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_mac': deviceMac,
      'bpm': bpm,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory HeartRateRecord.fromMap(Map<String, dynamic> map) {
    return HeartRateRecord(
      id: map['id'] as int?,
      deviceMac: map['device_mac'] as String,
      bpm: map['bpm'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
