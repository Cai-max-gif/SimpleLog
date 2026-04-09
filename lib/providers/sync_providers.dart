import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart' hide SyncStatus;
import '../cloud/sync_service.dart';
import '../cloud/transactions_sync_manager.dart';
import '../models/ledger_display_item.dart';
import '../data/repositories/base_repository.dart';
import '../services/system/logger_service.dart';
import 'database_providers.dart';
import 'ui_state_providers.dart';
import 'statistics_providers.dart';
import 'cloud_mode_providers.dart';

// 同步状态（根据 ledgerId 与刷新 tick 缓存），避免因 UI 重建重复拉取
final syncStatusProvider =
    FutureProvider.family<SyncStatus, int>((ref, ledgerId) async {
  final sync = ref.watch(syncServiceProvider);
  // 依赖 tick，使得手动刷新时重新获取；否则保持缓存
  final refreshTick = ref.watch(syncStatusRefreshProvider);
  print('🟢 [syncStatusProvider] 开始获取状态: ledgerId=$ledgerId, tick=$refreshTick');

  // 直接获取状态，不再清理缓存
  // 缓存的清理由 markLocalChanged() 统一管理
  final status = await sync.getStatus(ledgerId: ledgerId);
  print('🟢 [syncStatusProvider] 状态已获取: ledgerId=$ledgerId, diff=${status.diff}');

  // 写入最近一次成功值，供 UI 在刷新期间显示旧值，避免闪烁
  ref.read(lastSyncStatusProvider(ledgerId).notifier).state = status;
  return status;
});

// 最近一次同步状态缓存（按 ledgerId）
final lastSyncStatusProvider =
    StateProvider.family<SyncStatus?, int>((ref, ledgerId) => null);

// 自动同步开关：值与设置
final autoSyncValueProvider = FutureProvider.autoDispose<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return prefs.getBool('auto_sync') ?? false;
});

class AutoSyncSetter {
  AutoSyncSetter(this._ref);
  final Ref _ref;
  Future<void> set(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync', v);
    // 使缓存失效，触发读取最新值
    _ref.invalidate(autoSyncValueProvider);
  }
}

final autoSyncSetterProvider = Provider<AutoSyncSetter>((ref) {
  return AutoSyncSetter(ref);
});

// 多设备同步开关（默认关闭）
final multiDeviceSyncProvider = FutureProvider.autoDispose<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return prefs.getBool('multi_device_sync') ?? false;
});

class MultiDeviceSyncSetter {
  MultiDeviceSyncSetter(this._ref);
  final Ref _ref;
  Future<void> set(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('multi_device_sync', v);
    _ref.invalidate(multiDeviceSyncProvider);
  }
}

final multiDeviceSyncSetterProvider = Provider<MultiDeviceSyncSetter>((ref) {
  return MultiDeviceSyncSetter(ref);
});

// ====== 云服务配置 ======

final cloudServiceStoreProvider =
    Provider<CloudServiceStore>((_) => CloudServiceStore());

// 当前激活配置（Future，因需读 SharedPreferences）
final activeCloudConfigProvider =
    FutureProvider<CloudServiceConfig>((ref) async {
  final store = ref.watch(cloudServiceStoreProvider);
  return store.loadActive();
});

// Supabase配置(不管是否激活)
final supabaseConfigProvider = FutureProvider<CloudServiceConfig?>((ref) async {
  final store = ref.watch(cloudServiceStoreProvider);
  return store.loadSupabase();
});

// WebDAV配置(不管是否激活)
final webdavConfigProvider = FutureProvider<CloudServiceConfig?>((ref) async {
  final store = ref.watch(cloudServiceStoreProvider);
  return store.loadWebdav();
});

// S3配置(不管是否激活)
final s3ConfigProvider = FutureProvider<CloudServiceConfig?>((ref) async {
  final store = ref.watch(cloudServiceStoreProvider);
  return store.loadS3();
});

final authServiceProvider = FutureProvider<CloudAuthService>((ref) async {
  final activeAsync = ref.watch(activeCloudConfigProvider);
  if (!activeAsync.hasValue) {
    return NoopAuthService();
  }

  final config = activeAsync.value!;
  if (!config.valid || config.type == CloudBackendType.local) {
    return NoopAuthService();
  }

  try {
    final services = await createCloudServices(config);
    if (services.auth != null) {
      return services.auth!;
    }
  } catch (e) {
    // 初始化失败，返回 NoopAuthService
  }

  return NoopAuthService();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final activeAsync = ref.watch(activeCloudConfigProvider);
  if (!activeAsync.hasValue) return LocalOnlySyncService();

  final config = activeAsync.value!;
  if (!config.valid) return LocalOnlySyncService();

  // 检查是否为云端模式
  final mode = ref.watch(appModeProvider);
  if (mode == AppMode.cloud) {
    // 云端模式下，不使用云同步服务（数据直接存储在 Supabase）
    logger.info('SyncServiceProvider', '云端模式：返回 LocalOnlySyncService（云端模式不需要同步）');
    return LocalOnlySyncService();
  }

  final db = ref.watch(databaseProvider);
  final repo = ref.watch(repositoryProvider);

  // 确保 repo 是 BaseRepository 类型
  if (repo is! BaseRepository) {
    logger.warning('SyncServiceProvider', 'repo 不是 BaseRepository 类型，返回 LocalOnlySyncService');
    return LocalOnlySyncService();
  }

  switch (config.type) {
    case CloudBackendType.local:
      return LocalOnlySyncService();

    case CloudBackendType.supabase:
    case CloudBackendType.webdav:
    case CloudBackendType.icloud:
    case CloudBackendType.s3:
      // 使用新的 TransactionsSyncManager (基于 flutter_cloud_sync 包)
      // 采用延迟初始化，首次使用时自动初始化
      return TransactionsSyncManager(
        config: config,
        db: db,
        repo: repo,
      );
  }
});

