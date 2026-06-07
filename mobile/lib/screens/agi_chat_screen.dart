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

class _ModelOption {
  final String id;
  final String name;
  final String badge;
  final int budget;
  const _ModelOption(this.id, this.name, this.badge, this.budget);
  String get key => '$id::$budget';
}

class _Provider {
  final String id;
  final String name;
  final Color color;
  final List<_ModelOption> models;
  const _Provider(this.id, this.name, this.color, this.models);
}

const _providers = [
  _Provider('gemini', 'Gemini', Color(0xFF4285F4), [
    _ModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Low', 1024),
    _ModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Medium', 8192),
    _ModelOption('gemini-2.5-flash', 'Gemini 2.5 Flash', 'High', 24576),
    _ModelOption('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Low', 1024),
    _ModelOption('gemini-2.5-pro', 'Gemini 2.5 Pro', 'High', 24576),
  ]),
  _Provider('claude', 'Claude', Color(0xFFD97706), [
    _ModelOption('claude-sonnet-4-6', 'Claude Sonnet 4.6', 'Thinking', 0),
    _ModelOption('claude-opus-4-8', 'Claude Opus 4.8', 'Thinking', 0),
  ]),
  _Provider('cerebras', 'Cerebras', Color(0xFF7D3C98), [
    _ModelOption('gpt-oss-120b', 'GPT-OSS 120B', 'Medium', 0),
  ]),
  _Provider('openrouter', 'OpenRouter', Color(0xFF10B981), [
    _ModelOption(
        'deepseek/deepseek-v4-flash:free', 'DeepSeek V4 Flash', 'Reasoning', 0),
    _ModelOption('qwen/qwen3-coder:free', 'Qwen3 Coder', 'Free', 0),
    _ModelOption('google/gemma-4-31b:free', 'Gemma 4 31B', 'Free', 0),
    _ModelOption('openai/gpt-oss-120b:free', 'GPT-OSS 120B', 'Free', 0),
  ]),
];

class AgiChatScreen extends StatefulWidget {
  const AgiChatScreen({super.key});

  @override
  State<AgiChatScreen> createState() => _AgiChatScreenState();
}

