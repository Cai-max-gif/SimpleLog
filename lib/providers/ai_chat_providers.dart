import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../services/ai/ai_chat_service.dart';
import '../providers.dart';
import '../data/db.dart';

/// AI 对话服务 Provider
final aiChatServiceProvider = Provider<AIChatService>((ref) {
  final repo = ref.watch(repositoryProvider);
  return AIChatService(repo: repo);
});

/// 当前对话 ID Provider
final currentConversationIdProvider = StateProvider<int?>((ref) => null);

/// 消息列表 Provider
final messagesProvider = StreamProvider.family<List<Message>, int>(
  (ref, conversationId) {
    final repo = ref.watch(repositoryProvider);
    return repo.watchMessages(conversationId);
  },
);
