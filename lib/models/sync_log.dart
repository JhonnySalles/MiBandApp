class SyncLog {
  final int? id;
  final String deviceMac;
  final DateTime timestamp;
  final String status; // "SUCCESS", "ERROR", "IN_PROGRESS"
  final String message;
  final String? details;

  SyncLog({
    this.id,
    required this.deviceMac,
    required this.timestamp,
    required this.status,
    required this.message,
    this.details,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_mac': deviceMac,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'message': message,
      'details': details,
    };
  }

  factory SyncLog.fromMap(Map<String, dynamic> map) {
    return SyncLog(
      id: map['id'] as int?,
      deviceMac: map['device_mac'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
      status: map['status'] as String,
      message: map['message'] as String,
      details: map['details'] as String?,
    );
  }
}
