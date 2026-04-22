import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 快捷方式事件类型
enum QuickActionType {
  album, // 图片记账
  camera, // 拍照记账
  voice, // 语音记账
  ai, // AI 助手
  none //没有
}

/// 快捷方式事件状态
class QuickActionState {
  final QuickActionType type;
  final bool isHandled;

  const QuickActionState({
    required this.type,
    required this.isHandled,
  });

  QuickActionState copyWith({
    QuickActionType? type,
    bool? isHandled,
  }) {
    return QuickActionState(
      type: type ?? this.type,
      isHandled: isHandled ?? this.isHandled,
    );
  }
}

/// 快捷方式事件 Provider
final quickActionProvider = StateNotifierProvider<QuickActionNotifier, QuickActionState>((ref) {
  return QuickActionNotifier();
});

/// 快捷方式事件 Notifier
class QuickActionNotifier extends StateNotifier<QuickActionState> {
  QuickActionNotifier() : super(const QuickActionState(type: QuickActionType.none, isHandled: true));

  /// 设置快捷方式事件
  void setAction(String type) {
    QuickActionType actionType = QuickActionType.none;
    
    switch (type) {
      case 'action_album':
        actionType = QuickActionType.album;
        break;
      case 'action_camera':
        actionType = QuickActionType.camera;
        break;
      case 'action_voice':
        actionType = QuickActionType.voice;
        break;
      case 'action_ai':
        actionType = QuickActionType.ai;
        break;
    }
    
    state = state.copyWith(
      type: actionType,
      isHandled: false,
    );
  }

  /// 标记事件已处理
  void markAsHandled() {
    state = state.copyWith(
      type: QuickActionType.none,
      isHandled: true,
    );
  }
}
