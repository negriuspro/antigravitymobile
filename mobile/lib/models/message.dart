enum MessageRole { user, assistant }
enum AIProvider { claude, gemini, groq, cerebras }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final AIProvider provider;
  final DateTime timestamp;
  final bool isStreaming;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.provider,
    required this.timestamp,
    this.isStreaming = false,
  });

  ChatMessage copyWith({String? content, bool? isStreaming}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        provider: provider,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );

  Map<String, dynamic> toApiMessage() => {
        "role": role == MessageRole.user ? "user" : "assistant",
        "content": content,
      };
}
