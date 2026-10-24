import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/device_config.dart';
import '../../models/activity_data.dart';
import '../../models/heart_rate_record.dart';
import '../../models/sync_log.dart';
import '../../models/alarm_item.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('miband_app.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE activity_log ADD COLUMN spo2 INTEGER;');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE activity_log ADD COLUMN stress INTEGER;');
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Configuração de Dispositivos
    await db.execute('''
      CREATE TABLE device_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mac_address TEXT NOT NULL UNIQUE,
        auth_key TEXT NOT NULL,
        device_name TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        sync_interval_hours INTEGER NOT NULL DEFAULT 1,
        auto_weather INTEGER NOT NULL DEFAULT 1,
        last_sync_time TEXT
      )
    ''');

    // Logs de Atividade e Passos
    await db.execute('''
      CREATE TABLE activity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_mac TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        steps INTEGER NOT NULL DEFAULT 0,
        distance_meters INTEGER NOT NULL DEFAULT 0,
        calories INTEGER NOT NULL DEFAULT 0,
        heart_rate INTEGER,
        battery_level INTEGER,
        spo2 INTEGER,
        stress INTEGER
      )
    ''');

    // Registros de Frequência Cardíaca
    await db.execute('''
      CREATE TABLE heart_rate_record (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_mac TEXT NOT NULL,
        bpm INTEGER NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // Histórico de Sincronizações
    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_mac TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT NOT NULL,
        details TEXT
      )
    ''');

    // Alarmes do Dispositivo
    await db.execute('''
      CREATE TABLE alarms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_mac TEXT NOT NULL,
        alarm_index INTEGER NOT NULL,
        time TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        repetition INTEGER NOT NULL DEFAULT 128
      )
    ''');
  }

  // Operações de DeviceConfig
  Future<DeviceConfig?> getPrimaryDevice() async {
    final db = await database;
    final res = await db.query('device_config', orderBy: 'id DESC', limit: 1);
    if (res.isNotEmpty) {
      return DeviceConfig.fromMap(res.first);
    }
    return null;
  }

  Future<void> saveDevice(DeviceConfig config) async {
    final db = await database;
    final existing = await db.query(
      'device_config',
      where: 'mac_address = ?',
      whereArgs: [config.macAddress],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'device_config',
        config.toMap(),
        where: 'mac_address = ?',
        whereArgs: [config.macAddress],
      );
    } else {
      await db.insert('device_config', config.toMap());
    }
  }

  // Operações de Atividade
  Future<void> insertActivity(ActivityData activity) async {
    final db = await database;
    await db.insert('activity_log', activity.toMap());
  }

  Future<ActivityData?> getLatestActivity(String deviceMac) async {
    final db = await database;
    final res = await db.query(
      'activity_log',
      where: 'device_mac = ?',
      whereArgs: [deviceMac],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (res.isNotEmpty) {
      return ActivityData.fromMap(res.first);
    }
    return null;
  }

  Future<List<ActivityData>> getActivitiesForDays(String deviceMac, int days) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final res = await db.query(
      'activity_log',
      where: 'device_mac = ? AND timestamp >= ?',
      whereArgs: [deviceMac, since],
      orderBy: 'timestamp ASC',
    );
    return res.map((m) => ActivityData.fromMap(m)).toList();
  }

  // Operações de Frequência Cardíaca
  Future<void> insertHeartRate(HeartRateRecord record) async {
    final db = await database;
    await db.insert('heart_rate_record', record.toMap());
  }

  Future<List<HeartRateRecord>> getRecentHeartRates(String deviceMac, {int limit = 30}) async {
    final db = await database;
    final res = await db.query(
      'heart_rate_record',
      where: 'device_mac = ?',
      whereArgs: [deviceMac],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return res.map((m) => HeartRateRecord.fromMap(m)).toList();
  }

  // Operações de SyncLog
  Future<void> insertSyncLog(SyncLog log) async {
    final db = await database;
    await db.insert('sync_log', log.toMap());
  }

  Future<List<SyncLog>> getRecentSyncLogs({int limit = 50}) async {
    final db = await database;
    final res = await db.query(
      'sync_log',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return res.map((m) => SyncLog.fromMap(m)).toList();
  }

  // Operações de Alarmes
  Future<List<AlarmItem>> getAlarms(String deviceMac) async {
    final db = await database;
    final res = await db.query(
      'alarms',
      where: 'device_mac = ?',
      whereArgs: [deviceMac],
      orderBy: 'alarm_index ASC',
    );
    return res.map((m) => AlarmItem(
      index: m['alarm_index'] as int,
      time: m['time'] as String,
      enabled: (m['enabled'] as int) == 1,
      repetition: m['repetition'] as int,
    )).toList();
  }

  Future<void> saveAlarms(String deviceMac, List<AlarmItem> alarms) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('alarms', where: 'device_mac = ?', whereArgs: [deviceMac]);
      for (final a in alarms) {
        await txn.insert('alarms', {
          'device_mac': deviceMac,
          'alarm_index': a.index,
          'time': a.time,
          'enabled': a.enabled ? 1 : 0,
          'repetition': a.repetition,
        });
      }
    });
  }
}
