import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart';
import '../data/db.dart';
import '../data/repositories/local/local_repository.dart';
import '../data/repositories/cloud/cloud_repository.dart';
import '../data/repositories/base_repository.dart';
import '../services/system/logger_service.dart';
import 'sync_providers.dart';
import 'cloud_mode_providers.dart';
import 'supabase_providers.dart';

// 数据库Provider
final databaseProvider = Provider<BeeDatabase>((ref) {
  final db = BeeDatabase();
  ref.onDispose(() => db.close());
  return db;
});

// 仓储Provider - 根据 AppMode 自动切换实现
// 返回 BaseRepository 类型，确保类型安全
// LocalRepository (本地模式) 和 CloudRepository (云端模式) 都继承 BaseRepository
final repositoryProvider = Provider<BaseRepository>((ref) {
  final mode = ref.watch(appModeProvider);
  final db = ref.watch(databaseProvider);

  logger.info('RepositoryProvider', '当前模式: ${mode.label}');

  switch (mode) {
    case AppMode.local:
      // 本地优先模式：使用 LocalRepository（基于 Drift）
      logger.info('RepositoryProvider', '✅ 使用 LocalRepository (本地模式)');
      return LocalRepository(db);

    case AppMode.cloud:
      // 仅云端模式：使用 CloudRepository（基于 Supabase）
      final supabaseAsync = ref.watch(supabaseInstanceProvider);

      logger.info('RepositoryProvider', 'Supabase 状态: hasValue=${supabaseAsync.hasValue}, value=${supabaseAsync.value != null ? "已加载" : "null"}');

      // 如果 Supabase 未加载完成或为 null，回退到本地模式
      if (!supabaseAsync.hasValue || supabaseAsync.value == null) {
        logger.warning('RepositoryProvider', '⚠️ Supabase 未就绪，回退到 LocalRepository');
        return LocalRepository(db);
      }

      logger.info('RepositoryProvider', '✅ 使用 CloudRepository (仅云端模式)');
      return CloudRepository(supabaseAsync.value!);
  }
});

// 新增：根据 AppMode 返回对应的 Repository 实现
// 这个 Provider 返回抽象接口类型，可以是本地或云端实现
final dynamicRepositoryProvider = Provider<Object>((ref) {
  final mode = ref.watch(appModeProvider);
  final db = ref.watch(databaseProvider);

  switch (mode) {
    case AppMode.local:
      // 本地模式：使用 LocalRepository（基于 Drift）
      return LocalRepository(db);

    case AppMode.cloud:
      // 云端模式：使用 CloudRepository（基于 Supabase）
      final supabaseAsync = ref.watch(supabaseInstanceProvider);

      // 如果 Supabase 未加载完成或为 null，回退到本地模式
      if (!supabaseAsync.hasValue || supabaseAsync.value == null) {
        return LocalRepository(db);
      }

      return CloudRepository(supabaseAsync.value!);
  }
});

// 记住当前账本：启动时加载，切换时持久化
final currentLedgerIdProvider = StateProvider<int>((ref) => 1);

// 获取当前账本的详细信息
final currentLedgerProvider = FutureProvider<Ledger?>((ref) async {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return await repo.getLedgerById(ledgerId);
});

// 获取指定账本的详细信息
final ledgerByIdProvider = FutureProvider.family<Ledger?, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);

  return await repo.getLedgerById(ledgerId);
});

// 获取所有账本列表（Stream版本）
final ledgersStreamProvider = StreamProvider<List<Ledger>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchLedgers();
});

final _currentLedgerPersist = Provider<void>((ref) {
  // load on first read
  () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('current_ledger_id');
      if (saved != null) {
        final st = ref.read(currentLedgerIdProvider);
        if (st != saved) {
          ref.read(currentLedgerIdProvider.notifier).state = saved;
        }
      }
    } catch (_) {}
  }();
  // persist on change
  ref.listen<int>(currentLedgerIdProvider, (prev, next) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_ledger_id', next);
    } catch (_) {}
  });
});

// 当账本切换时，顺便触发一次设置页状态刷新（确保"我的"页及时反映）
final _ledgerChangeListener = Provider<void>((ref) {
  // 激活持久化监听
  ref.read(_currentLedgerPersist);
  ref.listen<int>(currentLedgerIdProvider, (prev, next) {
    ref.read(syncStatusRefreshProvider.notifier).state++;
  });
});

// 确保监听器被激活
final appInitProvider = FutureProvider<void>((ref) async {
  // 读取以激活监听
  ref.read(_ledgerChangeListener);
});

// 分类Provider
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getAllCategories();
});

// 分类与交易笔数组合Provider（响应式版本）
// 使用 autoDispose 在页面关闭时自动取消订阅
final categoriesWithCountProvider = StreamProvider.autoDispose<List<({Category category, int transactionCount})>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchCategoriesWithCount();
});

// 虚拟转账分类Provider（全局缓存，用于获取转账图标）
final transferCategoryProvider = FutureProvider<Category>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getTransferCategory();
});

// 重复交易Provider（按账本过滤）
// 注意：此 provider 已废弃，请使用 allRecurringTransactionsProvider 并在业务层过滤
final recurringTransactionsProvider = FutureProvider.family<List<RecurringTransaction>, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  final all = await repo.watchRecurringTransactionsByLedger(ledgerId).first;
  return all;
});

// 所有重复交易Provider（不限账本）
final allRecurringTransactionsProvider = StreamProvider.autoDispose<List<RecurringTransaction>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAllRecurringTransactions();
});

// 账户Provider（按账本过滤）
final accountsStreamProvider = StreamProvider.family<List<Account>, int>((ref, ledgerId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchAccountsForLedger(ledgerId);
});

// v1.15.0: 所有账户Provider（不限账本）
final allAccountsStreamProvider = StreamProvider<List<Account>>((ref) {
  final repo = ref.watch(repositoryProvider);
  logger.info('AllAccountsStream', '使用的 Repository 类型: ${repo.runtimeType}');
  final stream = repo.watchAllAccounts();
  return stream;
});

// 获取单个账户信息
final accountByIdProvider = FutureProvider.family<Account?, int>((ref, accountId) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getAccount(accountId);
});