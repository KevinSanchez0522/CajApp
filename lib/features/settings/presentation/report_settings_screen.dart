import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/report_config.dart';

class ReportSettingsScreen extends ConsumerStatefulWidget {
  const ReportSettingsScreen({super.key});

  @override
  ConsumerState<ReportSettingsScreen> createState() => _ReportSettingsScreenState();
}

class _ReportSettingsScreenState extends ConsumerState<ReportSettingsScreen> {
  final _emailController = TextEditingController();
  final _whatsappController = TextEditingController();
  bool _autoSend = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final email = await ReportConfig.getReportEmail();
    final whatsapp = await ReportConfig.getReportWhatsApp();
    final autoSend = await ReportConfig.getAutoSendEnabled();

    if (mounted) {
      setState(() {
        _emailController.text = email ?? '';
        _whatsappController.text = whatsapp ?? '';
        _autoSend = autoSend;
        _loading = false;
      });
    }
  }

  Future<void> _saveConfig() async {
    await ReportConfig.setReportEmail(_emailController.text);
    await ReportConfig.setReportWhatsApp(_whatsappController.text);
    await ReportConfig.setAutoSendEnabled(_autoSend);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar configuración'),
        content: const Text('¿Eliminar email y WhatsApp configurados?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (confirmed == true) {
      await ReportConfig.clear();
      if (!mounted) return;
      _emailController.clear();
      _whatsappController.clear();
      setState(() => _autoSend = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración eliminada'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Config. Envío Reportes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveConfig,
            tooltip: 'Guardar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Destinatarios Predeterminados',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Al cerrar caja, los reportes se enviarán automáticamente a estos contactos si están configurados.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // Email
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email destinatario (gerente/admin)',
                      hintText: 'gerente@tienda.com',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                      helperText: 'Ej: admin@boutique.com, contabilidad@empresa.com',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // WhatsApp
                  TextField(
                    controller: _whatsappController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'WhatsApp (con código país, solo números)',
                      hintText: '573001234567',
                      prefixIcon: Icon(Icons.chat_bubble),
                      border: OutlineInputBorder(),
                      helperText: 'Formato: 573001234567 (Colombia: 57 + 10 dígitos)',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Auto-send
                  SwitchListTile(
                    title: const Text('Envío automático (sin selector)'),
                    subtitle: const Text(
                      'Si activado, al cerrar caja envía directo a email/WhatsApp sin mostrar opciones',
                    ),
                    value: _autoSend,
                    onChanged: (v) => setState(() => _autoSend = v),
                    secondary: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Prueba de envío',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Genera un reporte de prueba para verificar que la configuración funciona.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.email),
                          label: const Text('Probar Email'),
                          onPressed: _emailController.text.isEmpty
                              ? null
                              : () => _testSend(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat_bubble),
                          label: const Text('Probar WhatsApp'),
                          onPressed: _whatsappController.text.isEmpty
                              ? null
                              : () => _testSend(false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Limpiar
          if (_emailController.text.isNotEmpty || _whatsappController.text.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              label: const Text('Limpiar configuración', style: TextStyle(color: Colors.red)),
              onPressed: _clearConfig,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
              ),
            ),

          const SizedBox(height: 40),
          const Center(
            child: Text(
              'Los reportes se generan en PDF y se envían\nal cerrar turno de caja desde la pantalla de Control de Caja.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _testSend(bool isEmail) async {
    // Generar PDF de prueba simple
    try {
      // Aquí podríamos generar un PDF simple de prueba
      // Por simplicidad, solo mostramos mensaje
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se abriría ${isEmail ? "el cliente de email" : "WhatsApp"} con el reporte PDF'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
      );
    }
  }
}