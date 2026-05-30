import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mensaje copiado al portapapeles'),
              backgroundColor: AppTheme.surface,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isUser ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
            border: isUser ? null : Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    message.provider.name.toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, letterSpacing: 1),
                  ),
                ),
              MarkdownBody(
                data: message.content,
                selectable: false, // Gesture detector handles copying
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: TextStyle(color: isUser ? AppTheme.bg : AppTheme.textPrimary, fontSize: 14),
                  h1: TextStyle(color: isUser ? AppTheme.bg : AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 18),
                  h2: TextStyle(color: isUser ? AppTheme.bg : AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 16),
                  h3: TextStyle(color: isUser ? AppTheme.bg : AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 15),
                  listBullet: TextStyle(color: isUser ? AppTheme.bg : AppTheme.textSecondary),
                  code: TextStyle(
                    color: isUser ? AppTheme.bg : AppTheme.textPrimary,
                    backgroundColor: isUser ? AppTheme.bg.withValues(alpha: 0.1) : AppTheme.bg,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: isUser ? AppTheme.bg.withValues(alpha: 0.05) : AppTheme.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                ),
              ),
              if (message.isStreaming)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.textSecondary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
