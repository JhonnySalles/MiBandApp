import 'dart:convert';
import 'dart:typed_data';
import '../models/weather_data.dart';

class WeatherPacket {
  final String name;
  final Uint8List payload;
  final bool shouldEncrypt;

  WeatherPacket(this.name, this.payload, {this.shouldEncrypt = true});
}

class HuamiWeatherEncoder {
  /// Gera a suíte de 6 pacotes de clima oficiais Huami/Gadgetbridge
  static List<WeatherPacket> generateWeatherPackets(WeatherData weather) {
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch ~/ 1000;
    final tzOffsetSec = now.timeZoneOffset.inSeconds;
    final tzQuarters = (tzOffsetSec ~/ 900) & 0xFF;

    final condCode = mapToHuamiWeatherCode(weather.code, weather.condition);
    final targetCity = weather.city.isNotEmpty ? weather.city : "São Paulo";

    // 1. Location (ID = 8)
    final locBytes = BytesBuilder();
    locBytes.addByte(0x08);
    locBytes.add(utf8.encode(targetCity));
    locBytes.addByte(0x00);

    // 2. Current Temp (ID = 2)
    final curBytes = BytesBuilder();
    curBytes.addByte(0x02);
    curBytes.add(_uint32Le(ts));
    curBytes.addByte(tzQuarters);
    curBytes.addByte(condCode);
    curBytes.addByte(weather.temp & 0xFF);
    curBytes.add(utf8.encode(weather.condition));
    curBytes.addByte(0x00);

    // 3. Air Quality (ID = 4)
    final aqiBytes = BytesBuilder();
    aqiBytes.addByte(0x04);
    aqiBytes.add(_uint32Le(ts));
    aqiBytes.addByte(tzQuarters);
    aqiBytes.add([0xFF, 0xFF]); // -1 short LE
    aqiBytes.add(utf8.encode("(n/a)"));
    aqiBytes.addByte(0x00);

    // 4. Multi-day Forecast (ID = 1)
    // Conforme Huami Gadgetbridge Spec & MiBandServer: Hoje + até 6 dias subsequentes (total de até 7 dias)
    final forecastBytes = BytesBuilder();
    forecastBytes.addByte(0x01);
    forecastBytes.add(_uint32Le(ts));
    forecastBytes.addByte(tzQuarters);

    final futureDays = weather.dailyForecast.length > 1
        ? weather.dailyForecast.sublist(1, weather.dailyForecast.length > 7 ? 7 : weather.dailyForecast.length)
        : <DailyForecastItem>[];
    final todayItem = weather.dailyForecast.isNotEmpty ? weather.dailyForecast[0] : null;

    final todayMax = _clampTemp(todayItem?.tempMax ?? (weather.temp + 2));
    final todayMin = _clampTemp(todayItem?.tempMin ?? (weather.temp - 3));
    final todayCond = todayItem?.condition ?? weather.condition;
    final todayCode = mapToHuamiWeatherCode(todayItem?.code ?? weather.code, todayCond);

    final nrDays = 1 + futureDays.length;
    forecastBytes.addByte(nrDays & 0xFF);

    // Hoje (sempre o primeiro item da lista)
    forecastBytes.add([todayCode & 0xFF, todayCode & 0xFF, todayMax & 0xFF, todayMin & 0xFF]);
    forecastBytes.add(utf8.encode(todayCond));
    forecastBytes.addByte(0x00);

    // Próximos dias
    for (final day in futureDays) {
      final dCond = day.condition;
      final dCode = mapToHuamiWeatherCode(day.code, dCond);
      final dMax = _clampTemp(day.tempMax);
      final dMin = _clampTemp(day.tempMin);
      forecastBytes.add([dCode & 0xFF, dCode & 0xFF, dMax & 0xFF, dMin & 0xFF]);
      forecastBytes.add(utf8.encode(dCond));
      forecastBytes.addByte(0x00);
    }

    // 5. Wind & Humidity (ID = 64 / 0x40)
    final windBytes = BytesBuilder();
    windBytes.addByte(0x40);
    windBytes.add(_uint32Le(ts));
    windBytes.addByte(tzQuarters);
    windBytes.add(utf8.encode("${weather.windSpeed} km/h"));
    windBytes.addByte(0x00);
    windBytes.add(utf8.encode("${weather.humidity}%"));
    windBytes.addByte(0x00);

    // 6. Sunrise & Sunset (ID = 16 / 0x10)
    final sunParts = _parseTime(weather.sunrise, defaultH: 6, defaultM: 0);
    final setParts = _parseTime(weather.sunset, defaultH: 18, defaultM: 0);
    final sunBytes = BytesBuilder();
    sunBytes.addByte(0x10);
    sunBytes.add(_uint32Le(ts));
    sunBytes.addByte(tzQuarters);
    sunBytes.add([sunParts[0] & 0xFF, sunParts[1] & 0xFF, setParts[0] & 0xFF, setParts[1] & 0xFF]);

    return [
      WeatherPacket("Current", curBytes.toBytes()),
      WeatherPacket("AirQuality", aqiBytes.toBytes()),
      WeatherPacket("Forecast", forecastBytes.toBytes()),
      WeatherPacket("Location", locBytes.toBytes()),
      WeatherPacket("WindHumidity", windBytes.toBytes()),
      WeatherPacket("SunriseSunset", sunBytes.toBytes()),
    ];
  }

