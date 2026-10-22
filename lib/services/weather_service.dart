import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather_data.dart';

class WeatherService {
  /// Obtém a previsão estendida do tempo (atual + próximos dias)
  static Future<WeatherData> fetchWeather({
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

    // Fallback padrão se não houver internet
    return WeatherData(
      temp: 24,
      condition: "Ensolarado",
      code: 0,
      city: city,
      humidity: 55,
      windSpeed: 10,
      dailyForecast: [
        DailyForecastItem(day: "Hoje", tempMax: 26, tempMin: 20, condition: "Ensolarado", code: 0),
        DailyForecastItem(day: "Amanhã", tempMax: 27, tempMin: 19, condition: "Parcialmente Nublado", code: 1),
        DailyForecastItem(day: "Depois", tempMax: 25, tempMin: 18, condition: "Ensolarado", code: 0),
      ],
      provider: "mock",
    );
  }

  static Future<WeatherData?> _fetchOpenMeteo(double lat, double lon, String city) async {
    try {
      final url = Uri.parse(
        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon"
        "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
        "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset"
        "&timezone=auto",
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

        final dailyForecast = <DailyForecastItem>[];
        for (int i = 0; i < timeList.length && i < 5; i++) {
          final dCode = i < codeList.length ? (codeList[i] as num).toInt() : 0;
          final dMax = i < maxList.length ? (maxList[i] as num).round() : (temp + 2);
          final dMin = i < minList.length ? (minList[i] as num).round() : (temp - 3);
          final dayLabel = i == 0 ? "Hoje" : (i == 1 ? "Amanhã" : "Dia ${i + 1}");

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
      final url = Uri.parse("https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$token&units=metric&lang=pt_br");
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final main = data['main'] as Map<String, dynamic>? ?? {};
        final weather = (data['weather'] as List<dynamic>?)?.firstOrNull as Map<String, dynamic>? ?? {};
        final wind = data['wind'] as Map<String, dynamic>? ?? {};

        final temp = (main['temp'] as num?)?.round() ?? 24;
        final hum = (main['humidity'] as num?)?.toInt() ?? 50;
        final windSpeed = ((wind['speed'] as num?)?.toDouble() ?? 3.0) * 3.6; // m/s para km/h
        final cond = weather['description'] as String? ?? "Ensolarado";
        final code = (weather['id'] as num?)?.toInt() ?? 800;

        return WeatherData(
          temp: temp,
          condition: cond,
          code: code,
          city: data['name'] as String? ?? city,
          humidity: hum,
          windSpeed: windSpeed.round(),
          provider: "openweathermap",
          dailyForecast: [
            DailyForecastItem(day: "Hoje", tempMax: temp + 2, tempMin: temp - 3, condition: cond, code: code),
          ],
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<WeatherData?> _fetchWeatherApi(double lat, double lon, String city, String token) async {
    try {
      final url = Uri.parse("https://api.weatherapi.com/v1/forecast.json?key=$token&q=$lat,$lon&days=5&lang=pt");
      final resp = await http.get(url).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>? ?? {};
        final condition = current['condition'] as Map<String, dynamic>? ?? {};
        final location = data['location'] as Map<String, dynamic>? ?? {};

        final temp = (current['temp_c'] as num?)?.round() ?? 24;
        final hum = (current['humidity'] as num?)?.toInt() ?? 50;
        final wind = (current['wind_kph'] as num?)?.round() ?? 10;
        final cond = condition['text'] as String? ?? "Ensolarado";
        final code = (condition['code'] as num?)?.toInt() ?? 1000;

        return WeatherData(
          temp: temp,
          condition: cond,
          code: code,
          city: location['name'] as String? ?? city,
          humidity: hum,
          windSpeed: wind,
          provider: "weatherapi",
          dailyForecast: [
            DailyForecastItem(day: "Hoje", tempMax: temp + 2, tempMin: temp - 3, condition: cond, code: code),
          ],
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
