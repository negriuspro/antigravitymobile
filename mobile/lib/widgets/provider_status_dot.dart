import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/hub_service.dart';
import '../services/token_service.dart';

enum ProviderStatus { checking, online, offline, quotaLow }

class ProviderStatusDot extends StatefulWidget {
  /// Provider ID: "groq", "gemini", "cerebras", "openrouter", "claude", "claude_code"
  final String providerId;
  final bool showLabel;

  const ProviderStatusDot({super.key, required this.providerId, this.showLabel = false});

  @override
  State<ProviderStatusDot> createState() => _ProviderStatusDotState();
}

class _ProviderStatusDotState extends State<ProviderStatusDot> {
  ProviderStatus _status = ProviderStatus.checking;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _check();
    // Re-check every 60 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _check());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _status = ProviderStatus.checking);

    final prefs = await SharedPreferences.getInstance();
    final wsUrl = prefs.getString('hub_url') ?? HubService.defaultHubUrl();
    final baseUrl = wsUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');

    try {
      final resp = await http.get(Uri.parse('$baseUrl/providers/status')).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200) {
        setState(() => _status = ProviderStatus.offline);
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final hasKey = data[widget.providerId] as bool? ?? false;

      if (!hasKey) {
        setState(() => _status = ProviderStatus.offline);
        return;
      }

      // Check quota
      final quota = kQuotas.where((q) => q.id == widget.providerId).firstOrNull;
      if (quota != null && (quota.dailyRequests > 0 || quota.dailyTokens > 0)) {
        final svc = TokenService();
        final usage = await svc.getUsage(widget.providerId);
        final reqPct = quota.dailyRequests > 0 ? usage.requestsToday / quota.dailyRequests : 0.0;
        final tokPct = quota.dailyTokens > 0 ? usage.tokensToday / quota.dailyTokens : 0.0;
        if (reqPct >= 1.0 || tokPct >= 1.0) {
          setState(() => _status = ProviderStatus.quotaLow);
          return;
        }
        if (reqPct > 0.85 || tokPct > 0.85) {
          setState(() => _status = ProviderStatus.quotaLow);
          return;
        }
      }

      setState(() => _status = ProviderStatus.online);
    } catch (_) {
      setState(() => _status = ProviderStatus.offline);
    }
  }

  Color get _color {
    switch (_status) {
      case ProviderStatus.checking: return Colors.grey;
      case ProviderStatus.online: return const Color(0xFF22C55E);
      case ProviderStatus.offline: return const Color(0xFFEF4444);
      case ProviderStatus.quotaLow: return const Color(0xFFF59E0B);
    }
  }

  String get _label {
    switch (_status) {
      case ProviderStatus.checking: return 'Verificando...';
      case ProviderStatus.online: return 'Activo';
      case ProviderStatus.offline: return 'Sin conexión';
      case ProviderStatus.quotaLow: return 'Cuota baja';
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = GestureDetector(
      onTap: _check,
      child: Tooltip(
        message: _label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color,
            boxShadow: _status == ProviderStatus.online
                ? [BoxShadow(color: _color.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
                : null,
          ),
        ),
      ),
    );

    if (!widget.showLabel) return dot;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      dot,
      const SizedBox(width: 5),
      Text(_label, style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w600)),
    ]);
  }
}
