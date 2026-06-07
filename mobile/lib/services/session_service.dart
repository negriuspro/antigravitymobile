import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessage {
  String content;
  final bool isAssistant;
  final String? imageB64;
  ChatMessage({required this.content, required this.isAssistant, this.imageB64});

  Map<String, dynamic> toJson() => {'content': content, 'isAssistant': isAssistant, if (imageB64 != null) 'imageB64': imageB64};
  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(content: j['content'] as String, isAssistant: j['isAssistant'] as bool, imageB64: j['imageB64'] as String?);
}

class ChatSession {
  final String id;
  String title;
  final String agentId;
  final DateTime createdAt;
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.agentId,
    required this.createdAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'agentId': agentId,
    'createdAt': createdAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
    id: j['id'] as String,
    title: j['title'] as String,
    agentId: j['agentId'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    messages: (j['messages'] as List).map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList(),
  );
}

class SessionService {
  static const _key = 'chat_sessions_v2';

  Future<List<ChatSession>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((j) => ChatSession.fromJson(j as Map<String, dynamic>)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Guarda la sesión generando título automático desde el primer mensaje del usuario.
  /// Consolida el patrón _saveSession duplicado en los 3 screens de chat.
  Future<void> saveWithAutoTitle(
    ChatSession session,
    List<ChatMessage> messages,
  ) async {
    if (messages.isEmpty) return;
    if (session.title == 'Nueva sesión') {
      final first = messages.firstWhere(
        (m) => !m.isAssistant,
        orElse: () => messages.first,
      );
      session.title = first.content.length > 40
          ? '${first.content.substring(0, 40)}...'
          : first.content;
    }
    await save(session);
  }

  Future<void> save(ChatSession session) async {
    final all = await loadAll();
    final idx = all.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      all[idx] = session;
    } else {
      all.insert(0, session);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((s) => s.toJson()).toList()));
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((s) => s.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all.map((s) => s.toJson()).toList()));
  }

  ChatSession createNew(String agentId) {
    return ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Nueva sesión',
      agentId: agentId,
      createdAt: DateTime.now(),
      messages: [],
    );
  }
}