class _AgiChatScreenState extends State<AgiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _sessions = SessionService();

  final _keysSvc = ApiKeysService();
  final _tokenSvc = TokenService();
  WebSocketChannel? _ws;
  bool _running = false;
  String _hubWs = HubService.defaultHubUrl();
  String _providerId = 'gemini';
  _ModelOption _selectedModel = _providers.first.models.first;
  ChatSession? _currentSession;
  String? _pendingImageB64;
  String? _pendingImageMime;

  _Provider get _provider => _providers.firstWhere((p) => p.id == _providerId);
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
    final session = _sessions.createNew('agi_$_providerId');
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
        setState(
            () => _messages.add(ChatMessage(content: '', isAssistant: true)));
      } else if (type == 'chunk') {
        setState(() => _messages.last.content += j['text'] as String? ?? '');
        _scrollDown();
      } else if (type == 'end') {
        setState(() => _running = false);
        _saveSession();
      }
    } catch (e, st) {
      debugPrint('[AgiChatScreen._onData] JSON parse error: $e\n$st');
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
      _messages.add(ChatMessage(
          content: displayText,
          isAssistant: false,
          imageB64: _pendingImageB64));
      _running = true;
      _controller.clear();
    });
    _scrollDown();

    final history = _messages
        .where((m) => m.content.isNotEmpty)
        .map((m) => {
              'role': m.isAssistant ? 'assistant' : 'user',
              'content': m.content
            })
        .toList();

    final userKeys = await _keysSvc.loadAll();

    final payload = <String, dynamic>{
      'provider': _providerId,
      'model': _selectedModel.id,
      'messages': history,
      if (userKeys.isNotEmpty) 'api_keys': userKeys,
    };
    if (_selectedModel.budget > 0)
      payload['thinking_budget'] = _selectedModel.budget;
    if (_pendingImageB64 != null) {
      payload['image'] = _pendingImageB64;
      payload['image_mime'] = _pendingImageMime ?? 'image/jpeg';
    }

    _ws?.sink.add(jsonEncode(payload));
    _tokenSvc.recordRequest(_providerId);
    setState(() {
      _pendingImageB64 = null;
      _pendingImageMime = null;
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
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
    final p = _provider;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentSession?.title == 'Nueva sesión'
              ? 'AGI Chat'
              : (_currentSession?.title ?? 'AGI Chat'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          GestureDetector(
            onTap: _showProviderPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: p.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: p.color),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(p.name,
                    style: TextStyle(
                        color: p.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, color: p.color, size: 16),
              ]),
            ),
          ),
          GestureDetector(
            onTap: _showModelPicker,
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${_selectedModel.name} ${_selectedModel.badge}',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 11)),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down,
                    color: AppTheme.textSecondary, size: 16),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child: ProviderStatusDot(providerId: _providerId, showLabel: false),
          ),
          IconButton(icon: const Icon(Icons.history), onPressed: _showHistory),
          IconButton(icon: const Icon(Icons.add), onPressed: _startNewSession),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.hub, color: p.color, size: 48),
                    const SizedBox(height: 12),
                    Text('${_selectedModel.name} ${_selectedModel.badge}',
                        style: TextStyle(
                            color: p.color, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text('Escribe o habla para empezar',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        ChatBubble(msg: _messages[i], accentColor: p.color),
                  ),
          ),
          ChatToolbar(
            accentColor: p.color,
            controller: _controller,
            running: _running,
            onSend: _send,
            onImageSelected: (b64, mime) => setState(() {
              _pendingImageB64 = b64;
              _pendingImageMime = mime;
            }),
            pendingImageB64: _pendingImageB64,
            onClearImage: () => setState(() {
              _pendingImageB64 = null;
              _pendingImageMime = null;
            }),
          ),
        ],
      ),
    );
  }

  void _showProviderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Seleccionar IA',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              const SizedBox(height: 12),
              ..._providers.map((p) => ListTile(
                    leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: p.color.withValues(alpha: 0.2),
                        child: Icon(Icons.hub, color: p.color, size: 16)),
                    title: Text(p.name,
                        style: TextStyle(
                            color: p.id == _providerId
                                ? p.color
                                : AppTheme.textPrimary)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      ProviderStatusDot(providerId: p.id, showLabel: false),
                      if (p.id == _providerId) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check, color: p.color)
                      ],
                    ]),
                    onTap: () {
                      setState(() {
                        _providerId = p.id;
                        _selectedModel = p.models.first;
                      });
                      Navigator.pop(context);
                      _startNewSession();
                    },
                  )),
            ]),
      ),
    );
  }

  void _showModelPicker() {
    final p = _provider;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modelo ${p.name}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              const SizedBox(height: 12),
              ...p.models.map((m) {
                final isSelected = m.key == _selectedModel.key;
                return ListTile(
                  title: Text(m.name,
                      style: TextStyle(
                          color: isSelected ? p.color : AppTheme.textPrimary)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: p.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(m.badge,
                          style: TextStyle(
                              color: p.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, color: p.color, size: 18)
                    ],
                  ]),
                  onTap: () {
                    setState(() => _selectedModel = m);
                    Navigator.pop(context);
                  },
                );
              }),
            ]),
      ),
    );
  }

  void _showHistory() async {
    final agentId = 'agi_$_providerId';
    final all = await _sessions.loadAll();
    final filtered = all.where((s) => s.agentId == agentId).toList();
    if (!mounted) return;
    final p = _provider;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Text('Historial — ${p.name}',
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
                const Spacer(),
                TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Nueva'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _startNewSession();
                    }),
              ]),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No hay sesiones',
                          style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      controller: sc,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final active = s.id == _currentSession?.id;
                        return ListTile(
                          leading: Icon(
                              active
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                              color: active ? p.color : AppTheme.textSecondary,
                              size: 20),
                          title: Text(s.title,
                              style: TextStyle(
                                  color:
                                      active ? p.color : AppTheme.textPrimary,
                                  fontSize: 13)),
                          subtitle: Text(
                              '${s.messages.length} msgs · ${formatRelativeDate(s.createdAt)}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.textSecondary, size: 18),
                            onPressed: () async {
                              await _sessions.delete(s.id);
                              final updated = (await _sessions.loadAll())
                                  .where((x) => x.agentId == agentId)
                                  .toList();
                              setM(() {
                                filtered.clear();
                                filtered.addAll(updated);
                              });
                              final wasActive = s.id == _currentSession?.id;
                              if (ctx.mounted && wasActive) {
                                Navigator.pop(ctx);
                                _startNewSession();
                              }
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _ws?.sink.close();
                            setState(() => _currentSession = s);
                            _connect();
                            _scrollDown();
                          },
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
