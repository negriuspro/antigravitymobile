import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hub_service.dart';
import '../services/api_keys_service.dart';
import '../theme/app_theme.dart';

class _HubProfile {
  String name;
  String ip;
  String port;
  _HubProfile({required this.name, required this.ip, required this.port});

  String get wsUrl => 'ws://$ip:$port';

  Map<String, dynamic> toJson() => {'name': name, 'ip': ip, 'port': port};
  factory _HubProfile.fromJson(Map<String, dynamic> j) =>
      _HubProfile(name: j['name'] as String, ip: j['ip'] as String, port: j['port'] as String);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _hub = HubService();
  final _keysSvc = ApiKeysService();
  List<_HubProfile> _profiles = [];
  String _activeUrl = '';
  bool _loading = true;
  Map<String, String> _apiKeys = {};
  bool _keysExpanded = false;

  static const _profilesKey = 'hub_profiles_v1';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _activeUrl = await _hub.getHubUrl();

    final raw = prefs.getString(_profilesKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _profiles = list.map((j) => _HubProfile.fromJson(j as Map<String, dynamic>)).toList();
    }

    // Si no hay perfiles, crear uno desde la URL activa
    if (_profiles.isEmpty) {
      final clean = _activeUrl.replaceFirst('ws://', '').replaceFirst('wss://', '').split('/').first;
      final parts = clean.split(':');
      _profiles = [
        _HubProfile(name: 'Docker WSL', ip: parts.isNotEmpty ? parts[0] : Uri.base.host, port: parts.length > 1 ? parts[1] : '3000'),
      ];
      await _saveProfiles();
    }

