import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../theme/app_theme.dart';
import '../services/session_service.dart';
import '../services/api_keys_service.dart';
import '../services/token_service.dart';
import '../services/hub_service.dart';
import '../utils/date_format.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_toolbar.dart';
import '../widgets/provider_status_dot.dart';

class ChatClaudeScreen extends StatefulWidget {
  const ChatClaudeScreen({super.key});

  @override
  State<ChatClaudeScreen> createState() => _ChatClaudeScreenState();
}

class _ChatClaudeScreenState extends State<ChatClaudeScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _sessions = SessionService();

  final _keysSvc = ApiKeysService();
  final _tokenSvc = TokenService();
  WebSocketChannel? _ws;
  bool _running = false;
  String _hubWs = HubService.defaultHubUrl();
  String _model = 'claude-sonnet-4-6';
  ChatSession? _currentSession;
  String? _pendingImageB64;
  String? _pendingImageMime;

  static const _color = Color(0xFFCC785C);

  static const _models = [
    ('claude-sonnet-4-6', 'Sonnet 4.6', 'Smart'),
    ('claude-opus-4-7', 'Opus 4.7', 'Max'),
    ('claude-haiku-4-5-20251001', 'Haiku 4.5', 'Fast'),
  ];

  List<ChatMessage> get _messages => _currentSession?.messages ?? [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await HubService.currentUrl();
    setState(() => _hubWs = url);
    _startNewSession();
  }

  void _startNewSession() {
    final session = _sessions.createNew('claude');
    setState(() => _currentSession = session);
    _connect();
  }

  void _connect() {
    _ws?.sink.close();
    _ws = WebSocketChannel.connect(Uri.parse('$_hubWs/ws/chat'));
    _ws!.stream.listen(
      _onData,
      onDone: () => setState(() => _running = false),
      onError: (_) => setState(() => _running = false),
    );
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final type = j['type'] as String? ?? '';
      if (type == 'start') {
        setState(() => _messages.add(ChatMessage(content: '', isAssistant: true)));
      } else if (type == 'chunk') {
        setState(() => _messages.last.content += j['text'] as String? ?? '');
        _scrollDown();
      } else if (type == 'end') {
        setState(() => _running = false);
        _saveSession();
      }
    } catch (e, st) {
      debugPrint('[ChatClaudeScreen._onData] JSON parse error: $e\n$st');
    }
  }

  Future<void> _saveSession() async {
    if (_currentSession == null) return;
    await _sessions.saveWithAutoTitle(_currentSession!, _messages);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _pendingImageB64 == null) || _running) return;
    final displayText = text.isNotEmpty ? text : '[Imagen adjunta]';
    setState(() {
      _messages.add(ChatMessage(content: displayText, isAssistant: false, imageB64: _pendingImageB64));
      _running = true;
      _controller.clear();
    });
    _scrollDown();
    final history = _messages.where((m) => m.content.isNotEmpty).map((m) => {'role': m.isAssistant ? 'assistant' : 'user', 'content': m.content}).toList();
    final userKeys = await _keysSvc.loadAll();
    final payload = <String, dynamic>{
      'provider': 'claude',
      'messages': history,
      'model': _model,
      if (userKeys.isNotEmpty) 'api_keys': userKeys,
    };
    if (_pendingImageB64 != null) { payload['image'] = _pendingImageB64; payload['image_mime'] = _pendingImageMime ?? 'image/jpeg'; }
    _ws?.sink.add(jsonEncode(payload));
    _tokenSvc.recordRequest('claude');
    setState(() { _pendingImageB64 = null; _pendingImageMime = null; });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _ws?.sink.close();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentSession?.title == 'Nueva sesión' ? 'Claude' : (_currentSession?.title ?? 'Claude'), overflow: TextOverflow.ellipsis),
        actions: [
          GestureDetector(
            onTap: _showModelPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_models.firstWhere((m) => m.$1 == _model, orElse: () => _models.first).$2, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary, size: 16),
              ]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: ProviderStatusDot(providerId: 'claude', showLabel: false),
          ),
          IconButton(icon: const Icon(Icons.history), onPressed: _showHistory, tooltip: 'Historial'),
          IconButton(icon: const Icon(Icons.add), onPressed: _startNewSession, tooltip: 'Nueva sesión'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.auto_awesome, color: _color, size: 48),
                    SizedBox(height: 12),
                    Text('Claude', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('Escribe un mensaje para empezar', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => ChatBubble(msg: _messages[i], accentColor: _color),
                  ),
          ),
          ChatToolbar(
            accentColor: _color,
            controller: _controller,
            running: _running,
            onSend: _send,
            onImageSelected: (b64, mime) => setState(() { _pendingImageB64 = b64; _pendingImageMime = mime; }),
            pendingImageB64: _pendingImageB64,
            onClearImage: () => setState(() { _pendingImageB64 = null; _pendingImageMime = null; }),
          ),
        ],
      ),
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Modelo Claude', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          ..._models.map((m) => ListTile(
            title: Text(m.$2, style: TextStyle(color: m.$1 == _model ? _color : AppTheme.textPrimary)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text(m.$3, style: const TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w600))),
              if (m.$1 == _model) ...[const SizedBox(width: 8), const Icon(Icons.check, color: _color, size: 18)],
            ]),
            onTap: () { setState(() => _model = m.$1); Navigator.pop(context); },
          )),
        ]),
      ),
    );
  }

  void _showHistory() async {
    final all = await _sessions.loadAll();
    final filtered = all.where((s) => s.agentId == 'claude').toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => DraggableScrollableSheet(
          initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3, expand: false,
          builder: (_, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Text('Historial — Claude', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                TextButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Nueva'), onPressed: () { Navigator.pop(ctx); _startNewSession(); }),
              ]),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No hay sesiones', style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      controller: sc, itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final active = s.id == _currentSession?.id;
                        return ListTile(
                          leading: Icon(active ? Icons.chat_bubble : Icons.chat_bubble_outline, color: active ? _color : AppTheme.textSecondary, size: 20),
                          title: Text(s.title, style: TextStyle(color: active ? _color : AppTheme.textPrimary, fontSize: 13)),
                          subtitle: Text('${s.messages.length} msgs · ${formatRelativeDate(s.createdAt)}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary, size: 18),
                            onPressed: () async {
                              await _sessions.delete(s.id);
                              final updated = (await _sessions.loadAll()).where((x) => x.agentId == 'claude').toList();
                              setM(() { filtered.clear(); filtered.addAll(updated); });
                              final wasActive = s.id == _currentSession?.id;
                              if (ctx.mounted && wasActive) { Navigator.pop(ctx); _startNewSession(); }
                            },
                          ),
                          onTap: () { Navigator.pop(ctx); _ws?.sink.close(); setState(() => _currentSession = s); _connect(); _scrollDown(); },
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

}

// _Bubble reemplazado por ChatBubble (widgets/chat_bubble.dart)
