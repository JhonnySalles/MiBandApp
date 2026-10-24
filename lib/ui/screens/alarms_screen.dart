import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/alarm_item.dart';
import '../../providers/alarm_provider.dart';
import '../../providers/device_provider.dart';

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen> {
  final _msgTitleCtrl = TextEditingController(text: "Notificação");
  final _msgBodyCtrl = TextEditingController(text: "Olá da Mi Band App!");

  @override
  void initState() {
    super.initState();
    final dev = context.read<DeviceProvider>().device;
    if (dev != null) {
      context.read<AlarmProvider>().loadAlarms(dev.macAddress);
    }
  }

  @override
  void dispose() {
    _msgTitleCtrl.dispose();
    _msgBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarmProv = context.watch<AlarmProvider>();
    final devProv = context.watch<DeviceProvider>();
    final alarms = alarmProv.alarms;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Alarmes & Mensagens"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Seção de Alarmes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Alarmes da Pulseira", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (alarmProv.isSyncingAlarms)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryOrange)),
                    )
                  else ...[
                    IconButton(
                      tooltip: "Ler da pulseira",
                      icon: const Icon(Icons.download_rounded, color: AppTheme.healthCyan),
                      onPressed: devProv.device == null
                          ? null
                          : () async {
                              final ok = await alarmProv.readAlarmsFromBand(devProv.device!);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(ok ? "Alarmes lidos com sucesso da pulseira!" : "Nenhum alarme obtido")),
                                );
                              }
                            },
                    ),
                    IconButton(
                      tooltip: "Gravar na pulseira",
                      icon: const Icon(Icons.upload_rounded, color: AppTheme.primaryOrange),
                      onPressed: devProv.device == null
                          ? null
                          : () async {
                              final ok = await alarmProv.sendAlarmsToBand(devProv.device!);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(ok ? "Alarmes gravados e sincronizados com a Mi Band!" : "Falha ao gravar alarmes")),
                                );
                              }
                            },
                    ),
                  ],
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppTheme.primaryOrange),
                    icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    onPressed: () => _showAddAlarmDialog(context, alarmProv),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (alarms.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text("Nenhum alarme configurado.", style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            ...alarms.map((a) {
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Icon(
                    Icons.alarm_rounded,
                    color: a.enabled ? AppTheme.primaryOrange : AppTheme.textSecondary,
                    size: 28,
                  ),
                  title: Text(
                    a.time,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: a.enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                  subtitle: Text(
                    a.repetitionDescription,
                    style: TextStyle(color: a.enabled ? AppTheme.healthCyan : AppTheme.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        activeThumbColor: AppTheme.primaryOrange,
                        value: a.enabled,
                        onChanged: (_) => alarmProv.toggleAlarm(a.index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textSecondary, size: 20),
                        onPressed: () => alarmProv.deleteAlarm(a.index),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 28),

          // Seção de Envio de Mensagens / Notificações
          const Text("Enviar Mensagem para o Relógio", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "Transmite uma notificação com alerta vibratório para a tela da Mi Band",
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.cardBackground,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _msgTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Título da Notificação",
                    prefixIcon: Icon(Icons.title_rounded, color: AppTheme.primaryOrange),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgBodyCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: "Conteúdo da Mensagem",
                    prefixIcon: Icon(Icons.message_rounded, color: AppTheme.primaryOrange),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.healthCyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: devProv.device == null
                        ? null
                        : () async {
                            final title = _msgTitleCtrl.text.trim();
                            final text = _msgBodyCtrl.text.trim();
                            final ok = await devProv.sendNotification(title, text);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(ok ? "Notificação enviada com sucesso à tela da Mi Band!" : "Falha ao enviar notificação")),
                              );
                            }
                          },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text("Transmitir para o Relógio", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showAddAlarmDialog(BuildContext context, AlarmProvider prov) async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 7, minute: 0),
    );

    if (pickedTime != null) {
      final hourStr = pickedTime.hour.toString().padLeft(2, '0');
      final minStr = pickedTime.minute.toString().padLeft(2, '0');
      final newIndex = prov.alarms.isEmpty ? 0 : (prov.alarms.map((a) => a.index).reduce((a, b) => a > b ? a : b) + 1);

      await prov.addOrUpdateAlarm(AlarmItem(
        index: newIndex,
        time: "$hourStr:$minStr",
        enabled: true,
        repetition: 31, // Seg a Sex padrão
      ));
    }
  }
}
