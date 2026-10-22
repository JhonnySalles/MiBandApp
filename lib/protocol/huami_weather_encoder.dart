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
    final forecastBytes = BytesBuilder();
    forecastBytes.addByte(0x01);
    forecastBytes.add(_uint32Le(ts));
    forecastBytes.addByte(tzQuarters);

    final futureDays = weather.dailyForecast.length > 1
        ? weather.dailyForecast.sublist(1, weather.dailyForecast.length > 5 ? 5 : weather.dailyForecast.length)
        : weather.dailyForecast;
    final todayItem = weather.dailyForecast.isNotEmpty ? weather.dailyForecast[0] : null;

    final todayMax = todayItem?.tempMax ?? (weather.temp + 2);
    final todayMin = todayItem?.tempMin ?? (weather.temp - 3);
    final todayCond = todayItem?.condition ?? weather.condition;
    final todayCode = mapToHuamiWeatherCode(todayItem?.code ?? weather.code, todayCond);

    final nrDays = 1 + futureDays.length;
    forecastBytes.addByte(nrDays & 0xFF);

    // Hoje
    forecastBytes.add([todayCode & 0xFF, todayCode & 0xFF, todayMax & 0xFF, todayMin & 0xFF]);
    forecastBytes.add(utf8.encode(todayCond));
    forecastBytes.addByte(0x00);

    // Próximos dias
    for (final day in futureDays) {
      final dCond = day.condition;
      final dCode = mapToHuamiWeatherCode(day.code, dCond);
      forecastBytes.add([dCode & 0xFF, dCode & 0xFF, day.tempMax & 0xFF, day.tempMin & 0xFF]);
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

  /// Mapeador semântico e numérico para os 21 códigos de ícones climáticos da Mi Band 6
  static int mapToHuamiWeatherCode(int? codeVal, String? conditionText) {
    if (conditionText != null) {
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

      if (txt.contains('tempestade') || txt.contains('trovoada') || txt.contains('raio') || txt.contains('thunder') || txt.contains('storm')) {
        return 4; // THUNDERSTORM
      }
      if (txt.contains('granizo') || txt.contains('hail')) {
        return 5; // HAIL
      }
      if ((txt.contains('chuva') || txt.contains('rain')) && (txt.contains('neve') || txt.contains('snow'))) {
        return 6; // RAIN_AND_SNOW
      }
      if (txt.contains('neve') || txt.contains('snow') || txt.contains('geada')) {
        if (txt.contains('fraca') || txt.contains('leve') || txt.contains('light')) return 14;
        if (txt.contains('forte') || txt.contains('pesada') || txt.contains('heavy')) return 16;
        return 15; // MEDIUM_SNOW
      }
      if (txt.contains('chuva') || txt.contains('rain') || txt.contains('garoa') || txt.contains('drizzle') || txt.contains('pancada') || txt.contains('chuvisco')) {
        if (txt.contains('torrencial') || txt.contains('pesada') || txt.contains('forte') || txt.contains('heavy')) return 9;
        if (txt.contains('leve') || txt.contains('garoa') || txt.contains('drizzle') || txt.contains('chuvisco') || txt.contains('fraca')) return 7;
        if (txt.contains('sol') && txt.contains('chuva')) return 3; // RAIN_WITH_SUN
        return 8; // MEDIUM_RAIN
      }
      if (txt.contains('nevoeiro') || txt.contains('neblina') || txt.contains('fog') || txt.contains('mist') || txt.contains('haze')) {
        return 18; // MIST
      }
      if (txt.contains('vento') || txt.contains('ventania') || txt.contains('wind')) {
        return 20; // WIND_AND_RAIN
      }
      if (txt.contains('parcial') || txt.contains('poucas nuvens') || txt.contains('partly') || txt.contains('sol com nuvens')) {
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
    // Padrão WMO (Open-Meteo)
    if (c >= 0 && c <= 99) {
      if (c == 0) return 0;
      if (c == 1 || c == 2) return 1;
      if (c == 3) return 2;
      if (c == 45 || c == 48) return 18;
      if (c == 51 || c == 53 || c == 55) return 7;
      if (c == 56 || c == 57 || c == 66 || c == 67) return 6;
      if (c == 61 || c == 63) return 8;
      if (c == 65 || c == 80 || c == 81 || c == 82) return 9;
      if (c == 71 || c == 73 || c == 75 || c == 85) return 15;
      if (c >= 95) return 4;
    }
    return 0;
  }
}
