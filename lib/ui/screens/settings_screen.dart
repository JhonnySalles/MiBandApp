import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/device_provider.dart';
import '../../providers/weather_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _macCtrl;
  late TextEditingController _keyCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _tokenCtrl;
  late TextEditingController _stepGoalCtrl;
  late TextEditingController _calorieGoalCtrl;

  String _selectedProvider = "open-meteo";
  bool _useGps = true;
  bool _autoWeather = true;
  int _hrInterval = 1;
  bool _stressMonitoring = true;
  bool _isApplyingHealth = false;

  bool _rightWrist = false;
  String _liftWristMode = "all_day";
  String _nightMode = "sunset";
  String _bandLang = "pt_BR";
  bool _isApplyingHw = false;
  Map<String, String>? _deviceInfo;
  bool _isLoadingInfo = false;

  @override
  void initState() {
    super.initState();
    final dev = context.read<DeviceProvider>().device;
    final w = context.read<WeatherProvider>();

    _macCtrl = TextEditingController(text: dev?.macAddress ?? "");
    _keyCtrl = TextEditingController(text: dev?.authKey ?? "");
    _cityCtrl = TextEditingController(text: w.city);
    _tokenCtrl = TextEditingController(text: w.apiToken);
    _stepGoalCtrl = TextEditingController(text: "10000");
    _calorieGoalCtrl = TextEditingController(text: "300");
    _selectedProvider = w.providerName;
    _useGps = w.useGps;
    _autoWeather = dev?.autoWeather ?? true;
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _keyCtrl.dispose();
    _cityCtrl.dispose();
    _tokenCtrl.dispose();
    _stepGoalCtrl.dispose();
    _calorieGoalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devProv = context.watch<DeviceProvider>();
    final weatherProv = context.watch<WeatherProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Configurações"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Seção Mi Band
          _buildSectionHeader("Dispositivo Mi Band", Icons.watch_rounded),
          const SizedBox(height: 12),
          Material(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _macCtrl,
                        decoration: const InputDecoration(
                          labelText: "MAC Address da Mi Band",
                          hintText: "Ex: E4:5F:01:23:45:67",
                          prefixIcon: Icon(Icons.bluetooth_rounded, color: AppTheme.primaryOrange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      onPressed: devProv.isScanning
                          ? null
                          : () async {
                              await devProv.scanNearby();
                              if (context.mounted) _showDevicePicker(context, devProv);
                            },
                      icon: devProv.isScanning
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.search_rounded),
                      label: const Text("Buscar"),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyCtrl,
                  decoration: InputDecoration(
                    labelText: "Auth Key (32 caracteres hexadecimais)",
                    hintText: "Ex: 0123456789abcdef0123456789abcdef",
                    prefixIcon: const Icon(Icons.key_rounded, color: AppTheme.primaryOrange),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.help_outline_rounded, color: AppTheme.textSecondary),
                      onPressed: _showAuthKeyHelp,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.primaryOrange,
                  title: const Text("Enviar Clima na Sincronização", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Atualiza o visor do relógio automaticamente a cada sync", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  value: _autoWeather,
                  onChanged: (val) => setState(() => _autoWeather = val),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Seção Clima & Localização
        _buildSectionHeader("Clima & Localização", Icons.cloud_rounded),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedProvider,
                  decoration: const InputDecoration(
                    labelText: "Provedor de Previsão do Tempo",
                    prefixIcon: Icon(Icons.public_rounded, color: AppTheme.healthCyan),
                  ),
                  dropdownColor: AppTheme.cardBackground,
                  items: const [
                    DropdownMenuItem(value: "open-meteo", child: Text("Open-Meteo (Gratuito / Sem API Key)")),
                    DropdownMenuItem(value: "openweathermap", child: Text("OpenWeatherMap (Requer API Key)")),
                    DropdownMenuItem(value: "weatherapi", child: Text("WeatherAPI (Requer API Key)")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedProvider = val);
                  },
                ),
                if (_selectedProvider != "open-meteo") ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: "Chave de API do Provedor",
                      hintText: "Cole sua chave de API aqui",
                      prefixIcon: Icon(Icons.vpn_key_rounded, color: AppTheme.healthCyan),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.healthCyan,
                  title: const Text("Localização Automática (GPS)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Usa coordenadas do GPS para buscar o tempo local", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  value: _useGps,
                  onChanged: (val) => setState(() => _useGps = val),
                ),
                if (!_useGps) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: "Cidade Padrão",
                      hintText: "Ex: São Paulo",
                      prefixIcon: Icon(Icons.location_city_rounded, color: AppTheme.healthCyan),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Seção Saúde e Sensores da Pulseira
        _buildSectionHeader("Monitoramento de Saúde & Sensores", Icons.favorite_rounded),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _hrInterval,
                  decoration: const InputDecoration(
                    labelText: "Frequência Cardíaca Periódica",
                    prefixIcon: Icon(Icons.monitor_heart_rounded, color: AppTheme.heartRed),
                  ),
                  dropdownColor: AppTheme.cardBackground,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text("Desativado (Manual)")),
                    DropdownMenuItem(value: 1, child: Text("A cada 1 minuto")),
                    DropdownMenuItem(value: 5, child: Text("A cada 5 minutos")),
                    DropdownMenuItem(value: 10, child: Text("A cada 10 minutos")),
                    DropdownMenuItem(value: 30, child: Text("A cada 30 minutos")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _hrInterval = val);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _stepGoalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Meta de Passos",
                          prefixIcon: Icon(Icons.directions_walk_rounded, color: AppTheme.primaryOrange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _calorieGoalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Meta de Calorias (kcal)",
                          prefixIcon: Icon(Icons.local_fire_department_rounded, color: AppTheme.primaryOrange),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.stressPurple,
                  title: const Text("Monitoramento de Estresse (HRV)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Mede estresse periodicamente através da variabilidade cardíaca", style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  value: _stressMonitoring,
                  onChanged: (val) => setState(() => _stressMonitoring = val),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.heartRed,
                    side: const BorderSide(color: AppTheme.heartRed),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: _isApplyingHealth
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.heartRed))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text("Enviar Parâmetros de Saúde à Pulseira"),
                  onPressed: _isApplyingHealth
                      ? null
                      : () async {
                          setState(() => _isApplyingHealth = true);
                          try {
                            final stepGoal = int.tryParse(_stepGoalCtrl.text) ?? 10000;
                            final calGoal = int.tryParse(_calorieGoalCtrl.text) ?? 300;

                            final hrOk = await devProv.setHeartRateInterval(_hrInterval);
                            final goalsOk = await devProv.setFitnessGoals(stepGoal: stepGoal, calorieGoal: calGoal);
                            final stressOk = await devProv.setStressMonitoring(enabled: _stressMonitoring, intervalMinutes: 5);

                            if (context.mounted) {
                              if (hrOk || goalsOk || stressOk) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Parâmetros de saúde e metas aplicados com sucesso na Mi Band!")),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Não foi possível enviar para a pulseira. Verifique a conexão BLE.")),
                                );
                              }
                            }
                          } finally {
                            if (mounted) setState(() => _isApplyingHealth = false);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Seção Personalização de Hardware
        _buildSectionHeader("Personalização do Hardware", Icons.tune_rounded),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.healthCyan,
                  title: const Text("Localização de Uso", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(_rightWrist ? "Pulso Direito (Calibração acelerômetro)" : "Pulso Esquerdo (Calibração acelerômetro)", style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  value: _rightWrist,
                  onChanged: (val) => setState(() => _rightWrist = val),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _liftWristMode,
                  decoration: const InputDecoration(
                    labelText: "Levantar Pulso para Ver Tela",
                    prefixIcon: Icon(Icons.screen_rotation_rounded, color: AppTheme.primaryOrange),
                  ),
                  dropdownColor: AppTheme.cardBackground,
                  items: const [
                    DropdownMenuItem(value: "all_day", child: Text("Ativado o dia todo")),
                    DropdownMenuItem(value: "scheduled", child: Text("Programado (07:00 às 22:00)")),
                    DropdownMenuItem(value: "off", child: Text("Desativado")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _liftWristMode = val);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _nightMode,
                  decoration: const InputDecoration(
                    labelText: "Modo Noturno (Redução de Brilho)",
                    prefixIcon: Icon(Icons.nightlight_round, color: AppTheme.healthCyan),
                  ),
                  dropdownColor: AppTheme.cardBackground,
                  items: const [
                    DropdownMenuItem(value: "sunset", child: Text("Automático ao pôr do sol")),
                    DropdownMenuItem(value: "scheduled", child: Text("Programado (22:00 às 07:00)")),
                    DropdownMenuItem(value: "off", child: Text("Desativado")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _nightMode = val);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _bandLang,
                  decoration: const InputDecoration(
                    labelText: "Idioma da Pulseira",
                    prefixIcon: Icon(Icons.language_rounded, color: AppTheme.primaryOrange),
                  ),
                  dropdownColor: AppTheme.cardBackground,
                  items: const [
                    DropdownMenuItem(value: "pt_BR", child: Text("Português (Brasil)")),
                    DropdownMenuItem(value: "en_US", child: Text("Inglês (United States)")),
                    DropdownMenuItem(value: "es_ES", child: Text("Espanhol (España)")),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _bandLang = val);
                  },
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.healthCyan,
                    side: const BorderSide(color: AppTheme.healthCyan),
                    minimumSize: const Size(double.infinity, 44),
                  ),
                  icon: _isApplyingHw
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.healthCyan))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: const Text("Aplicar Configurações no Hardware"),
                  onPressed: _isApplyingHw
                      ? null
                      : () async {
                          setState(() => _isApplyingHw = true);
                          try {
                            final wOk = await devProv.setWearLocation(rightWrist: _rightWrist);
                            final lOk = await devProv.setLiftWrist(mode: _liftWristMode);
                            final nOk = await devProv.setNightMode(mode: _nightMode);
                            final gOk = await devProv.setBandLanguage(_bandLang);

                            if (context.mounted) {
                              if (wOk || lOk || nOk || gOk) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Configurações de hardware aplicadas com sucesso!")),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Falha ao comunicar com a pulseira via BLE.")),
                                );
                              }
                            }
                          } finally {
                            if (mounted) setState(() => _isApplyingHw = false);
                          }
                        },
                ),
                const SizedBox(height: 14),
                const Divider(color: AppTheme.cardSubtle),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Diagnóstico do Dispositivo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      icon: _isLoadingInfo
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text("Consultar"),
                      onPressed: _isLoadingInfo
                          ? null
                          : () async {
                              setState(() => _isLoadingInfo = true);
                              try {
                                final info = await devProv.readDeviceInfo();
                                if (mounted && info != null) {
                                  setState(() => _deviceInfo = info);
                                }
                              } finally {
                                if (mounted) setState(() => _isLoadingInfo = false);
                              }
                            },
                    ),
                  ],
                ),
                if (_deviceInfo != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.darkBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Modelo: ${_deviceInfo!['model'] ?? 'Mi Smart Band 6'}", style: const TextStyle(fontSize: 12)),
                        Text("Firmware: ${_deviceInfo!['firmware_version'] ?? 'N/A'}", style: const TextStyle(fontSize: 12)),
                        Text("Hardware: ${_deviceInfo!['hardware_version'] ?? 'N/A'}", style: const TextStyle(fontSize: 12)),
                        Text("Serial: ${_deviceInfo!['serial_number'] ?? 'N/A'}", style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Botões de Ação
        ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () async {
              final cleanKey = _keyCtrl.text.trim().replaceAll("0x", "").replaceAll("0X", "");
              if (cleanKey.length != 32 && cleanKey.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("A Auth Key possui ${cleanKey.length} caracteres. Ela deve conter exatamente 32 caracteres hexadecimais.")),
                );
                return;
              }

              await devProv.saveConfig(
                macAddress: _macCtrl.text,
                authKey: cleanKey,
                autoWeather: _autoWeather,
              );

              await weatherProv.saveSettings(
                providerName: _selectedProvider,
                apiToken: _tokenCtrl.text.trim(),
                city: _cityCtrl.text.trim(),
                useGps: _useGps,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Configurações salvas com sucesso!")),
                );
              }
            },
            child: const Text("Salvar Configurações", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryOrange, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ],
    );
  }

  void _showDevicePicker(BuildContext context, DeviceProvider prov) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final devices = prov.discoveredDevices;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Dispositivos BLE Encontrados", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Selecione sua Mi Band na lista abaixo:", style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              if (devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text("Nenhum dispositivo encontrado nas proximidades.", style: TextStyle(color: AppTheme.textSecondary))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(color: AppTheme.cardSubtle),
                    itemBuilder: (c, idx) {
                      final d = devices[idx];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth_rounded, color: AppTheme.primaryOrange),
                        title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${d.address} • Sinal: ${d.rssi} dBm"),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                        onTap: () {
                          _macCtrl.text = d.address;
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showAuthKeyHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text("O que é a Auth Key?"),
        content: const Text(
          "A Xiaomi Mi Band requer uma chave de autenticação (Auth Key de 32 caracteres hexadecimais) para estabelecer a conexão criptografada BLE.\n\n"
          "Essa chave é gerada pelo ecossistema Xiaomi no momento do pareamento com sua conta.\n\n"
          "Você pode extrair essa chave da sua conta Mi utilizando ferramentas como o 'huami-token' ou o arquivo de backup do Zepp / Zepp Life.",
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Entendi", style: TextStyle(color: AppTheme.primaryOrange)),
          ),
        ],
      ),
    );
  }
}
