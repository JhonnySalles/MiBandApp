import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../models/weather_data.dart';

class WeatherCard extends StatelessWidget {
  final WeatherData? weather;
  final bool isLoading;
  final VoidCallback onRefresh;

  const WeatherCard({
    super.key,
    required this.weather,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (weather == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Carregando informações do clima...",
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppTheme.primaryOrange),
              onPressed: onRefresh,
            ),
          ],
        ),
      );
    }

    final w = weather!;
    final today = w.dailyForecast.isNotEmpty ? w.dailyForecast.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.cardSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: AppTheme.primaryOrange, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    w.city,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryOrange),
                      )
                    : const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 20),
                onPressed: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_getWeatherIcon(w.condition), color: const Color(0xFFFFB300), size: 48),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${w.temp}",
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                          letterSpacing: -1,
                        ),
                      ),
                      const Text(
                        "°C",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryOrange,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    w.condition,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (today != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("Máx: ${today.tempMax}°C", style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    Text("Mín: ${today.tempMin}°C", style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text("Umidade: ${w.humidity}%", style: const TextStyle(fontSize: 11, color: AppTheme.healthCyan)),
                  ],
                ),
            ],
          ),
          if (w.dailyForecast.length > 1) ...[
            const Divider(color: AppTheme.cardSubtle, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: w.dailyForecast.sublist(1, w.dailyForecast.length > 4 ? 4 : w.dailyForecast.length).map((d) {
                return Column(
                  children: [
                    Text(d.day, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Icon(_getWeatherIcon(d.condition), color: const Color(0xFFFFB300), size: 20),
                    const SizedBox(height: 4),
                    Text("${d.tempMax}° / ${d.tempMin}°", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getWeatherIcon(String cond) {
    final t = cond.toLowerCase();
    if (t.contains('tempestade') || t.contains('trovoada')) return Icons.flash_on_rounded;
    if (t.contains('chuva') || t.contains('garoa')) return Icons.grain_rounded;
    if (t.contains('neve')) return Icons.ac_unit_rounded;
    if (t.contains('nuvem') || t.contains('nublado')) return Icons.cloud_rounded;
    return Icons.wb_sunny_rounded;
  }
}
