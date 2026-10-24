import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/device_provider.dart';
import '../../providers/activity_provider.dart';
import '../../providers/weather_provider.dart';
import '../../services/ble_service.dart';
import '../widgets/step_gauge.dart';
import '../widgets/metric_card.dart';
import '../widgets/weather_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceProv = context.watch<DeviceProvider>();
    final activityProv = context.watch<ActivityProvider>();
    final weatherProv = context.watch<WeatherProvider>();

    final activity = activityProv.todayActivity;
    final isSyncing = deviceProv.connectionState == BleConnectionState.syncing;
    final isConnecting = deviceProv.connectionState == BleConnectionState.connecting;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Mi Band Fitness"),
            Text(
              deviceProv.device?.deviceName ?? "Nenhum dispositivo pareado",
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          _buildConnectionBadge(deviceProv.connectionState),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryOrange,
        onRefresh: () async {
          if (deviceProv.device != null) {
            final act = await deviceProv.sync(weather: weatherProv.weather);
            if (act != null) activityProv.updateActivity(act);
          }
          await weatherProv.fetchWeather();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Gauge circular de passos
            StepGauge(
              steps: activity?.steps ?? 0,
              goal: activityProv.dailyStepGoal,
              calories: activity?.calories ?? 0,
              distanceKm: activity?.distanceKm ?? 0.0,
            ),
            const SizedBox(height: 16),

            // Ações rápidas de sincronização e localização
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (isSyncing || isConnecting || deviceProv.device == null)
                        ? null
                        : () async {
                            final act = await deviceProv.sync(weather: weatherProv.weather);
                            if (act != null) {
                              activityProv.updateActivity(act);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Sincronização concluída com sucesso!")),
                                );
                              }
                            }
                          },
                    icon: (isSyncing || isConnecting)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync_rounded),
                    label: Text(isSyncing ? "Sincronizando..." : (isConnecting ? "Conectando..." : "Sincronizar")),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.cardSubtle,
                    padding: const EdgeInsets.all(14),
                  ),
                  tooltip: "Localizar pulseira (Vibrar)",
                  onPressed: deviceProv.device == null
                      ? null
                      : () async {
                          final ok = await deviceProv.vibrate();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? "Comando de vibração enviado!" : "Falha ao vibrar pulseira")),
                            );
                          }
                        },
                  icon: const Icon(Icons.vibration_rounded, color: AppTheme.healthCyan),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.cardSubtle,
                    padding: const EdgeInsets.all(14),
                  ),
                  tooltip: "Parar vibração",
                  onPressed: deviceProv.device == null
                      ? null
                      : () async {
                          final ok = await deviceProv.stopVibrate();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? "Comando de parar vibração enviado!" : "Falha ao interromper")),
                            );
                          }
                        },
                  icon: const Icon(Icons.stop_circle_outlined, color: AppTheme.heartRed),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cards de Métricas: Frequência Cardíaca & Bateria
            MetricCard(
              icon: Icons.favorite_rounded,
              iconColor: AppTheme.heartRed,
              title: "Frequência Cardíaca",
              value: activity?.heartRate != null ? "${activity!.heartRate}" : "--",
              unit: "BPM",
              subtitle: activity?.heartRate != null ? "Aferido recentemente" : "Toque em Medir para acionar o sensor",
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSubtle,
                  foregroundColor: AppTheme.heartRed,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: (isSyncing || deviceProv.device == null)
                    ? null
                    : () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Iniciando medição óptica de BPM... Mantenha a pulseira no pulso")),
                        );
                        final act = await deviceProv.sync(weather: weatherProv.weather, measureHr: true);
                        if (act != null) activityProv.updateActivity(act);
                      },
                child: const Text("Medir", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            MetricCard(
              icon: Icons.battery_charging_full_rounded,
              iconColor: AppTheme.batteryGreen,
              title: "Nível de Bateria",
              value: activity?.batteryLevel != null ? "${activity!.batteryLevel}" : "--",
              unit: "%",
              subtitle: deviceProv.device?.lastSyncTime != null
                  ? "Última sincronização: ${deviceProv.device!.lastSyncTime!.hour.toString().padLeft(2, '0')}:${deviceProv.device!.lastSyncTime!.minute.toString().padLeft(2, '0')}"
                  : "Não sincronizado hoje",
            ),
            const SizedBox(height: 12),

            MetricCard(
              icon: Icons.bloodtype_rounded,
              iconColor: const Color(0xFF00E5FF),
              title: "Oxigênio no Sangue (SpO2)",
              value: activity?.spo2 != null ? "${activity!.spo2}" : "--",
              unit: "%",
              subtitle: activity?.spo2 != null ? "Saturação normal em repouso" : "Acione para medir saturação",
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardSubtle,
                  foregroundColor: const Color(0xFF00E5FF),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: (isSyncing || deviceProv.device == null)
                    ? null
                    : () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Medindo SpO2... Mantenha o braço imóvel por ~15s")),
                        );
                        final val = await deviceProv.measureSpo2();
                        if (val != null && activity != null) {
                          activityProv.updateActivity(activity.copyWith(spo2: val));
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(val != null ? "SpO2 aferido: $val%" : "Não foi possível obter SpO2 no momento")),
                          );
                        }
                      },
                child: const Text("Medir", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),

            MetricCard(
              icon: Icons.psychology_rounded,
              iconColor: AppTheme.stressPurple,
              title: "Nível de Estresse (HRV)",
              value: activity?.stress != null ? "${activity!.stress}" : "--",
              unit: "/100",
              subtitle: () {
                final s = activity?.stress;
                if (s == null) return "Calculado a partir da variabilidade cardíaca (HRV)";
                if (s < 30) return "Relaxado";
                if (s < 60) return "Normal";
                if (s < 80) return "Médio";
                return "Alto";
              }(),
            ),
            const SizedBox(height: 16),

            // Card de Clima
            WeatherCard(
              weather: weatherProv.weather,
              isLoading: weatherProv.isLoading,
              onRefresh: () => weatherProv.fetchWeather(),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(BleConnectionState state) {
    Color bg;
    String label;
    IconData icon;

    switch (state) {
      case BleConnectionState.connected:
        bg = const Color(0xFF00E676);
        label = "Conectado";
        icon = Icons.bluetooth_connected_rounded;
        break;
      case BleConnectionState.connecting:
      case BleConnectionState.syncing:
        bg = AppTheme.primaryOrange;
        label = "Sincronizando";
        icon = Icons.sync_rounded;
        break;
      case BleConnectionState.scanning:
        bg = AppTheme.healthCyan;
        label = "Buscando";
        icon = Icons.bluetooth_searching_rounded;
        break;
      case BleConnectionState.error:
        bg = const Color(0xFFFF5252);
        label = "Erro";
        icon = Icons.error_outline_rounded;
        break;
      case BleConnectionState.disconnected:
        bg = AppTheme.textSecondary;
        label = "Desconectado";
        icon = Icons.bluetooth_disabled_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: bg, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: bg, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
