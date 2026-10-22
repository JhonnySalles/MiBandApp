import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/activity_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Histórico"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryOrange,
          labelColor: AppTheme.primaryOrange,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: "Passos"),
            Tab(text: "Batimentos"),
            Tab(text: "Logs"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStepsTab(),
          _buildHeartRateTab(),
          _buildLogsTab(),
        ],
      ),
    );
  }

  Widget _buildStepsTab() {
    final activityProv = context.watch<ActivityProvider>();
    final history = activityProv.history;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Passos nos Últimos Dias",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 180,
                child: history.isEmpty
                    ? const Center(child: Text("Nenhum histórico registrado ainda", style: TextStyle(color: AppTheme.textSecondary)))
                    : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: 12000,
                          barTouchData: BarTouchData(enabled: true),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (val, meta) {
                                  final idx = val.toInt();
                                  if (idx >= 0 && idx < history.length) {
                                    final d = history[idx].timestamp;
                                    return Text("${d.day}/${d.month}", style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary));
                                  }
                                  return const Text("");
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: history.asMap().entries.map((e) {
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: e.value.steps.toDouble(),
                                  color: AppTheme.primaryOrange,
                                  width: 16,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text("Registros Detalhados", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text("Nenhuma atividade gravada.", style: TextStyle(color: AppTheme.textSecondary))),
          )
        else
          ...history.reversed.map((a) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0x22FF6B00),
                  child: Icon(Icons.directions_walk_rounded, color: AppTheme.primaryOrange),
                ),
                title: Text("${a.steps} passos", style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${a.distanceKm.toStringAsFixed(2)} km  •  ${a.calories} kcal"),
                trailing: Text(
                  "${a.timestamp.day.toString().padLeft(2, '0')}/${a.timestamp.month.toString().padLeft(2, '0')} ${a.timestamp.hour.toString().padLeft(2, '0')}:${a.timestamp.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHeartRateTab() {
    final activityProv = context.watch<ActivityProvider>();
    final list = activityProv.recentHeartRates;

    if (list.isEmpty) {
      return const Center(
        child: Text("Nenhuma medição de batimentos ainda.\nToque em 'Medir' na tela inicial.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final r = list[idx];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x22FF334B),
              child: Icon(Icons.favorite_rounded, color: AppTheme.heartRed),
            ),
            title: Text("${r.bpm} BPM", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(_getZoneDescription(r.bpm)),
            trailing: Text(
              "${r.timestamp.day.toString().padLeft(2, '0')}/${r.timestamp.month.toString().padLeft(2, '0')} ${r.timestamp.hour.toString().padLeft(2, '0')}:${r.timestamp.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    final activityProv = context.watch<ActivityProvider>();
    final logs = activityProv.syncLogs;

    if (logs.isEmpty) {
      return const Center(child: Text("Nenhum log registrado ainda.", style: TextStyle(color: AppTheme.textSecondary)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, idx) {
        final l = logs[idx];
        final isSuccess = l.status == "SUCCESS";
        final color = isSuccess ? const Color(0xFF00E676) : const Color(0xFFFF5252);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
              color: color,
            ),
            title: Text(l.message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: l.details != null ? Text(l.details!, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)) : null,
            trailing: Text(
              "${l.timestamp.hour.toString().padLeft(2, '0')}:${l.timestamp.minute.toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        );
      },
    );
  }

  String _getZoneDescription(int bpm) {
    if (bpm < 60) return "Repouso / Baixo";
    if (bpm <= 100) return "Normal / Moderado";
    if (bpm <= 140) return "Aeróbico / Ativo";
    return "Anaeróbico / Intenso";
  }
}
