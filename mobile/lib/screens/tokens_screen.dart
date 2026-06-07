import 'dart:async';
import 'package:flutter/material.dart';
import '../services/token_service.dart';
import '../services/provider_metrics_service.dart';
import '../theme/app_theme.dart';

class TokensScreen extends StatefulWidget {
  const TokensScreen({super.key});

  @override
  State<TokensScreen> createState() => _TokensScreenState();
}

class _TokensScreenState extends State<TokensScreen> {
  final _tokenSvc = TokenService();
  final _metricsSvc = ProviderMetricsService();

  Map<String, TokenUsage> _usage = {};
  Map<String, ProviderMetrics> _metrics = {};
  ClaudeCodeMetrics _claudeCode = ClaudeCodeMetrics.empty();
  bool _loading = true;
  Timer? _clock;
  Timer? _poll;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _now = DateTime.now().toUtc()));
    _poll =
        Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final results = await Future.wait([
      _tokenSvc.loadAll(),
      _metricsSvc.fetchAll(),
      _metricsSvc.fetchClaudeCodeMetrics(),
    ]);
    if (!mounted) return;
    setState(() {
      _usage = results[0] as Map<String, TokenUsage>;
      _metrics = {
        for (final m in results[1] as List<ProviderMetrics>) m.providerId: m
      };
      _claudeCode = results[2] as ClaudeCodeMetrics;
      _loading = false;
    });
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
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summary(),
                      const SizedBox(height: 12),
                      _resetBanner(),
                      const SizedBox(height: 12),
                      _ProvidersGrid(
                        quotas: kQuotas,
                        usage: _usage,
                        metrics: _metrics,
                        claudeCode: _claudeCode,
                      ),
                    ]),
              ),
            ),
    );
  }

  Widget _summary() {
    final online = kQuotas.where((q) => _metrics[q.id]?.health == 'ok').length;
    final withUsage = kQuotas
        .where((q) =>
            (_usage[q.id]?.tokensToday ?? 0) > 0 ||
            (_usage[q.id]?.requestsToday ?? 0) > 0)
        .length;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _SummaryChip(
          label: 'PROVEEDORES',
          value: '${kQuotas.length}',
          color: AppTheme.accent),
      _SummaryChip(label: 'ACTIVOS', value: '$online', color: AppTheme.success),
      _SummaryChip(
          label: 'CON USO HOY',
          value: '$withUsage',
          color: const Color(0xFFF59E0B)),
    ]);
  }

  Widget _resetBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border, width: 0.5)),
      child: Row(children: [
        const Icon(Icons.timer_outlined,
            color: AppTheme.textSecondary, size: 16),
        const SizedBox(width: 8),
        const Text('Reset diario (00:00 UTC) en: ',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        Text(_countdown(),
            style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace')),
      ]),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 9,
                letterSpacing: 1.0,
                fontFamily: 'monospace')),
      ]),
    );
  }
}

// ─── Providers Grid ──────────────────────────────────────────────────────────

class _ProvidersGrid extends StatelessWidget {
  final List<ProviderQuota> quotas;
  final Map<String, TokenUsage> usage;
  final Map<String, ProviderMetrics> metrics;
  final ClaudeCodeMetrics claudeCode;

  const _ProvidersGrid(
      {required this.quotas,
      required this.usage,
      required this.metrics,
      required this.claudeCode});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const minCardWidth = 360.0;
      const spacing = 12.0;
      final columns =
          (constraints.maxWidth / (minCardWidth + spacing)).floor().clamp(1, 3);
      final cardWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: quotas.map((q) {
          return SizedBox(
            width: cardWidth,
            child: _ProviderCard(
                quota: q,
                usage: usage[q.id],
                metrics: metrics[q.id],
                claudeCode: claudeCode),
          );
        }).toList(),
      );
    });
  }
}

/// Tarjeta estilo "mini dashboard" -- inspirada en AgentsView de AngelCtrl:
/// logo/insignia, badge ONLINE/OFFLINE, cifra grande destacada y grilla 2x2
/// de métricas, combinando datos reales del hub (salud, modelos) con el
/// consumo local rastreado por TokenService.
class _ProviderCard extends StatelessWidget {
  final ProviderQuota quota;
  final TokenUsage? usage;
  final ProviderMetrics? metrics;
  final ClaudeCodeMetrics claudeCode;

  const _ProviderCard(
      {required this.quota,
      required this.usage,
      required this.metrics,
      required this.claudeCode});

