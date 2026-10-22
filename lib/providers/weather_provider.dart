import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_data.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

class WeatherProvider extends ChangeNotifier {
  WeatherData? _weather;
  WeatherData? get weather => _weather;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _providerName = "open-meteo";
  String get providerName => _providerName;

  String _apiToken = "";
  String get apiToken => _apiToken;

  String _city = "São Paulo";
  String get city => _city;

  bool _useGps = true;
  bool get useGps => _useGps;

  WeatherProvider() {
    _loadSettings().then((_) => fetchWeather());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _providerName = prefs.getString('weather_provider') ?? "open-meteo";
    _apiToken = prefs.getString('weather_api_token') ?? "";
    _city = prefs.getString('weather_city') ?? "São Paulo";
    _useGps = prefs.getBool('weather_use_gps') ?? true;
    notifyListeners();
  }

  Future<void> saveSettings({
    required String providerName,
    required String apiToken,
    required String city,
    required bool useGps,
  }) async {
    _providerName = providerName;
    _apiToken = apiToken;
    _city = city;
    _useGps = useGps;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weather_provider', _providerName);
    await prefs.setString('weather_api_token', _apiToken);
    await prefs.setString('weather_city', _city);
    await prefs.setBool('weather_use_gps', _useGps);

    notifyListeners();
    await fetchWeather();
  }

  Future<void> fetchWeather() async {
    _isLoading = true;
    notifyListeners();

    try {
      double lat = LocationService.defaultLat;
      double lon = LocationService.defaultLon;

      if (_useGps) {
        final loc = await LocationService.getCurrentCoordinates();
        lat = loc.latitude;
        lon = loc.longitude;
      }

      _weather = await WeatherService.fetchWeather(
        latitude: lat,
        longitude: lon,
        provider: _providerName,
        apiToken: _apiToken,
        city: _city,
      );
    } catch (_) {
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
