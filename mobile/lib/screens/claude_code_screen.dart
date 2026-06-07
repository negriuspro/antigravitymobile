import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../theme/app_theme.dart';
import '../services/session_service.dart';
import '../services/token_service.dart';
import '../services/api_keys_service.dart';
import '../services/hub_service.dart';
import '../utils/date_format.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_toolbar.dart';
import '../widgets/provider_status_dot.dart';

class _Model {
  final String id;
  final String label;
  final String badge;
  const _Model(this.id, this.label, this.badge);
}

const _agents = [
  _Agent('Claude Code', 'claude_code', Icons.terminal, Color(0xFFCC785C),
      '/claude/stream'),
  _Agent('Codex', 'codex', Icons.code, Color(0xFF10A37F), '/codex/stream'),
  _Agent('AGI', 'agi', Icons.hub, Color(0xFF9B59B6), '/agi/stream'),
  _Agent('Claude', 'claude', Icons.auto_awesome, Color(0xFFCC785C), null),
  _Agent('Gemini', 'gemini', Icons.star_outline, Color(0xFF4285F4), null),
  _Agent('Groq', 'groq', Icons.bolt, Color(0xFFF55036), null),
  _Agent('Cerebras', 'cerebras', Icons.memory, Color(0xFF7D3C98), null),
];

class _Agent {
  final String label;
  final String id;
  final IconData icon;
  final Color color;
  final String? endpoint;
  const _Agent(this.label, this.id, this.icon, this.color, this.endpoint);
}

class ClaudeCodeScreen extends StatefulWidget {
  const ClaudeCodeScreen({super.key});

  @override
  State<ClaudeCodeScreen> createState() => _ClaudeCodeScreenState();
}