  static (IconData, Color) _visual(String providerId, String fallbackHex) {
    final color = Color(int.parse(fallbackHex.replaceFirst('#', '0xFF')));
    final icon = switch (providerId) {
      'groq' => Icons.bolt_rounded,
      'cerebras' => Icons.memory_rounded,
      'gemini' => Icons.auto_awesome_rounded,
      'openrouter' => Icons.hub_rounded,
      'claude_code' => Icons.terminal_rounded,
      'sambanova' => Icons.cloud_rounded,
      _ => Icons.smart_toy_rounded,
    };
    return (icon, color);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = _visual(quota.id, quota.color);
    final health = metrics?.health ?? 'unknown';
    final configured = health == 'ok';
    final (statusColor, statusLabel) = switch (health) {
      'ok' => (AppTheme.success, 'ONLINE'),
      'not_configured' => (AppTheme.textSecondary, 'OFFLINE'),
      _ => (const Color(0xFFF59E0B), 'DESCONOCIDO'),
    };

    final reqUsed = usage?.requestsToday ?? 0;
    final tokUsed = usage?.tokensToday ?? 0;
    final reqMax = quota.dailyRequests;
    final tokMax = quota.dailyTokens;
    final tokPct = tokMax > 0 ? (tokUsed / tokMax).clamp(0.0, 1.0) : 0.0;
    final reqPct = reqMax > 0 ? (reqUsed / reqMax).clamp(0.0, 1.0) : 0.0;
    final isNearLimit = reqPct > 0.85 || tokPct > 0.85;

    // Para Claude Code usamos los datos reales leídos por el hub desde
    // ~/.claude/projects/*.jsonl; los demás proveedores no exponen un
    // desglose input/output, así que se muestran como "—".
    final isClaudeCode = quota.id == 'claude_code';
    final ccToday = claudeCode.today;
    final inputLabel =
        isClaudeCode ? _fmt((ccToday['input'] as num? ?? 0).toInt()) : '—';
    final outputLabel =
        isClaudeCode ? _fmt((ccToday['output'] as num? ?? 0).toInt()) : '—';
    final tokHoyLabel = isClaudeCode
        ? _fmt((ccToday['total'] as num? ?? 0).toInt())
        : _fmt(tokUsed);
    final quotaPctLabel = tokMax > 0
        ? '${(tokPct * 100).toStringAsFixed(0)}%'
        : (reqMax > 0 ? '${(reqPct * 100).toStringAsFixed(0)}%' : '—');

    final models = metrics?.models ?? const [];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNearLimit
              ? Colors.red.withValues(alpha: 0.4)
              : accent.withValues(alpha: 0.18),
          width: isNearLimit ? 1.0 : 0.5,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            _logo(icon, accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                quota.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _badge(statusLabel, statusColor),
          ]),
        ),

        const Divider(color: AppTheme.border, height: 1, thickness: 0.5),

        if (!configured)
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quota.specialty,
                  style: TextStyle(
                      color: accent.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 8),
              const Text('API key no configurada',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace')),
              const SizedBox(height: 4),
              const Text(
                  'Agrega la key en el hub (.env) o desde Ajustes y reinicia.',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      fontFamily: 'monospace')),
            ]),
          )
        else ...[
          // ── Cifra destacada: tokens consumidos hoy ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TOKENS HOY',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                      fontFamily: 'monospace',
                      letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(_fmt(tokUsed),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(quota.specialty,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontFamily: 'monospace'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),

          const SizedBox(height: 12),

          // ── Grilla 2x2: input / output / tokens hoy / uso de cuota diaria ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(children: [
              Row(children: [
                Expanded(child: _metricTile('INPUT', inputLabel, accent)),
                const SizedBox(width: 8),
                Expanded(child: _metricTile('OUTPUT', outputLabel, accent)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: _metricTile(
                    'TOKENS HOY',
                    tokHoyLabel,
                    isNearLimit ? Colors.red : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metricTile(
                    'USO CUOTA DIARIA',
                    quotaPctLabel,
                    isNearLimit ? Colors.red : const Color(0xFF8C6EF5),
                  ),
                ),
              ]),
            ]),
          ),

          // ── Acceso a la lista de modelos disponibles ──
          if (models.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      _showModelsSheet(context, quota.name, models, accent),
                  style: TextButton.styleFrom(
                    foregroundColor: accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                          color: accent.withValues(alpha: 0.3), width: 0.5),
                    ),
                  ),
                  icon: const Icon(Icons.view_list_rounded, size: 14),
                  label: Text('VER MODELOS · ${models.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                ),
              ),
            ),
          ],

          if (tokMax > 0) ...[
            const SizedBox(height: 12),
            Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: _Bar(pct: tokPct, color: accent)),
          ],

          const SizedBox(height: 14),
        ],
      ]),
    );
  }

  Widget _logo(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Icon(icon, color: color, size: 15),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                letterSpacing: 0.5)),
      );

  Widget _metricTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 16,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 8,
                fontFamily: 'monospace',
                letterSpacing: 0.8)),
      ]),
    );
  }

  void _showModelsSheet(
      BuildContext context, String label, List<dynamic> models, Color accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Expanded(
                child: Text('$label  ·  ${models.length} modelos',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          const Divider(color: AppTheme.border, height: 1, thickness: 0.5),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: models.length,
              separatorBuilder: (_, __) => const Divider(
                  color: AppTheme.border, height: 1, thickness: 0.5),
              itemBuilder: (_, i) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(Icons.psychology_alt_rounded, size: 14, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_modelLabel(models[i]),
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _modelLabel(dynamic model) {
    if (model is Map) {
      final label = model['label'] ?? model['name'] ?? model['id'];
      return label?.toString() ?? '—';
    }
    return model.toString();
  }
}

class _Bar extends StatelessWidget {
  final double pct;
  final Color color;
  const _Bar({required this.pct, required this.color});

  @override
  Widget build(BuildContext context) {
    final barColor = pct > 0.85
        ? Colors.red
        : pct > 0.6
            ? Colors.orange
            : color;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Uso de cuota diaria',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const Spacer(),
        Text('${(pct * 100).toStringAsFixed(1)}%',
            style: TextStyle(
                color: barColor, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppTheme.border,
            valueColor: AlwaysStoppedAnimation(barColor),
            minHeight: 6),
      ),
    ]);
  }
}