// 用于触发设置页同步状态的刷新（每次 +1 即可触发 FutureBuilder 重新获取）
final syncStatusRefreshProvider = StateProvider<int>((ref) => 0);

// ====== 账本同步相关 ======

/// 刷新账本列表的触发器
final ledgerListRefreshProvider = StateProvider<int>((ref) => 0);

/// 当前正在上传的账本ID集合
final uploadingLedgerIdsProvider = StateProvider<Set<int>>((ref) => {});

/// 本地账本列表（快速，仅本地）
final localLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 监听刷新触发器（账本列表和统计信息）
  ref.watch(ledgerListRefreshProvider);
  ref.watch(statsRefreshProvider);  // 监听统计刷新，确保自动记账后刷新

  try {
    // 使用 syncServiceProvider，TransactionsSyncManager 现在包含账本管理功能
    final syncService = ref.watch(syncServiceProvider);

    // 获取账户功能开启状态
    final accountFeatureEnabled = await ref.watch(accountFeatureEnabledProvider.future);

    // syncServiceProvider 是同步的，直接使用
    if (syncService is TransactionsSyncManager) {
      return syncService.getLocalLedgers(accountFeatureEnabled: accountFeatureEnabled);
    }

    // 如果是 LocalOnlySyncService，只返回本地账本
    final repo = ref.watch(repositoryProvider);

    // 确保 repo 是 BaseRepository 类型
    if (repo is! BaseRepository) {
      logger.warning('LocalLedgers', 'Repository 类型不是 BaseRepository: ${repo.runtimeType}');
      return [];
    }

    final localLedgers = await repo.getAllLedgers();

    final result = <LedgerDisplayItem>[];
    for (final ledger in localLedgers) {
      // 使用 getLedgerStats 一次性获取余额和交易数，内部会自动查询 transactions
      final stats = await repo.getLedgerStats(
        ledgerId: ledger.id,
        accountFeatureEnabled: accountFeatureEnabled,
      );

      result.add(LedgerDisplayItem.fromLocal(
        id: ledger.id,
        name: ledger.name,
        currency: ledger.currency,
        createdAt: ledger.createdAt,
        transactionCount: stats.transactionCount,
        balance: stats.balance,
      ));
    }

    return result;
  } catch (e, stackTrace) {
    logger.error('LocalLedgers', '获取本地账本列表失败', e, stackTrace);
    return [];
  }
});

/// 远程账本列表（慢速，网络请求）
final remoteLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 监听刷新触发器
  ref.watch(ledgerListRefreshProvider);

  // 使用 syncServiceProvider
  final syncService = ref.watch(syncServiceProvider);

  // 只有 TransactionsSyncManager 才有远程账本
  if (syncService is TransactionsSyncManager) {
    return syncService.getRemoteLedgers();
  }

  // LocalOnlySyncService 没有远程账本
  return [];
});

/// 账本列表（带刷新支持）- 兼容旧代码
final allLedgersProvider = FutureProvider<List<LedgerDisplayItem>>((ref) async {
  // 监听刷新触发器
  ref.watch(ledgerListRefreshProvider);

  try {
    // 使用 syncServiceProvider，TransactionsSyncManager 现在包含账本管理功能
    final syncService = ref.watch(syncServiceProvider);

    // syncServiceProvider 是同步的，直接使用
    if (syncService is TransactionsSyncManager) {
      return syncService.getAllLedgers();
    }

    // 如果是 LocalOnlySyncService，只返回本地账本
    final repo = ref.watch(repositoryProvider);

    // 确保 repo 是 BaseRepository 类型
    if (repo is! BaseRepository) {
      logger.warning('AllLedgers', 'Repository 类型不是 BaseRepository: ${repo.runtimeType}');
      return [];
    }

    final localLedgers = await repo.getAllLedgers();

    final result = <LedgerDisplayItem>[];
    for (final ledger in localLedgers) {
      // 使用 Repository 的 getLedgerStats 方法获取统计数据
      final stats = await repo.getLedgerStats(
        ledgerId: ledger.id,
        accountFeatureEnabled: false, // 这里使用默认值，实际应该从provider读取
      );

      result.add(LedgerDisplayItem.fromLocal(
        id: ledger.id,
        name: ledger.name,
        currency: ledger.currency,
        createdAt: ledger.createdAt,
        transactionCount: stats.transactionCount,
        balance: stats.balance,
      ));
    }

    return result;
  } catch (e, stackTrace) {
    logger.error('AllLedgers', '获取账本列表失败', e, stackTrace);
    return [];
  }
});
