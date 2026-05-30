import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../theme/app_theme.dart';
import '../services/hub_service.dart';

// Carpetas del escritorio del usuario (null path = sin carpeta)
const kDesktopFolders = [
  _Folder('Sin carpeta', null),
  _Folder('AntigravityMobile', r'C:\Users\je416\Desktop\AntigravityMobile'),
  _Folder('AI_IDE_Agents', r'C:\Users\je416\Desktop\AI_IDE_Agents'),
  _Folder('proyectos con ia', r'C:\Users\je416\Desktop\proyectos con ia'),
  _Folder('todos mis proyectos de codigo', r'C:\Users\je416\Desktop\todos mis proyectos de codigo'),
  _Folder('descargas', r'C:\Users\je416\Desktop\descargas'),
  _Folder('ejecutables', r'C:\Users\je416\Desktop\ejecutables'),
  _Folder('volviendo a programar', r'C:\Users\je416\Desktop\volviendo a programar'),
];

class _Folder {
  final String name;
  final String? path;
  const _Folder(this.name, this.path);
}

class ChatToolbar extends StatefulWidget {
  final Color accentColor;
  final TextEditingController controller;
  final bool running;
  final VoidCallback onSend;
  final void Function(String b64, String mime) onImageSelected;
  final String? pendingImageB64;
  final VoidCallback onClearImage;

  const ChatToolbar({
    super.key,
    required this.accentColor,
    required this.controller,
    required this.running,
    required this.onSend,
    required this.onImageSelected,
    this.pendingImageB64,
    required this.onClearImage,
  });

  @override
  State<ChatToolbar> createState() => _ChatToolbarState();
}

class _ChatToolbarState extends State<ChatToolbar> {
  final _stt = SpeechToText();
  bool _listening = false;
  bool _sttReady = false;
  String _currentFolder = 'Sin carpeta';
  String _currentFolderPath = '';
  String _hubBase = HubService.defaultHubUrl().replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _sttReady = await _stt.initialize();
    final prefs = await SharedPreferences.getInstance();
    final wsUrl = prefs.getString('hub_url') ?? HubService.defaultHubUrl();
    _hubBase = wsUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  void _saveFolder(String name, String path) {
    setState(() { _currentFolder = name; _currentFolderPath = path; });
  }

  void _toggleMic() async {
    if (!_sttReady) {
      _showMicUnavailable();
      return;
    }
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
    } else {
      setState(() => _listening = true);
      final started = await _stt.listen(
        onResult: (r) {
          widget.controller.text = r.recognizedWords;
          widget.controller.selection = TextSelection.fromPosition(TextPosition(offset: widget.controller.text.length));
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        localeId: 'es_ES',
      );
      if (!started) {
        setState(() => _listening = false);
        _showMicUnavailable();
        return;
      }
      _stt.statusListener = (s) {
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      };
    }
  }

