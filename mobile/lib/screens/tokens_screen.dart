import 'dart:async';
import 'package:flutter/material.dart';
import '../services/token_service.dart';
import '../theme/app_theme.dart';

class TokensScreen extends StatefulWidget {
  const TokensScreen({super.key});

  @override
  State<TokensScreen> createState() => _TokensScreenState();
}

class _TokensScreenState extends State<TokensScreen> {
  final _svc = TokenService();
  Map<String, TokenUsage> _usage = {};
  bool _loading = true;
  Timer? _timer;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now().toUtc());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _usage = await _svc.loadAll();
    setState(() => _loading = false);
  }

  String _countdown() {
    final tomorrow = DateTime.utc(_now.year, _now.month, _now.day + 1);
    final diff = tomorrow.difference(_now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tokens y Cuotas'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Banner reset diario
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: AppTheme.surface,
                  child: Row(children: [
                    const Icon(Icons.timer_outlined, color: AppTheme.textSecondary, size: 16),
                    const SizedBox(width: 8),
                    const Text('Reset diario (00:00 UTC) en: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text(_countdown(), style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  ]),
                ),
                const Divider(height: 1, color: AppTheme.border),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: kQuotas.length,
                    itemBuilder: (_, i) => _ProviderCard(quota: kQuotas[i], usage: _usage[kQuotas[i].id], countdown: _countdown()),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final ProviderQuota quota;
  final TokenUsage? usage;
  final String countdown;

  const _ProviderCard({required this.quota, required this.usage, required this.countdown});

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(quota.color.replaceFirst('#', '0xFF')));
    final reqUsed = usage?.requestsToday ?? 0;
    final tokUsed = usage?.tokensToday ?? 0;
    final reqMax = quota.dailyRequests;
    final tokMax = quota.dailyTokens;
    final reqLeft = reqMax > 0 ? (reqMax - reqUsed).clamp(0, reqMax) : null;
    final tokLeft = tokMax > 0 ? (tokMax - tokUsed).clamp(0, tokMax) : null;
    final reqPct = reqMax > 0 ? (reqUsed / reqMax).clamp(0.0, 1.0) : 0.0;
    final tokPct = tokMax > 0 ? (tokUsed / tokMax).clamp(0.0, 1.0) : 0.0;
    final isNearLimit = reqPct > 0.85 || tokPct > 0.85;
    final sinUso = reqUsed == 0 && tokUsed == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isNearLimit ? BorderSide(color: Colors.red.withValues(alpha: 0.5), width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header: nombre + badge
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 8),
            Text(quota.name, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(width: 8),
            if (isNearLimit)
              _badge('⚠ LÍMITE CERCANO', Colors.red),
            if (sinUso && !isNearLimit)
              _badge('Sin uso hoy', AppTheme.textSecondary),
            const Spacer(),
            if (quota.resetCycle == 'mensual')
              Text('cuota mensual', style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 10))
            else
              Row(children: [
                const Icon(Icons.timer_outlined, size: 12, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(countdown, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'monospace')),
              ]),
          ]),

          // Especialidad
          const SizedBox(height: 6),
          Text(quota.specialty, style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 11, fontStyle: FontStyle.italic)),

          const SizedBox(height: 12),
          const Divider(color: AppTheme.border, height: 1),
          const SizedBox(height: 12),

          // Tokens: gastado / disponible / total
          if (tokMax > 0 || tokUsed > 0) ...[
            _StatRow(
              label: 'Tokens gastados',
              value: _fmt(tokUsed),
              valueColor: tokPct > 0.85 ? Colors.red : color,
            ),
            const SizedBox(height: 4),
            if (tokLeft != null)
              _StatRow(label: 'Tokens disponibles', value: _fmt(tokLeft), valueColor: tokLeft < tokMax * 0.15 ? Colors.red : AppTheme.textPrimary),
            if (tokMax > 0)
              _StatRow(label: 'Cuota diaria total', value: _fmt(tokMax), valueColor: AppTheme.textSecondary),
            const SizedBox(height: 8),
            _Bar(label: 'Tokens', pct: tokPct, color: color),
            const SizedBox(height: 12),
          ],
          if (tokMax == 0 && tokUsed == 0 && quota.dailyRequests == 0) ...[
            Row(children: [
              Icon(Icons.help_outline, size: 14, color: color.withValues(alpha: 0.5)),
              const SizedBox(width: 6),
              const Text('Límites no publicados por este proveedor', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 12),
          ],

          // Peticiones: gastado / disponible / total
          if (reqMax > 0 || reqUsed > 0) ...[
            _StatRow(
              label: 'Peticiones enviadas',
              value: reqUsed.toString(),
              valueColor: reqPct > 0.85 ? Colors.red : color,
            ),
            const SizedBox(height: 4),
            if (reqLeft != null)
              _StatRow(label: 'Peticiones restantes', value: reqLeft.toString(), valueColor: reqLeft < reqMax * 0.15 ? Colors.red : AppTheme.textPrimary),
            if (reqMax > 0)
              _StatRow(label: 'Máximo diario', value: '${_fmt(reqMax)} peticiones', valueColor: AppTheme.textSecondary),
            const SizedBox(height: 8),
            _Bar(label: 'Peticiones', pct: reqPct, color: color),
            const SizedBox(height: 12),
          ],

          // Chips de info
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (quota.minuteTokens > 0)
              _Chip('${_fmt(quota.minuteTokens)} tok/min', Icons.speed, color),
            if (reqMax > 0)
              _Chip('${_fmt(reqMax)} req/día', Icons.repeat, color),
            if (tokMax > 0)
              _Chip('${_fmt(tokMax)} tok/día', Icons.token, color),
          ]),

          if (!sinUso) ...[
            const SizedBox(height: 8),
            const Text(
              'Los contadores locales se sincronizan con el reset de las 00:00 UTC.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: Text(text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _StatRow({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      const Spacer(),
      Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double pct;
  final Color color;
  const _Bar({required this.label, required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    final barColor = pct > 0.85 ? Colors.red : pct > 0.6 ? Colors.orange : color;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const Spacer(),
        Text('${(pct * 100).toStringAsFixed(1)}%', style: TextStyle(color: barColor, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct, backgroundColor: AppTheme.border, valueColor: AlwaysStoppedAnimation(barColor), minHeight: 6),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _Chip(this.text, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
