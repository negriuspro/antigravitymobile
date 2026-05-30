import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HubService {
  static const _prefKey = 'hub_url';

  static String defaultHubUrl() {
    final base = Uri.base;
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final host = base.hasPort ? '${base.host}:${base.port}' : base.host;
    if (host.isEmpty) return 'ws://localhost:3000';
    return '$scheme://$host';
  }

  WebSocketChannel? _channel;
  final _streamController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _streamController.stream;
  bool get isConnected => _channel != null;

  Future<String> getHubUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultHubUrl();
  }

  Future<void> saveHubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
  }

  Future<bool> checkHealth(String baseUrl) async {
    try {
      final httpUrl = baseUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
      final res = await http.get(Uri.parse('$httpUrl/health')).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> connect() async {
    final url = await getHubUrl();
    _channel = WebSocketChannel.connect(Uri.parse('$url/ws/chat'));
    _channel!.stream.listen(
      (raw) {
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        _streamController.add(data);
      },
      onError: (_) => disconnect(),
      onDone: () => disconnect(),
    );
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _streamController.close();
  }
}