  static int _clampTemp(int t) {
    if (t < -50) return -50;
    if (t > 60) return 60;
    return t;
  }

  static Uint8List _uint32Le(int val) {
    final b = Uint8List(4);
    final bd = ByteData.sublistView(b);
    bd.setUint32(0, val, Endian.little);
    return b;
  }

  static List<int> _parseTime(String timeStr, {int defaultH = 6, int defaultM = 0}) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return [int.parse(parts[0]), int.parse(parts[1])];
      }
    } catch (_) {}
    return [defaultH, defaultM];
  }

  /// Mapeador semântico e numérico universal para os 21 códigos de ícones climáticos da Mi Band 6
  static int mapToHuamiWeatherCode(int? codeVal, String? conditionText) {
    if (conditionText != null && conditionText.isNotEmpty) {
      String txt = conditionText.toLowerCase().trim();
      txt = txt
          .replaceAll('á', 'a')
          .replaceAll('ã', 'a')
          .replaceAll('â', 'a')
          .replaceAll('é', 'e')
          .replaceAll('ê', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ô', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ç', 'c');

      if (txt.contains('tempestade') || txt.contains('trovoada') || txt.contains('raio') || txt.contains('thunder') || txt.contains('storm') || txt.contains('trovoes')) {
        return 4; // THUNDERSTORM
      }
      if (txt.contains('granizo') || txt.contains('hail')) {
        return 5; // HAIL
      }
      if ((txt.contains('chuva') || txt.contains('rain')) && (txt.contains('neve') || txt.contains('snow'))) {
        return 6; // RAIN_AND_SNOW
      }
      if (txt.contains('neve') || txt.contains('snow') || txt.contains('geada') || txt.contains('sleet')) {
        if (txt.contains('fraca') || txt.contains('leve') || txt.contains('light')) return 14; // LIGHT_SNOW
        if (txt.contains('forte') || txt.contains('pesada') || txt.contains('heavy')) return 16; // HEAVY_SNOW
        return 15; // MEDIUM_SNOW
      }
      if (txt.contains('chuva') || txt.contains('rain') || txt.contains('garoa') || txt.contains('drizzle') || txt.contains('pancada') || txt.contains('chuvisco') || txt.contains('precipitacao')) {
        if (txt.contains('torrencial') || txt.contains('pesada') || txt.contains('forte') || txt.contains('heavy') || txt.contains('intensa')) return 9; // HEAVY_RAIN
        if (txt.contains('leve') || txt.contains('garoa') || txt.contains('drizzle') || txt.contains('chuvisco') || txt.contains('fraca') || txt.contains('light')) return 7; // LIGHT_RAIN
        if ((txt.contains('sol') || txt.contains('aberturas')) && txt.contains('chuva')) return 3; // RAIN_WITH_SUN
        return 8; // MEDIUM_RAIN
      }
      if (txt.contains('nevoeiro') || txt.contains('neblina') || txt.contains('fog') || txt.contains('mist') || txt.contains('haze')) {
        return 18; // MIST
      }
      if (txt.contains('vento') || txt.contains('ventania') || txt.contains('wind')) {
        return 20; // WIND_AND_RAIN
      }
      if (txt.contains('parcial') || txt.contains('poucas nuvens') || txt.contains('parcialmente') || txt.contains('partly') || txt.contains('sol com nuvens') || txt.contains('aberturas de sol')) {
        return 1; // SCATTERED_CLOUDS
      }
      if (txt.contains('nublado') || txt.contains('encoberto') || txt.contains('cloud') || txt.contains('overcast')) {
        return 2; // CLOUDY
      }
      if (txt.contains('ensolarado') || txt.contains('limpo') || txt.contains('claro') || txt.contains('sunny') || txt.contains('clear')) {
        return 0; // CLEAR_SKY
      }
    }

    final c = codeVal ?? 0;

    // 1. Padrão WMO (Open-Meteo 0 a 99)
    if (c >= 0 && c <= 99) {
      if (c == 0) return 0; // CLEAR_SKY
      if (c == 1 || c == 2) return 1; // SCATTERED_CLOUDS
      if (c == 3) return 2; // CLOUDY
      if (c == 45 || c == 48) return 18; // MIST
      if (c == 51 || c == 53 || c == 55) return 7; // LIGHT_RAIN
      if (c == 56 || c == 57 || c == 66 || c == 67) return 6; // RAIN_AND_SNOW
      if (c == 61 || c == 63) return 8; // MEDIUM_RAIN
      if (c == 65 || c == 80 || c == 81 || c == 82) return 9; // HEAVY_RAIN
      if (c == 71 || c == 73 || c == 75 || c == 77 || c == 85 || c == 86) return 15; // MEDIUM_SNOW
      if (c >= 95) return 4; // THUNDERSTORM
      return 0;
    }

    // 2. Padrão OpenWeatherMap (200 - 804)
    if (c >= 200 && c <= 899) {
      if (c >= 200 && c <= 232) return 4; // THUNDERSTORM
      if (c >= 300 && c <= 321) return 19; // DRIZZLE
      if (c == 500 || c == 520) return 7; // LIGHT_RAIN
      if (c == 501 || c == 511 || c == 521 || c == 531) return 8; // MEDIUM_RAIN
      if (c == 502 || c == 503 || c == 504 || c == 522) return 9; // HEAVY_RAIN
      if (c >= 600 && c <= 622) return 15; // MEDIUM_SNOW
      if (c >= 701 && c <= 781) return 18; // MIST
      if (c == 800) return 0; // CLEAR_SKY
      if (c == 801 || c == 802) return 1; // SCATTERED_CLOUDS
      if (c == 803 || c == 804) return 2; // CLOUDY
      return 0;
    }

    // 3. Padrão WeatherAPI (1000 - 1300)
    if (c >= 1000 && c <= 1300) {
      if (c == 1000) return 0; // CLEAR_SKY
      if (c == 1003) return 1; // SCATTERED_CLOUDS
      if (c == 1006 || c == 1009) return 2; // CLOUDY
      if (c == 1030 || c == 1135 || c == 1147) return 18; // MIST
      if (c == 1063 || c == 1150 || c == 1153 || c == 1180 || c == 1183) return 7; // LIGHT_RAIN
      if (c == 1186 || c == 1189 || c == 1240) return 8; // MEDIUM_RAIN
      if (c == 1192 || c == 1195 || c == 1243 || c == 1246) return 9; // HEAVY_RAIN
      if (c == 1087 || c == 1273 || c == 1276) return 4; // THUNDERSTORM
      if (c == 1066 || c == 1114 || c == 1210 || c == 1213 || c == 1216 || c == 1219 || c == 1222 || c == 1225) return 15; // MEDIUM_SNOW
      return 0;
    }

    return 0;
  }
}
