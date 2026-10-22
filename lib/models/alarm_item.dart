class AlarmItem {
  final int index;
  final String time; // "HH:mm"
  final bool enabled;
  final int repetition; // bitmask: Mon=1, Tue=2, Wed=4, Thu=8, Fri=16, Sat=32, Sun=64, Once=128

  AlarmItem({
    required this.index,
    required this.time,
    required this.enabled,
    this.repetition = 128, // Once default
  });

  int get hour {
    final parts = time.split(':');
    return int.tryParse(parts[0]) ?? 7;
  }

  int get minute {
    final parts = time.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  String get repetitionDescription {
    if (repetition == 128 || repetition == 0) return 'Uma vez';
    if (repetition == 127) return 'Todos os dias';
    if (repetition == 31) return 'Seg a Sex';
    if (repetition == 96) return 'Fim de semana';

    final days = <String>[];
    if ((repetition & 1) != 0) days.add('Seg');
    if ((repetition & 2) != 0) days.add('Ter');
    if ((repetition & 4) != 0) days.add('Qua');
    if ((repetition & 8) != 0) days.add('Qui');
    if ((repetition & 16) != 0) days.add('Sex');
    if ((repetition & 32) != 0) days.add('Sáb');
    if ((repetition & 64) != 0) days.add('Dom');
    return days.join(', ');
  }

  Map<String, dynamic> toMap() {
    return {
      'index': index,
      'time': time,
      'enabled': enabled ? 1 : 0,
      'repetition': repetition,
    };
  }

  factory AlarmItem.fromMap(Map<String, dynamic> map) {
    return AlarmItem(
      index: map['index'] as int? ?? 0,
      time: map['time'] as String? ?? '07:00',
      enabled: (map['enabled'] as int? ?? 1) == 1,
      repetition: map['repetition'] as int? ?? 128,
    );
  }

  AlarmItem copyWith({
    int? index,
    String? time,
    bool? enabled,
    int? repetition,
  }) {
    return AlarmItem(
      index: index ?? this.index,
      time: time ?? this.time,
      enabled: enabled ?? this.enabled,
      repetition: repetition ?? this.repetition,
    );
  }
}