class _ClaudeCodeScreenState extends State<ClaudeCodeScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _sessions = SessionService();

  final _tokenSvc = TokenService();
  final _keysSvc = ApiKeysService();
  String? _pendingImageB64;
  String? _pendingImageMime;
  WebSocketChannel? _ws;
  bool _running = false;
  bool _orchestrator = false;
  String _hubWs = HubService.defaultHubUrl();
  _Agent _selected = _agents[0];
  String? _selectedModel;
  ChatSession? _currentSession;

  // Agentes que YA tienen acceso al sistema (no necesitan orquestador)
  bool get _isSystemAgent => _selected.endpoint != null;
  // Agentes de chat que pueden activar modo orquestador
  bool get _canOrchestrate =>
      !_isSystemAgent &&
      (_selected.id == 'groq' ||
          _selected.id == 'cerebras' ||
          _selected.id == 'gemini' ||
          _selected.id == 'claude');

  static const _modelOptions = {
    'claude_code': [
      _Model('claude-sonnet-4-6', 'Claude Sonnet 4.6', 'Smart'),
      _Model('claude-opus-4-7', 'Claude Opus 4.7', 'Max'),
      _Model('claude-haiku-4-5-20251001', 'Claude Haiku 4.5', 'Fast'),
    ],
    'codex': [
      _Model('gpt-4o', 'GPT-4o', 'Smart'),
      _Model('gpt-4o-mini', 'GPT-4o Mini', 'Fast'),
      _Model('o4-mini', 'o4 Mini', 'Reason'),
    ],
    'agi': [
      _Model('llama-3.3-70b-versatile', 'Llama 3.3 70B', 'Fast'),
      _Model(
          'meta-llama/llama-4-scout-17b-16e-instruct', 'Llama 4 Scout', 'Fast'),
      _Model('qwen/qwen3-32b', 'Qwen3 32B', 'Smart'),
    ],
    'claude': [
      _Model('claude-sonnet-4-6', 'Claude Sonnet 4.6', 'Smart'),
      _Model('claude-opus-4-8', 'Claude Opus 4.8', 'Max'),
      _Model('claude-haiku-4-5-20251001', 'Claude Haiku 4.5', 'Fast'),
    ],
    'gemini': [
      _Model('gemini-2.5-flash', 'Gemini 2.5 Flash', 'Fast'),
      _Model('gemini-2.5-pro', 'Gemini 2.5 Pro', 'Smart'),
      _Model('gemini-2.5-flash-lite', 'Gemini 2.5 Flash Lite', 'Fast'),
    ],
    'groq': [
      _Model('llama-3.3-70b-versatile', 'Llama 3.3 70B', 'Fast'),
      _Model(
          'meta-llama/llama-4-scout-17b-16e-instruct', 'Llama 4 Scout', 'Fast'),
      _Model('qwen/qwen3-32b', 'Qwen3 32B', 'Smart'),
    ],
    'cerebras': [
      _Model('gpt-oss-120b', 'GPT OSS 120B', 'Smart'),
      _Model('zai-glm-4.7', 'Z.ai GLM 4.7', 'Reason'),
    ],
  };

  List<_Model> get _currentModels => _modelOptions[_selected.id] ?? [];
  _Model? get _currentModel => _selectedModel != null
      ? _currentModels.where((m) => m.id == _selectedModel).firstOrNull
      : _currentModels.firstOrNull;

  List<ChatMessage> get _messages => _currentSession?.messages ?? [];

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final url = await HubService.currentUrl();
    setState(() => _hubWs = url);
    _startNewSession();
  }

  void _startNewSession() {
    final session = _sessions.createNew(_selected.id);
    setState(() => _currentSession = session);
    _connect();
  }

  void _connect() {
    _ws?.sink.close();
    String endpoint;
    if (_selected.endpoint != null) {
      endpoint = _selected.endpoint!;
    } else if (_orchestrator && _canOrchestrate) {
      endpoint = '/agi/stream';
    } else {
      endpoint = '/ws/chat';
    }
    _ws = WebSocketChannel.connect(Uri.parse('$_hubWs$endpoint'));
    _ws!.stream.listen(
      _onData,
      onDone: () => setState(() => _running = false),
      onError: (_) => setState(() => _running = false),
    );
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    if (_currentSession == null) return;

    if (_selected.endpoint != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['done'] == true) {
          setState(() => _running = false);
          _saveSession();
          return;
        }
      } catch (e, st) {
        debugPrint(
            '[ClaudeCodeScreen._onData] JSON parse error (endpoint): $e\n$st');
      }
      setState(() {
        if (_messages.isNotEmpty && _messages.last.isAssistant) {
          _messages.last.content += raw;
        } else {
          _messages.add(ChatMessage(content: raw, isAssistant: true));
        }
      });
    } else {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final type = json['type'] as String? ?? '';
        if (type == 'start') {
          setState(
              () => _messages.add(ChatMessage(content: '', isAssistant: true)));
        } else if (type == 'chunk') {
          final last = _messages.last;
          setState(() => last.content += json['text'] as String? ?? '');
        } else if (type == 'end') {
          setState(() => _running = false);
          _saveSession();
        }
      } catch (e, st) {
        debugPrint(
            '[ClaudeCodeScreen._onData] JSON parse error (hub): $e\n$st');
      }
    }
    _scrollDown();
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

    final userKeys = await _keysSvc.loadAll();

    if (_selected.endpoint != null) {
      _ws?.sink.add(jsonEncode({
        'prompt': text,
        if (_selectedModel != null) 'model': _selectedModel
      }));
    } else if (_orchestrator && _canOrchestrate) {
      _ws?.sink.add(jsonEncode({
        'prompt': text,
        'provider': _selected.id,
        if (_selectedModel != null) 'model': _selectedModel,
        if (userKeys.isNotEmpty) 'api_keys': userKeys
      }));
      _tokenSvc.recordRequest(_selected.id);
    } else {
      final history = _messages
          .where((m) => m.content.isNotEmpty)
          .map((m) => {
                'role': m.isAssistant ? 'assistant' : 'user',
                'content': m.content
              })
          .toList();
      final payload = <String, dynamic>{
        'provider': _selected.id,
        'messages': history,
        if (_selectedModel != null) 'model': _selectedModel,
        if (userKeys.isNotEmpty) 'api_keys': userKeys
      };
      if (_pendingImageB64 != null) {
        payload['image'] = _pendingImageB64;
        payload['image_mime'] = _pendingImageMime ?? 'image/jpeg';
      }
      _ws?.sink.add(jsonEncode(payload));
      _tokenSvc.recordRequest(_selected.id);
    }
    setState(() {
      _pendingImageB64 = null;
      _pendingImageMime = null;
    });
  }

  void _toggleOrchestrator() {
    if (!_canOrchestrate) return;
    setState(() => _orchestrator = !_orchestrator);
    _connect(); // reconectar al endpoint correcto
  }

  void _switchAgent(_Agent agent) {
    setState(() {
      _selected = agent;
      _running = false;
      // Apagar orquestador al cambiar de agente (es temporal)
      if (agent.endpoint != null) _orchestrator = false;
    });
    _startNewSession();
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_selected.icon, color: _selected.color, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _currentSession?.title == 'Nueva sesión'
                    ? _selected.label
                    : _currentSession!.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_currentModels.isNotEmpty)
            GestureDetector(
              onTap: _showModelPicker,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentModel?.label ?? 'Modelo',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 12),
                    ),
                    if (_currentModel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: _selected.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_currentModel!.badge,
                            style: TextStyle(
                                color: _selected.color,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down,
                        color: AppTheme.textSecondary, size: 16),
                  ],
                ),
              ),
            ),
          // Badge orquestador
          if (_isSystemAgent || (_canOrchestrate && _orchestrator))
            GestureDetector(
              onTap: _canOrchestrate ? _toggleOrchestrator : null,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, color: Colors.green, size: 8),
                  SizedBox(width: 5),
                  Text('Root',
                      style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            )
          else if (_canOrchestrate)
            GestureDetector(
              onTap: _toggleOrchestrator,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle,
                      color: Colors.red.withValues(alpha: 0.7), size: 8),
                  const SizedBox(width: 5),
                  Text('Acceso',
                      style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.8),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
            child:
                ProviderStatusDot(providerId: _selected.id, showLabel: false),
          ),
          IconButton(
              icon: const Icon(Icons.history),
              onPressed: _showSessionHistory,
              tooltip: 'Historial'),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: _startNewSession,
              tooltip: 'Nueva sesión'),
        ],
      ),
      body: Column(
        children: [
          _AgentBar(
              agents: _agents, selected: _selected, onSelect: _switchAgent),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_selected.icon, color: _selected.color, size: 48),
                        const SizedBox(height: 12),
                        Text(_selected.label,
                            style: const TextStyle(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Escribe un mensaje para empezar',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => ChatBubble(
                        msg: _messages[i],
                        accentColor: _selected.color,
                        monospaceAssistant: true),
                  ),
          ),
          ChatToolbar(
            accentColor: _selected.color,
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

  void _showModelPicker() {
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
            const Text('Seleccionar modelo',
                style: TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const SizedBox(height: 12),
            ..._currentModels.map((m) {
              final active = _currentModel?.id == m.id;
              return ListTile(
                title: Text(m.label,
                    style: TextStyle(
                        color:
                            active ? _selected.color : AppTheme.textPrimary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _selected.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(m.badge,
                          style: TextStyle(
                              color: _selected.color,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, color: _selected.color, size: 18)
                    ],
                  ],
                ),
                onTap: () {
                  setState(() => _selectedModel = m.id);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSessionHistory() async {
    final allSessions = await _sessions.loadAll();
    final filtered =
        allSessions.where((s) => s.agentId == _selected.id).toList();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text('Historial — ${_selected.label}',
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
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No hay sesiones guardadas',
                            style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        controller: sc,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final s = filtered[i];
                          final isActive = s.id == _currentSession?.id;
                          return ListTile(
                            leading: Icon(
                              isActive
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                              color: isActive
                                  ? _selected.color
                                  : AppTheme.textSecondary,
                              size: 20,
                            ),
                            title: Text(s.title,
                                style: TextStyle(
                                    color: isActive
                                        ? _selected.color
                                        : AppTheme.textPrimary,
                                    fontSize: 13)),
                            subtitle: Text(
                              '${s.messages.length} mensajes · ${formatRelativeDate(s.createdAt)}',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppTheme.textSecondary, size: 18),
                              onPressed: () async {
                                await _sessions.delete(s.id);
                                final updated = await _sessions.loadAll();
                                setModalState(() => filtered
                                  ..clear()
                                  ..addAll(updated.where(
                                      (x) => x.agentId == _selected.id)));
                                if (s.id == _currentSession?.id) {
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentBar extends StatelessWidget {
  final List<_Agent> agents;
  final _Agent selected;
  final void Function(_Agent) onSelect;

  const _AgentBar(
      {required this.agents, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: agents.length,
        itemBuilder: (_, i) {
          final a = agents[i];
          final active = a.id == selected.id;
          return GestureDetector(
            onTap: () => onSelect(a),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color:
                    active ? a.color.withValues(alpha: 0.15) : AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? a.color : AppTheme.border),
              ),
              child: Row(
                children: [
                  ProviderStatusDot(providerId: a.id, showLabel: false),
                  const SizedBox(width: 5),
                  Icon(a.icon,
                      color: active ? a.color : AppTheme.textSecondary,
                      size: 14),
                  const SizedBox(width: 6),
                  Text(a.label,
                      style: TextStyle(
                          color: active ? a.color : AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.normal)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// _BubbleWidget reemplazado por ChatBubble (widgets/chat_bubble.dart)
