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

  String _selectedProvider = "open-meteo";
  bool _useGps = true;
  bool _autoWeather = true;

  @override
  void initState() {
    super.initState();
    final dev = context.read<DeviceProvider>().device;
    final w = context.read<WeatherProvider>();

    _macCtrl = TextEditingController(text: dev?.macAddress ?? "");
    _keyCtrl = TextEditingController(text: dev?.authKey ?? "");
    _cityCtrl = TextEditingController(text: w.city);
    _tokenCtrl = TextEditingController(text: w.apiToken);
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
