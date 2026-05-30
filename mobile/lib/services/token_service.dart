import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProviderQuota {
  final String id;
  final String name;
  final int dailyRequests;    // max peticiones/día (0 = desconocido)
  final int dailyTokens;      // max tokens/día (0 = desconocido)
  final int minuteTokens;     // max tokens/minuto (0 = desconocido)
  final String resetTime;     // hora UTC de reset
  final String color;         // hex
  final String specialty;     // para qué es mejor esta IA
  final String resetCycle;    // "diario", "mensual", "por crédito"

  const ProviderQuota({
    required this.id,
    required this.name,
    required this.dailyRequests,
    required this.dailyTokens,
    required this.minuteTokens,
    required this.resetTime,
    required this.color,
    required this.specialty,
    this.resetCycle = 'diario',
  });
}

// Límites del tier gratuito + especialidad de cada proveedor
const kQuotas = [
  ProviderQuota(
    id: 'groq',
    name: 'Groq',
    dailyRequests: 14400,
    dailyTokens: 500000,
    minuteTokens: 6000,
    resetTime: '00:00 UTC',
    color: '#F55036',
    specialty: 'Respuestas ultrarrápidas — prototipos, chat en tiempo real, testing veloz',
    resetCycle: 'diario',
  ),
  ProviderQuota(
    id: 'cerebras',
    name: 'Cerebras',
    dailyRequests: 0,
    dailyTokens: 0,
    minuteTokens: 0,
    resetTime: '00:00 UTC',
    color: '#7D3C98',
    specialty: 'Velocidad extrema con modelos grandes — GPT-OSS 120B a velocidad increíble',
    resetCycle: 'diario',
  ),
  ProviderQuota(
    id: 'gemini',
    name: 'Gemini',
    dailyRequests: 1500,
    dailyTokens: 1000000,
    minuteTokens: 4000,
    resetTime: '00:00 UTC',
    color: '#4285F4',
    specialty: 'Imágenes y contexto largo — análisis visual, documentos de 1M tokens, multimodal',
    resetCycle: 'diario',
  ),
  ProviderQuota(
    id: 'openrouter',
    name: 'OpenRouter',
    dailyRequests: 200,
    dailyTokens: 0,
    minuteTokens: 0,
    resetTime: '00:00 UTC',
    color: '#10B981',
    specialty: 'Acceso a 300+ modelos — elige el mejor para cada tarea, incluye modelos gratuitos',
    resetCycle: 'diario',
  ),
  ProviderQuota(
    id: 'claude_code',
    name: 'Claude Code',
    dailyRequests: 0,
    dailyTokens: 0,
    minuteTokens: 0,
    resetTime: 'mensual',
    color: '#CC785C',
    specialty: 'Código complejo — debugging, arquitectura, refactoring, lectura de archivos del proyecto',
    resetCycle: 'mensual',
  ),
  ProviderQuota(
    id: 'claude',
    name: 'Claude Chat',
    dailyRequests: 0,
    dailyTokens: 0,
    minuteTokens: 0,
    resetTime: 'mensual',
    color: '#D97706',
    specialty: 'Redacción y análisis — documentos, explicaciones detalladas, razonamiento complejo',
    resetCycle: 'mensual',
  ),
];

class TokenUsage {
  final String providerId;
  final int requestsToday;
  final int tokensToday;
  final DateTime lastReset;

  TokenUsage({
    required this.providerId,
    required this.requestsToday,
    required this.tokensToday,
    required this.lastReset,
  });

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'requestsToday': requestsToday,
    'tokensToday': tokensToday,
    'lastReset': lastReset.toIso8601String(),
  };

  factory TokenUsage.fromJson(Map<String, dynamic> j) => TokenUsage(
    providerId: j['providerId'] as String,
    requestsToday: j['requestsToday'] as int,
    tokensToday: j['tokensToday'] as int,
    lastReset: DateTime.parse(j['lastReset'] as String),
  );

  TokenUsage copyWith({int? requestsToday, int? tokensToday, DateTime? lastReset}) => TokenUsage(
    providerId: providerId,
    requestsToday: requestsToday ?? this.requestsToday,
    tokensToday: tokensToday ?? this.tokensToday,
    lastReset: lastReset ?? this.lastReset,
  );
}

class TokenService {
  static const _key = 'token_usage_v1';

  Future<Map<String, TokenUsage>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, TokenUsage.fromJson(v as Map<String, dynamic>)));
  }

  Future<void> recordRequest(String providerId, {int tokens = 0}) async {
    final all = await loadAll();
    final now = DateTime.now().toUtc();
    var usage = all[providerId] ?? TokenUsage(providerId: providerId, requestsToday: 0, tokensToday: 0, lastReset: now);

    // Reset si cambió el día UTC
    if (now.day != usage.lastReset.day || now.difference(usage.lastReset).inHours >= 24) {
      usage = TokenUsage(providerId: providerId, requestsToday: 0, tokensToday: 0, lastReset: now);
    }

    usage = usage.copyWith(requestsToday: usage.requestsToday + 1, tokensToday: usage.tokensToday + tokens);
    all[providerId] = usage;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<TokenUsage> getUsage(String providerId) async {
    final all = await loadAll();
    return all[providerId] ?? TokenUsage(providerId: providerId, requestsToday: 0, tokensToday: 0, lastReset: DateTime.now().toUtc());
  }
}
