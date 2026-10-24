import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';

class WeatherService {
  /// Obtém a previsão estendida do tempo (atual + próximos dias)
  static Future<WeatherData?> fetchWeather({
    required double latitude,
    required double longitude,
    String provider = "open-meteo",
    String? apiToken,
    String city = "São Paulo",
  }) async {
    final prov = provider.toLowerCase();

    if (prov == "openweathermap" && apiToken != null && apiToken.isNotEmpty) {
      final res = await _fetchOpenWeatherMap(latitude, longitude, city, apiToken);
      if (res != null) return res;
    } else if (prov == "weatherapi" && apiToken != null && apiToken.isNotEmpty) {
      final res = await _fetchWeatherApi(latitude, longitude, city, apiToken);
      if (res != null) return res;
    }

    // Padrão: Open-Meteo (100% gratuito e sem necessidade de chave de API)
    final res = await _fetchOpenMeteo(latitude, longitude, city);
    if (res != null) return res;

    return null;
  }

  static Future<WeatherData?> _fetchOpenMeteo(double lat, double lon, String city) async {
    try {
      final url = Uri.parse(
        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon"
        "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
        "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
        "&forecast_days=7&timezone=auto",
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>? ?? {};
        final daily = data['daily'] as Map<String, dynamic>? ?? {};

        final temp = (current['temperature_2m'] as num?)?.round() ?? 24;
        final wCode = (current['weather_code'] as num?)?.toInt() ?? 0;
        final hum = (current['relative_humidity_2m'] as num?)?.toInt() ?? 50;
        final wind = (current['wind_speed_10m'] as num?)?.round() ?? 10;

        final sunriseList = (daily['sunrise'] as List<dynamic>?) ?? [];
        final sunsetList = (daily['sunset'] as List<dynamic>?) ?? [];
        final maxList = (daily['temperature_2m_max'] as List<dynamic>?) ?? [];
        final minList = (daily['temperature_2m_min'] as List<dynamic>?) ?? [];
        final codeList = (daily['weather_code'] as List<dynamic>?) ?? [];
        final timeList = (daily['time'] as List<dynamic>?) ?? [];

        String sunrise = "06:00";
        String sunset = "18:00";
        if (sunriseList.isNotEmpty) {
          final s = sunriseList[0].toString();
          if (s.contains('T')) sunrise = s.split('T')[1].substring(0, 5);
        }
        if (sunsetList.isNotEmpty) {
          final s = sunsetList[0].toString();
          if (s.contains('T')) sunset = s.split('T')[1].substring(0, 5);
        }

        final ptWeekdays = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];
        final dailyForecast = <DailyForecastItem>[];

        for (int i = 0; i < timeList.length && i < 7; i++) {
          final dCode = i < codeList.length ? (codeList[i] as num).toInt() : 0;
          final dMax = i < maxList.length ? (maxList[i] as num).round() : (temp + 2);
          final dMin = i < minList.length ? (minList[i] as num).round() : (temp - 3);

          String dayLabel;
          if (i == 0) {
            dayLabel = "Hoje";
          } else if (i == 1) {
            dayLabel = "Amanhã";
          } else {
            try {
              final dObj = DateTime.parse(timeList[i].toString());
              dayLabel = ptWeekdays[dObj.weekday - 1];
            } catch (_) {
              dayLabel = "Dia ${i + 1}";
            }
          }

          dailyForecast.add(DailyForecastItem(
            day: dayLabel,
            tempMax: dMax,
            tempMin: dMin,
            condition: _wmoConditionText(dCode),
            code: dCode,
          ));
        }

        return WeatherData(
          temp: temp,
          condition: _wmoConditionText(wCode),
          code: wCode,
          city: city,
          humidity: hum,
          windSpeed: wind,
          sunrise: sunrise,
          sunset: sunset,
          dailyForecast: dailyForecast,
          provider: "open-meteo",
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<WeatherData?> _fetchOpenWeatherMap(double lat, double lon, String city, String token) async {
    try {
      final url = Uri.parse("https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&appid=$token&units=metric&lang=pt_br");
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final list = (data['list'] as List<dynamic>?) ?? [];
        final cityObj = data['city'] as Map<String, dynamic>? ?? {};

        if (list.isEmpty) return null;

        final first = list[0] as Map<String, dynamic>;
        final main0 = first['main'] as Map<String, dynamic>? ?? {};
        final weather0 = (first['weather'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>? ?? {};
        final wind0 = first['wind'] as Map<String, dynamic>? ?? {};

        final curTemp = (main0['temp'] as num?)?.round() ?? 24;
        final hum = (main0['humidity'] as num?)?.toInt() ?? 50;
        final windSpeed = ((wind0['speed'] as num?)?.toDouble() ?? 3.0) * 3.6;
        final cond = weather0['description'] as String? ?? "Ensolarado";
        final code = (weather0['id'] as num?)?.toInt() ?? 800;

        String sunrise = "06:00";
        String sunset = "18:00";
        final srTs = cityObj['sunrise'] as int?;
        final ssTs = cityObj['sunset'] as int?;
        if (srTs != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(srTs * 1000);
          sunrise = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        }
        if (ssTs != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ssTs * 1000);
          sunset = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        }

        // Agrupar previsões por data
        final Map<String, List<Map<String, dynamic>>> byDay = {};
        for (final item in list) {
          final dtTxt = (item as Map<String, dynamic>)['dt_txt'] as String? ?? '';
          if (dtTxt.length >= 10) {
            final dStr = dtTxt.substring(0, 10);
            byDay.putIfAbsent(dStr, () => []).add(item);
          }
        }

        final ptWeekdays = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];
        final dailyForecast = <DailyForecastItem>[];
        int dayIndex = 0;

        for (final entry in byDay.entries) {
          if (dayIndex >= 7) break;
          final dayItems = entry.value;
          int maxT = -100;
          int minT = 100;
          int dCode = code;
          String dCond = cond;

          for (final it in dayItems) {
            final m = it['main'] as Map<String, dynamic>? ?? {};
            final tMax = (m['temp_max'] as num?)?.round() ?? curTemp;
            final tMin = (m['temp_min'] as num?)?.round() ?? curTemp;
            if (tMax > maxT) maxT = tMax;
            if (tMin < minT) minT = tMin;
            final w = (it['weather'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>?;
            if (w != null) {
              dCode = (w['id'] as num?)?.toInt() ?? dCode;
              dCond = w['description'] as String? ?? dCond;
            }
          }

          String dayLabel;
          if (dayIndex == 0) {
            dayLabel = "Hoje";
          } else if (dayIndex == 1) {
            dayLabel = "Amanhã";
          } else {
            try {
              final dObj = DateTime.parse(entry.key);
              dayLabel = ptWeekdays[dObj.weekday - 1];
            } catch (_) {
              dayLabel = entry.key;
            }
          }

          dailyForecast.add(DailyForecastItem(
            day: dayLabel,
            tempMax: maxT > -100 ? maxT : curTemp + 2,
            tempMin: minT < 100 ? minT : curTemp - 3,
            condition: dCond,
            code: dCode,
          ));
          dayIndex++;
        }

        return WeatherData(
          temp: curTemp,
          condition: cond,
          code: code,
          city: cityObj['name'] as String? ?? city,
          humidity: hum,
          windSpeed: windSpeed.round(),
          sunrise: sunrise,
          sunset: sunset,
          provider: "openweathermap",
          dailyForecast: dailyForecast,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<WeatherData?> _fetchWeatherApi(double lat, double lon, String city, String token) async {
    try {
      final url = Uri.parse("https://api.weatherapi.com/v1/forecast.json?key=$token&q=$lat,$lon&days=7&lang=pt");
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>? ?? {};
        final condition = current['condition'] as Map<String, dynamic>? ?? {};
        final location = data['location'] as Map<String, dynamic>? ?? {};
        final forecast = data['forecast'] as Map<String, dynamic>? ?? {};
        final forecastDays = (forecast['forecastday'] as List<dynamic>?) ?? [];

        final temp = (current['temp_c'] as num?)?.round() ?? 24;
        final hum = (current['humidity'] as num?)?.toInt() ?? 50;
        final wind = (current['wind_kph'] as num?)?.round() ?? 10;
        final cond = condition['text'] as String? ?? "Ensolarado";
        final code = (condition['code'] as num?)?.toInt() ?? 1000;

        String sunrise = "06:00";
        String sunset = "18:00";
        if (forecastDays.isNotEmpty) {
          final astro = (forecastDays[0] as Map<String, dynamic>)['astro'] as Map<String, dynamic>? ?? {};
          sunrise = astro['sunrise'] as String? ?? "06:00";
          sunset = astro['sunset'] as String? ?? "18:00";
        }

        final ptWeekdays = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"];
        final dailyForecast = <DailyForecastItem>[];

        for (int i = 0; i < forecastDays.length && i < 7; i++) {
          final fd = forecastDays[i] as Map<String, dynamic>;
          final dayObj = fd['day'] as Map<String, dynamic>? ?? {};
          final condObj = dayObj['condition'] as Map<String, dynamic>? ?? {};
          final dateStr = fd['date'] as String? ?? '';

          String dayLabel;
          if (i == 0) {
            dayLabel = "Hoje";
          } else if (i == 1) {
            dayLabel = "Amanhã";
          } else {
            try {
              final dObj = DateTime.parse(dateStr);
              dayLabel = ptWeekdays[dObj.weekday - 1];
            } catch (_) {
              dayLabel = "Dia ${i + 1}";
            }
          }

          dailyForecast.add(DailyForecastItem(
            day: dayLabel,
            tempMax: (dayObj['maxtemp_c'] as num?)?.round() ?? (temp + 2),
            tempMin: (dayObj['mintemp_c'] as num?)?.round() ?? (temp - 3),
            condition: condObj['text'] as String? ?? cond,
            code: (condObj['code'] as num?)?.toInt() ?? code,
          ));
        }

        return WeatherData(
          temp: temp,
          condition: cond,
          code: code,
          city: location['name'] as String? ?? city,
          humidity: hum,
          windSpeed: wind,
          sunrise: sunrise,
          sunset: sunset,
          provider: "weatherapi",
          dailyForecast: dailyForecast,
        );
      }
    } catch (_) {}
    return null;
  }

  static String _wmoConditionText(int code) {
    switch (code) {
      case 0: return "Céu Limpo";
      case 1: return "Predominantemente Limpo";
      case 2: return "Parcialmente Nublado";
      case 3: return "Nublado";
      case 45:
      case 48: return "Nevoeiro";
      case 51:
      case 53:
      case 55: return "Garoa Leve";
      case 61:
      case 63: return "Chuva";
      case 65: return "Chuva Forte";
      case 71:
      case 73:
      case 75: return "Neve";
      case 80:
      case 81:
      case 82: return "Pancadas de Chuva";
      case 95:
      case 96:
      case 99: return "Tempestade";
      default: return "Ensolarado";
    }
  }
}