    _apiKeys = await _keysSvc.loadAll();
    setState(() => _loading = false);
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, jsonEncode(_profiles.map((p) => p.toJson()).toList()));
  }

  Future<void> _activate(_HubProfile profile) async {
    await _hub.saveHubUrl(profile.wsUrl);
    setState(() => _activeUrl = profile.wsUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Conectado a ${profile.name} (${profile.wsUrl})'),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _addProfile() => _showProfileDialog(null);

  void _editProfile(_HubProfile profile) => _showProfileDialog(profile);

  void _showProfileDialog(_HubProfile? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.ip ?? '');
    final portCtrl = TextEditingController(text: existing?.port ?? '3000');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(existing == null ? 'Agregar perfil' : 'Editar perfil',
              style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Mi amigo Juan', labelStyle: TextStyle(color: AppTheme.textSecondary)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: ipCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'IP del servidor', hintText: '192.168.1.50', labelStyle: TextStyle(color: AppTheme.textSecondary)),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: portCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Puerto', hintText: '3000', labelStyle: TextStyle(color: AppTheme.textSecondary)),
                keyboardType: TextInputType.number,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  setState(() => _profiles.remove(existing));
                  _saveProfiles();
                  Navigator.pop(ctx);
                },
                child: const Text('Eliminar', style: TextStyle(color: AppTheme.error)),
              ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: AppTheme.bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final ip = ipCtrl.text.trim();
                final port = portCtrl.text.trim();
                if (name.isEmpty || ip.isEmpty || port.isEmpty) return;
                setState(() {
                  if (existing != null) {
                    existing.name = name;
                    existing.ip = ip;
                    existing.port = port;
                  } else {
                    _profiles.add(_HubProfile(name: name, ip: ip, port: port));
                  }
                });
                _saveProfiles();
                Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Agregar' : 'Guardar'),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addProfile, tooltip: 'Agregar perfil'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('PERFILES DE CONEXIÓN', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                const Text('Cada perfil guarda la IP y puerto de un Hub. Toca uno para conectarte.', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 16),

                ..._profiles.map((p) {
                  final isActive = p.wsUrl == _activeUrl;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isActive ? const BorderSide(color: AppTheme.accent, width: 1.5) : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (isActive ? AppTheme.accent : AppTheme.textSecondary).withValues(alpha: 0.15),
                        ),
                        child: Icon(Icons.computer, color: isActive ? AppTheme.accent : AppTheme.textSecondary, size: 18),
                      ),
                      title: Text(p.name, style: TextStyle(color: isActive ? AppTheme.accent : AppTheme.textPrimary, fontWeight: isActive ? FontWeight.w700 : FontWeight.normal, fontSize: 14)),
                      subtitle: Text('${p.ip}:${p.port}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'monospace')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                            child: const Text('ACTIVO', style: TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        IconButton(icon: const Icon(Icons.edit_outlined, color: AppTheme.textSecondary, size: 18), onPressed: () => _editProfile(p)),
                      ]),
                      onTap: () => _activate(p),
                    ),
                  );
                }),

                // Botón agregar
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    foregroundColor: AppTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar perfil de conexión'),
                  onPressed: _addProfile,
                ),

                const SizedBox(height: 32),
                // ── API KEYS ──────────────────────────────────────
                _ApiKeysSection(
                  svc: _keysSvc,
                  keys: _apiKeys,
                  expanded: _keysExpanded,
                  onToggle: () => setState(() => _keysExpanded = !_keysExpanded),
                  onChanged: (id, val) async {
                    await _keysSvc.setKey(id, val);
                    setState(() {
                      if (val.isEmpty) _apiKeys.remove(id); else _apiKeys[id] = val;
                    });
                  },
                  onClearAll: () async {
                    await _keysSvc.clearAll();
                    setState(() => _apiKeys.clear());
                  },
                ),
                const SizedBox(height: 32),
                const Text('ACERCA DE', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Antigravity Mobile', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('v1.0.0 — Panel remoto para Antigravity AI', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      SizedBox(height: 4),
                      Text('Comparte la app con amigos y cada uno agrega su propio Hub.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// API Keys section widget
// ─────────────────────────────────────────────────────────────
class _ApiKeysSection extends StatefulWidget {
  final ApiKeysService svc;
  final Map<String, String> keys;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String id, String val) onChanged;
  final VoidCallback onClearAll;

  const _ApiKeysSection({
    required this.svc,
    required this.keys,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    required this.onClearAll,
  });

  @override
  State<_ApiKeysSection> createState() => _ApiKeysSectionState();
}

class _ApiKeysSectionState extends State<_ApiKeysSection> {
  late final Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final p in ApiKeysService.providers)
        p.id: TextEditingController(text: widget.keys[p.id] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header clickable
      GestureDetector(
        onTap: widget.onToggle,
        child: Row(children: [
          const Text('MIS API KEYS', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 1.5)),
          const Spacer(),
          Icon(widget.expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.textSecondary, size: 18),
        ]),
      ),
      const SizedBox(height: 4),
      const Text(
        'Tus propias claves anulan las del Hub. Nadie más podrá ver ni usar tus keys.',
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      if (widget.expanded) ...[
        const SizedBox(height: 14),
        ...ApiKeysService.providers.map((p) {
          final ctrl = _ctrls[p.id]!;
          final hasKey = (widget.keys[p.id] ?? '').isNotEmpty;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: hasKey ? const Color(0xFF22C55E) : AppTheme.border),
                ),
                const SizedBox(width: 8),
                Text(p.name, style: TextStyle(color: hasKey ? AppTheme.textPrimary : AppTheme.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                if (hasKey)
                  GestureDetector(
                    onTap: () { ctrl.clear(); widget.onChanged(p.id, ''); },
                    child: const Text('Quitar', style: TextStyle(color: AppTheme.error, fontSize: 11)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text(p.where, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: p.hint,
                  hintStyle: const TextStyle(color: AppTheme.border, fontFamily: 'monospace'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18, color: AppTheme.accent),
                    tooltip: 'Guardar',
                    onPressed: () { widget.onChanged(p.id, ctrl.text.trim()); FocusScope.of(context).unfocus(); },
                  ),
                ),
                onSubmitted: (v) => widget.onChanged(p.id, v.trim()),
              ),
            ]),
          );
        }),
        const SizedBox(height: 4),
        TextButton.icon(
          icon: const Icon(Icons.delete_sweep, size: 16, color: AppTheme.error),
          label: const Text('Borrar todas mis keys', style: TextStyle(color: AppTheme.error, fontSize: 12)),
          onPressed: () {
            for (final c in _ctrls.values) { c.clear(); }
            widget.onClearAll();
          },
        ),
      ],
    ]);
  }
}
