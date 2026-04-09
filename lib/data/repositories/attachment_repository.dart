import '../db.dart';

/// 附件Repository接口
/// 定义附件相关的所有数据操作
abstract class AttachmentRepository {
  // ============================================
  // 基础 CRUD 操作
  // ============================================

  /// 创建附件记录
  Future<int> createAttachment({
    required int transactionId,
    required String fileName,
    String? originalName,
    int? fileSize,
    int? width,
    int? height,
    int sortOrder = 0,
  });

  /// 根据ID获取附件
  Future<TransactionAttachment?> getAttachmentById(int id);

  /// 获取交易的所有附件
  Future<List<TransactionAttachment>> getAttachmentsByTransaction(int transactionId);

  /// 删除附件记录
  Future<void> deleteAttachment(int id);

  /// 删除交易的所有附件记录
  Future<void> deleteAttachmentsByTransaction(int transactionId);

  /// 更新附件排序
  Future<void> updateAttachmentSortOrder(int id, int sortOrder);

  /// 批量更新附件排序
  Future<void> updateAttachmentSortOrders(List<({int id, int sortOrder})> updates);

  // ============================================
  // 查询操作
  // ============================================

  /// 根据文件名检查附件是否存在
  Future<bool> attachmentExistsByFileName(String fileName);

  /// 获取交易的附件数量
  Future<int> getAttachmentCountByTransaction(int transactionId);

  /// 批量获取多个交易的附件数量
  Future<Map<int, int>> getAttachmentCountsForTransactions(List<int> transactionIds);

  /// 批量获取多个交易的附件
  Future<Map<int, List<TransactionAttachment>>> getAttachmentsForTransactions(List<int> transactionIds);

  /// 获取所有有附件的交易ID
  Future<List<int>> getTransactionIdsWithAttachments();

  /// 获取所有附件
  Future<List<TransactionAttachment>> getAllAttachments();

  /// 根据文件名删除附件
  Future<void> deleteAttachmentByFileName(String fileName);

  // ============================================
  // 响应式监听
  // ============================================

  /// 监听交易的附件
  Stream<List<TransactionAttachment>> watchAttachmentsByTransaction(int transactionId);

  /// 监听交易的附件数量
  Stream<int> watchAttachmentCountByTransaction(int transactionId);
}
