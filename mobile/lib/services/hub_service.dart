import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HubService {
  static const _prefKey = 'hub_url';

  /// Puerto del frontend Flutter Web cuando corre vía dev-mobile.ps1, y el
  /// puerto donde ese mismo script expone el hub backend (uvicorn --env-file
  /// .env.dev). Si detectamos el primero, el hub real está en el segundo --
  /// no en el puerto del propio frontend.
  static const _devMobileFrontendPort = 5002;
  static const _devMobileHubPort = 8001;

  static String defaultHubUrl() {
    final base = Uri.base;
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    if (base.hasPort && base.port == _devMobileFrontendPort) {
      return '$scheme://${base.host}:$_devMobileHubPort';
    }
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

  /// Versión estática de [getHubUrl] para uso directo sin instancia.
  /// Centraliza los 6 accesos directos a SharedPreferences dispersos por los screens.
  static Future<String> currentUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultHubUrl();
  }

  Future<void> saveHubUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
  }

  Future<bool> checkHealth(String baseUrl) async {
    try {
      final httpUrl = baseUrl
          .replaceFirst('ws://', 'http://')
          .replaceFirst('wss://', 'https://');
      final res = await http
          .get(Uri.parse('$httpUrl/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (e, st) {
      debugPrint('[HubService.checkHealth] unreachable ($baseUrl): $e\n$st');
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
