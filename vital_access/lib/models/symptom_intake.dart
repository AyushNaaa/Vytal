import 'chat_message.dart';

class SymptomIntake {
  /// Full conversation history between user and Claude.
  final List<ChatMessage> conversation;

  /// Claude-generated structured summary of all collected symptoms.
  /// Populated when Claude emits [INTAKE_COMPLETE].
  final String structuredSummary;

  const SymptomIntake({
    required this.conversation,
    required this.structuredSummary,
  });

  /// Returns just the user-side messages as a readable bullet list.
  String get userResponsesSummary {
    final userMessages = conversation
        .where((m) => m.role == 'user')
        .map((m) => '• ${m.content}')
        .join('\n');
    return userMessages;
  }
}
