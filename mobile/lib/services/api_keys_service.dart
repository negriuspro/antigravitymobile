import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user-provided API keys locally on the device.
/// These override the Hub's .env keys when set.
class ApiKeysService {
  static const _key = 'user_api_keys_v1';

  static const providers = [
    _ProviderDef('groq', 'Groq', 'gsk_...', 'console.groq.com → API Keys'),
    _ProviderDef('cerebras', 'Cerebras', 'csk_...', 'cloud.cerebras.ai → API Keys'),
    _ProviderDef('gemini', 'Gemini', 'AIza...', 'aistudio.google.com → Get API Key'),
    _ProviderDef('openrouter', 'OpenRouter', 'sk-or-v1-...', 'openrouter.ai → Keys'),
  ];

  Future<Map<String, String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as String));
  }

  Future<void> save(Map<String, String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(keys));
  }

  Future<void> setKey(String providerId, String apiKey) async {
    final all = await loadAll();
    if (apiKey.isEmpty) {
      all.remove(providerId);
    } else {
      all[providerId] = apiKey.trim();
    }
    await save(all);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class _ProviderDef {
  final String id;
  final String name;
  final String hint;
  final String where;
  const _ProviderDef(this.id, this.name, this.hint, this.where);
}