  void _showMicUnavailable() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.mic_off, size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          const Text('Micrófono no disponible', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'El micrófono requiere una conexión segura (HTTPS).\n\nEl navegador bloquea el acceso al micrófono cuando la app se abre por HTTP desde una IP local.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: widget.accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Solución: usar ngrok', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              const Text('1. Abre ngrok para el servidor móvil\n2. Abre la app con la URL de ngrok (https://...)\n3. El micrófono funcionará', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ),
        ]),
      ),
    );
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Adjuntar imagen', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.folder_open, color: _currentFolderPath.isEmpty ? AppTheme.border : widget.accentColor),
            title: Text('Explorar escritorio', style: TextStyle(color: _currentFolderPath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)),
            subtitle: Text(
              _currentFolderPath.isEmpty ? 'Selecciona una carpeta primero' : 'Navega tus carpetas del PC',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            onTap: _currentFolderPath.isEmpty ? null : () { Navigator.pop(context); _showFolderBrowser(_currentFolderPath); },
          ),
          ListTile(
            leading: Icon(Icons.photo_library, color: widget.accentColor),
            title: const Text('Seleccionar archivo', style: TextStyle(color: AppTheme.textPrimary)),
            subtitle: const Text('Desde el selector del navegador', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickFromDevice(); },
          ),
        ]),
      ),
    );
  }

  Future<void> _pickFromDevice() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;
    final file = result.files.first;
    final ext = file.extension?.toLowerCase() ?? 'jpg';
    final mime = _mimeFromExt(ext);
    final b64 = 'data:$mime;base64,${base64Encode(file.bytes!)}';
    widget.onImageSelected(b64, mime);
  }

  Future<void> _showFolderBrowser(String path) async {
    // Fetch from hub
    Uri uri;
    try {
      uri = Uri.parse('$_hubBase/files/list?path=${Uri.encodeComponent(path)}');
    } catch (_) {
      return;
    }

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final entries = (data['entries'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
          builder: (_, sc) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Icon(Icons.folder, color: widget.accentColor, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(path.split(r'\').last, style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            const Divider(height: 1, color: AppTheme.border),
            Expanded(
              child: ListView(controller: sc, children: [
                // Botón volver si no es raíz
                if (path != r'C:\Users\je416\Desktop')
                  ListTile(
                    leading: const Icon(Icons.arrow_upward, color: AppTheme.textSecondary, size: 18),
                    title: const Text('.. Volver', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                    onTap: () {
                      Navigator.pop(ctx);
                      final parent = path.contains(r'\') ? path.substring(0, path.lastIndexOf(r'\')) : path;
                      _showFolderBrowser(parent);
                    },
                  ),
                ...entries.map((e) {
                  final isDir = e['isDir'] as bool;
                  final isImage = e['isImage'] as bool;
                  final name = e['name'] as String;
                  final ePath = e['path'] as String;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isImage ? Icons.image : (isDir ? Icons.folder : Icons.insert_drive_file),
                      color: isImage ? widget.accentColor : (isDir ? Colors.amber : AppTheme.textSecondary),
                      size: 20,
                    ),
                    title: Text(name, style: TextStyle(color: isImage ? widget.accentColor : AppTheme.textPrimary, fontSize: 13)),
                    onTap: isDir
                        ? () { Navigator.pop(ctx); _showFolderBrowser(ePath); }
                        : isImage
                            ? () { Navigator.pop(ctx); _loadImageFromHub(ePath); }
                            : null,
                  );
                }),
              ]),
            ),
          ]),
        ),
      );
    } catch (_) {}
  }

  Future<void> _loadImageFromHub(String path) async {
    try {
      final uri = Uri.parse('$_hubBase/files/image?path=${Uri.encodeComponent(path)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final b64 = data['data'] as String;
      final mime = data['mime'] as String;
      widget.onImageSelected(b64, mime);
    } catch (_) {}
  }

  void _showFolderPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Carpeta del proyecto', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Selecciona en qué proyecto estás trabajando', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          ...kDesktopFolders.map((f) {
            final isSelected = f.name == _currentFolder;
            final isNone = f.path == null;
            return ListTile(
              dense: true,
              leading: Icon(
                isNone ? Icons.do_not_disturb_alt_outlined : Icons.folder,
                color: isSelected ? widget.accentColor : (isNone ? AppTheme.textSecondary : Colors.amber),
                size: 20,
              ),
              title: Text(f.name, style: TextStyle(
                color: isSelected ? widget.accentColor : (isNone ? AppTheme.textSecondary : AppTheme.textPrimary),
                fontSize: 13,
                fontStyle: isNone ? FontStyle.italic : FontStyle.normal,
              )),
              trailing: isSelected ? Icon(Icons.check, color: widget.accentColor, size: 18) : null,
              onTap: () { _saveFolder(f.name, f.path ?? ''); Navigator.pop(context); },
            );
          }),
        ]),
      ),
    );
  }

  String _mimeFromExt(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      default: return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Barra de proyecto actual
        GestureDetector(
          onTap: _showFolderPicker,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: AppTheme.surface,
            child: Row(children: [
              Icon(
                _currentFolderPath.isEmpty ? Icons.do_not_disturb_alt_outlined : Icons.folder,
                color: _currentFolderPath.isEmpty ? AppTheme.textSecondary : widget.accentColor,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                _currentFolder,
                style: TextStyle(
                  color: _currentFolderPath.isEmpty ? AppTheme.textSecondary : widget.accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontStyle: _currentFolderPath.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, color: AppTheme.textSecondary, size: 14),
            ]),
          ),
        ),
        // Indicador escuchando
        if (_listening)
          Container(
            color: widget.accentColor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.mic, color: widget.accentColor, size: 14),
              const SizedBox(width: 6),
              Text('Escuchando...', style: TextStyle(color: widget.accentColor, fontSize: 11)),
            ]),
          ),
        // Preview imagen pendiente
        if (widget.pendingImageB64 != null)
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              const Icon(Icons.image, color: AppTheme.textSecondary, size: 15),
              const SizedBox(width: 6),
              const Text('Imagen adjunta', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClearImage,
                child: const Icon(Icons.close, size: 15, color: AppTheme.textSecondary),
              ),
            ]),
          ),
        // Input row
        Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 16),
          color: AppTheme.surface,
          child: Row(children: [
            // Imagen
            IconButton(
              icon: Icon(Icons.image_outlined, color: widget.pendingImageB64 != null ? widget.accentColor : AppTheme.textSecondary, size: 22),
              onPressed: _showImageOptions,
              tooltip: 'Imagen',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            // Micrófono
            IconButton(
              icon: Icon(
                _listening ? Icons.mic : (_sttReady ? Icons.mic_none : Icons.mic_off),
                color: _listening ? widget.accentColor : (_sttReady ? AppTheme.textSecondary : AppTheme.textSecondary.withValues(alpha: 0.5)),
                size: 22,
              ),
              onPressed: _toggleMic,
              tooltip: _sttReady ? 'Hablar' : 'Requiere HTTPS',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            // Input texto
            Expanded(
              child: TextField(
                controller: widget.controller,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Mensaje...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => widget.onSend(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 6),
            // Enviar
            IconButton(
              style: IconButton.styleFrom(backgroundColor: widget.accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              icon: widget.running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.bg))
                  : const Icon(Icons.send_rounded, color: AppTheme.bg, size: 20),
              onPressed: widget.running ? null : widget.onSend,
            ),
          ]),
        ),
      ],
    );
  }
}
