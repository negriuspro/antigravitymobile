import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

/// Widget de burbuja de chat compartido por los 3 screens de conversación.
/// Consolida _Bubble (chat_claude_screen, agi_chat_screen) y _BubbleWidget (claude_code_screen).
///
/// Diferencias entre screens:
/// - [monospaceAssistant]: activa fuente monoespaciada en respuestas del asistente
///   (usado en claude_code_screen para formatear código).
class ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final Color accentColor;
  final bool monospaceAssistant;

  const ChatBubble({
    super.key,
    required this.msg,
    required this.accentColor,
    this.monospaceAssistant = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = !msg.isAssistant;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (msg.imageB64 != null)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  base64Decode(msg.imageB64!.split(',').last),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (msg.content.isNotEmpty && msg.content != '[Imagen adjunta]')
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85),
              decoration: BoxDecoration(
                color: isUser ? accentColor : AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: isUser ? null : Border.all(color: AppTheme.border),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  color:
                      isUser ? Colors.white : AppTheme.textPrimary,
                  fontSize: 14,
                  fontFamily:
                      (monospaceAssistant && msg.isAssistant) ? 'monospace' : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
