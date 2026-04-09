import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cloud_sync_supabase/flutter_cloud_sync_supabase.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';

import '../services/system/logger_service.dart';
import 'sync_providers.dart';

/// Supabase Provider
/// 用于云端模式的 Supabase 连接
/// 复用 flutter_cloud_sync 包的云同步配置系统
final supabaseInstanceProvider =
    FutureProvider<SupabaseProvider?>((ref) async {
  logger.info('SupabaseInstanceProvider', '🔄 开始加载 Supabase 实例');

  // 从统一的云服务配置中读取 Supabase 配置
  final supabaseConfigAsync = ref.watch(supabaseConfigProvider);

  if (!supabaseConfigAsync.hasValue) {
    logger.warning('SupabaseInstanceProvider', '⚠️ Supabase 配置未加载完成');
    return null;
  }

  final config = supabaseConfigAsync.value;

  // 如果没有配置或配置无效，返回 null
  if (config == null || !config.valid) {
    logger.warning('SupabaseInstanceProvider', '⚠️ Supabase 配置不存在或无效');
    return null;
  }

  logger.info('SupabaseInstanceProvider', '✅ Supabase 配置已加载: type=${config.type}, valid=${config.valid}');

  try {
    // 使用 createCloudServices 创建服务实例
    final services = await createCloudServices(config);

    // 从服务中获取 SupabaseProvider
    // flutter_cloud_sync_supabase 包在创建时会返回 SupabaseProvider
    if (services.provider is SupabaseProvider) {
      logger.info('SupabaseInstanceProvider', '✅ Supabase 初始化成功（复用云同步配置）');
      return services.provider as SupabaseProvider;
    }

    logger.warning('SupabaseInstanceProvider', '⚠️ CloudProvider 不是 SupabaseProvider 类型: ${services.provider.runtimeType}');
    return null;
  } catch (e, stackTrace) {
    logger.error('SupabaseInstanceProvider', '❌ Supabase 初始化失败', e, stackTrace);
    return null;
  }
});

/// Supabase Provider Notifier (用于检查状态和手动刷新)
/// 注意：这个 notifier 主要用于向后兼容，实际状态由 supabaseInstanceProvider 管理
class SupabaseInstanceNotifier {
  final Ref ref;

  SupabaseInstanceNotifier(this.ref);

  /// 检查 Supabase 是否已初始化且可用
  bool get isInitialized {
    final asyncValue = ref.read(supabaseInstanceProvider);
    return asyncValue.hasValue && asyncValue.value != null;
  }

  /// 手动重新初始化（切换配置后调用）
  Future<void> reinitialize() async {
    // 使原有的 provider 失效，触发重新加载
    ref.invalidate(supabaseConfigProvider);
    ref.invalidate(supabaseInstanceProvider);
  }
}

/// Supabase Notifier Provider（用于向后兼容测试页面）
final supabaseInstanceNotifierProvider = Provider<SupabaseInstanceNotifier>((ref) {
  return SupabaseInstanceNotifier(ref);
});
