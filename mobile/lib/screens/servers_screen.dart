import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hub_service.dart';
import '../theme/app_theme.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key});

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  List<Map<String, dynamic>> _containers = [];
  bool _loading = false;
  String _hubHttp = HubService.defaultHubUrl().replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('hub_url');
    if (saved != null) {
      setState(() => _hubHttp = saved.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://'));
    }
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_hubHttp/servers')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _containers = List<Map<String, dynamic>>.from(data['containers'] as List));
      }
    } catch (_) {
      // UI polling should fail quietly; offline state is represented by stale/empty data.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _action(String id, String name, String action) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('$action contenedor', style: const TextStyle(color: AppTheme.accent)),
        content: Text('$action "$name"?', style: const TextStyle(color: AppTheme.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await http.post(Uri.parse('$_hubHttp/servers/$id/${action.toLowerCase()}'));
      _refresh();
    } catch (_) {
      // Keep the page responsive if Docker is temporarily unavailable.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contenedores'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _containers.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined, color: AppTheme.textSecondary, size: 48),
                  SizedBox(height: 12),
                  Text('Sin contenedores gestionables', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _containers.length,
              itemBuilder: (_, i) {
                final c = _containers[i];
                final id = c['id'] as String;
                final name = c['name'] as String;
                final running = c['running'] as bool? ?? false;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.circle, color: running ? AppTheme.success : AppTheme.textSecondary, size: 8),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name, style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline, color: running ? AppTheme.error : AppTheme.success),
                          onPressed: () => _action(id, name, running ? 'stop' : 'start'),
                          tooltip: running ? 'Detener' : 'Iniciar',
                        ),
                        IconButton(
                          icon: const Icon(Icons.restart_alt, color: AppTheme.textSecondary),
                          onPressed: () => _action(id, name, 'restart'),
                          tooltip: 'Reiniciar',
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        '${c['image']} - ${c['status']}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
