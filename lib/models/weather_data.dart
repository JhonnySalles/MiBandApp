class DailyForecastItem {
  final String day;
  final int tempMax;
  final int tempMin;
  final String condition;
  final int code;

  DailyForecastItem({
    required this.day,
    required this.tempMax,
    required this.tempMin,
    required this.condition,
    this.code = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      'temp_max': tempMax,
      'temp_min': tempMin,
      'condition': condition,
      'code': code,
    };
  }

  factory DailyForecastItem.fromMap(Map<String, dynamic> map) {
    return DailyForecastItem(
      day: map['day'] as String? ?? 'Hoje',
      tempMax: map['temp_max'] as int? ?? 25,
      tempMin: map['temp_min'] as int? ?? 18,
      condition: map['condition'] as String? ?? 'Ensolarado',
      code: map['code'] as int? ?? 0,
    );
  }
}

class WeatherData {
  final int temp;
  final String condition;
  final int code;
  final String city;
  final int humidity;
  final int windSpeed;
  final String sunrise;
  final String sunset;
  final List<DailyForecastItem> dailyForecast;
  final String provider;

  WeatherData({
    required this.temp,
    required this.condition,
    this.code = 0,
    required this.city,
    this.humidity = 55,
    this.windSpeed = 12,
    this.sunrise = "06:00",
    this.sunset = "18:00",
    this.dailyForecast = const [],
    this.provider = "open-meteo",
  });

  Map<String, dynamic> toMap() {
    return {
      'temp': temp,
      'condition': condition,
      'code': code,
      'city': city,
      'humidity': humidity,
      'wind_speed': windSpeed,
      'sunrise': sunrise,
      'sunset': sunset,
      'provider': provider,
      'daily_forecast': dailyForecast.map((f) => f.toMap()).toList(),
    };
  }

  factory WeatherData.fromMap(Map<String, dynamic> map) {
    final list = map['daily_forecast'] as List<dynamic>? ?? [];
    return WeatherData(
      temp: map['temp'] as int? ?? 24,
      condition: map['condition'] as String? ?? 'Ensolarado',
      code: map['code'] as int? ?? 0,
      city: map['city'] as String? ?? 'São Paulo',
      humidity: map['humidity'] as int? ?? 55,
      windSpeed: map['wind_speed'] as int? ?? 12,
      sunrise: map['sunrise'] as String? ?? '06:00',
      sunset: map['sunset'] as String? ?? '18:00',
      provider: map['provider'] as String? ?? 'open-meteo',
      dailyForecast: list.map((item) => DailyForecastItem.fromMap(item as Map<String, dynamic>)).toList(),
    );
  }
}
