import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final bool isDefault;

  LocationResult({required this.latitude, required this.longitude, this.isDefault = false});
}

class LocationService {
  // Coordenadas padrão (São Paulo)
  static const double defaultLat = -23.5505;
  static const double defaultLon = -46.6333;

  static Future<LocationResult> getCurrentCoordinates() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult(latitude: defaultLat, longitude: defaultLon, isDefault: true);
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationResult(latitude: defaultLat, longitude: defaultLon, isDefault: true);
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationResult(latitude: defaultLat, longitude: defaultLon, isDefault: true);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LocationResult(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return LocationResult(latitude: defaultLat, longitude: defaultLon, isDefault: true);
    }
  }
}
