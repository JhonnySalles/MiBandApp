class BleConstants {
  // Huami 2021 Chunked Modern Protocol (Mi Band 6 / 7 / modern Amazfit)
  static const String uuidCharChunkedWrite = "00000016-0000-3512-2118-0009af100700";
  static const String uuidCharChunkedRead = "00000017-0000-3512-2118-0009af100700";
  static const String uuidCharChunkedOld = "00000020-0000-3512-2118-0009af100700";
  
  static const int chunked2021EndpointAuth = 130; // 0x82
  static const int chunked2021EndpointCompat = 0x0090; // 144 - Clima, Configurações e Alarmes

  // Device Information Service (DIS 0x180A)
  static const String uuidServiceDis = "0000180a-0000-1000-8000-00805f9b34fb";
  static const String uuidCharModel = "00002a24-0000-1000-8000-00805f9b34fb";
  static const String uuidCharSerial = "00002a25-0000-1000-8000-00805f9b34fb";
  static const String uuidCharFwRevision = "00002a26-0000-1000-8000-00805f9b34fb";
  static const String uuidCharHwRevision = "00002a27-0000-1000-8000-00805f9b34fb";
  static const String uuidCharSwRevision = "00002a28-0000-1000-8000-00805f9b34fb";

  // Legacy Huami Auth (Mi Band 2 / 3 / 4 / 5 inicial)
  static const String uuidServiceAuth = "0000fee1-0000-1000-8000-00805f9b34fb";
  static const String uuidCharAuth = "00000009-0000-3512-2118-0009af100700";

  // Basic info, Time & Activity
  static const String uuidServiceBasic = "0000fee0-0000-1000-8000-00805f9b34fb";
  static const String uuidCharSteps = "00000007-0000-3512-2118-0009af100700";
  static const String uuidCharBatteryLegacy = "00000006-0000-3512-2118-0009af100700";
  static const String uuidCharBatteryStandard = "00002a19-0000-1000-8000-00805f9b34fb";
  static const String uuidCharCurrentTime = "00002a2b-0000-1000-8000-00805f9b34fb";
  static const String uuidCharActivityData = "00000004-0000-3512-2118-0009af100700";
  static const String uuidCharActivityControl = "00000005-0000-3512-2118-0009af100700";

  // Standard BLE Heart Rate Service
  static const String uuidServiceHeartRate = "0000180d-0000-1000-8000-00805f9b34fb";
  static const String uuidCharHeartRateMeasure = "00002a37-0000-1000-8000-00805f9b34fb";
  static const String uuidCharHeartRateControl = "00002a39-0000-1000-8000-00805f9b34fb";

  // Vibration & Alerts
  static const String uuidCharAlert = "00002a06-0000-1000-8000-00805f9b34fb";
  static const String uuidCharNewAlert = "00002a46-0000-1000-8000-00805f9b34fb";
  static const String uuidCharAlertControl = "00002a44-0000-1000-8000-00805f9b34fb";
  static const String uuidCharHuamiAlert = "00000003-0000-3512-2118-0009af100700";
}
