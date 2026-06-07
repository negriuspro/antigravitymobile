import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'hub_service.dart';

class ProviderMetrics {
  final String providerId;
  final String label;
  final String health; // "ok" | "not_configured"
  final List<dynamic> models;

  ProviderMetrics(
      {required this.providerId,
      required this.label,
      required this.health,
      required this.models});

  factory ProviderMetrics.fromJson(Map<String, dynamic> j) => ProviderMetrics(
        providerId: j['provider_id'] as String,
        label: j['label'] as String,
        health: j['health'] as String? ?? 'unknown',
        models: (j['models'] as List?) ?? [],
      );
}

/// Local Claude Code CLI usage stats, read by the hub from `~/.claude/projects/*.jsonl`.
class ClaudeCodeMetrics {
  final bool hasData;
  final Map<String, dynamic> session;
  final Map<String, dynamic> today;
  final List<int> sparkline;

  ClaudeCodeMetrics(
      {required this.hasData,
      required this.session,
      required this.today,
      required this.sparkline});

  factory ClaudeCodeMetrics.fromJson(Map<String, dynamic> j) =>
      ClaudeCodeMetrics(
        hasData: j['has_data'] as bool? ?? false,
        session: (j['session'] as Map?)?.cast<String, dynamic>() ?? {},
        today: (j['today'] as Map?)?.cast<String, dynamic>() ?? {},
        sparkline: ((j['sparkline'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );

  static ClaudeCodeMetrics empty() =>
      ClaudeCodeMetrics(hasData: false, session: {}, today: {}, sparkline: []);
}

/// Fetches provider health and model lists from the hub (`/providers/metrics`).
class ProviderMetricsService {
  Future<ClaudeCodeMetrics> fetchClaudeCodeMetrics() async {
    final wsUrl = await HubService.currentUrl();
    final baseUrl = wsUrl
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/providers/claude/metrics'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return ClaudeCodeMetrics.empty();
      return ClaudeCodeMetrics.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint(
          '[ProviderMetricsService.fetchClaudeCodeMetrics] error: $e\n$st');
      return ClaudeCodeMetrics.empty();
    }
  }

  Future<List<ProviderMetrics>> fetchAll() async {
    final wsUrl = await HubService.currentUrl();
    final baseUrl = wsUrl
        .replaceFirst('ws://', 'http://')
        .replaceFirst('wss://', 'https://');
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/providers/metrics'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [];
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => ProviderMetrics.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[ProviderMetricsService.fetchAll] error: $e\n$st');
      return [];
    }
  }
}
