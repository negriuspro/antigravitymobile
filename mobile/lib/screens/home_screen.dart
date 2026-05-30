import 'package:flutter/material.dart';
import '../services/hub_service.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _hub = HubService();
  bool _online = false;
  bool _checking = false;
  String _hubUrl = '';

  @override
  void initState() {
    super.initState();
    _loadAndCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAndCheck();
  }

  Future<void> _loadAndCheck() async {
    _hubUrl = await _hub.getHubUrl();
    _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() => _checking = true);
    final ok = await _hub.checkHealth(_hubUrl);
    if (mounted) setState(() { _online = ok; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Antigravity')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(online: _online, checking: _checking, url: _hubUrl, onRefresh: _checkServer),
            const SizedBox(height: 20),
            const Text('Acceso rápido', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 12),
            _QuickActions(),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool online;
  final bool checking;
  final String url;
  final VoidCallback onRefresh;

  const _StatusCard({required this.online, required this.checking, required this.url, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checking ? AppTheme.textSecondary : (online ? AppTheme.success : AppTheme.error),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checking ? 'Verificando...' : (online ? 'Hub online' : 'Hub offline'),
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.accent),
                  ),
                  Text(url, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppTheme.textSecondary, size: 20),
              onPressed: checking ? null : onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      ('Claude Code', Icons.terminal, '/claude-code'),
      ('Chat IA', Icons.hub_outlined, '/agi'),
      ('Chat Claude', Icons.auto_awesome_outlined, '/chat'),
      ('Servidores', Icons.dns_outlined, '/servers'),
      ('Tokens y Cuotas', Icons.data_usage_outlined, '/tokens'),
      ('Ajustes', Icons.settings_outlined, '/settings'),
    ];
    return Column(
      children: actions.map((a) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(a.$2, color: AppTheme.textPrimary, size: 20),
          title: Text(a.$1, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
          trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
          onTap: () => Navigator.pushNamed(context, a.$3),
        ),
      )).toList(),
    );
  }
}
