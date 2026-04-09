import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_ai_kit_tflite/flutter_ai_kit_tflite.dart';

import '../../widgets/ui/ui.dart';
import '../../widgets/biz/section_card.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../providers/theme_providers.dart';

/// 模型管理页面
class ModelManagementPage extends ConsumerStatefulWidget {
  const ModelManagementPage({super.key});

  @override
  ConsumerState<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends ConsumerState<ModelManagementPage> {
  final ModelManager _modelManager = ModelManager();

  // 下载进度
  final Map<String, double> _downloadProgress = {};

  // 下载状态
  final Map<String, ModelDownloadState> _downloadStates = {};

  @override
  void initState() {
    super.initState();
    _loadStates();
  }

  Future<void> _loadStates() async {
    for (final model in PredefinedModels.all) {
      final state = await _modelManager.getModelState(model.id);
      if (mounted) {
        setState(() {
          _downloadStates[model.id] = state;
        });
      }
    }
  }

  Future<void> _downloadModel(ModelInfo model) async {
    setState(() {
      _downloadStates[model.id] = ModelDownloadState.downloading;
      _downloadProgress[model.id] = 0.0;
    });

    try {
      await _modelManager.downloadModel(
        model,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress[model.id] = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadStates[model.id] = ModelDownloadState.downloaded;
        });
        showToast(context, '${model.name} 下载完成');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadStates[model.id] = ModelDownloadState.notDownloaded;
        });
        showToast(context, '下载失败: $e');
      }
    }
  }

  Future<void> _cancelDownload(ModelInfo model) async {
    await _modelManager.cancelDownload(model.id);
    if (mounted) {
      setState(() {
        _downloadStates[model.id] = ModelDownloadState.notDownloaded;
        _downloadProgress[model.id] = 0.0;
      });
    }
  }

  Future<void> _deleteModel(ModelInfo model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${model.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _modelManager.deleteModel(model.id);
        if (mounted) {
          setState(() {
            _downloadStates[model.id] = ModelDownloadState.notDownloaded;
          });
          showToast(context, '${model.name} 已删除');
        }
      } catch (e) {
        if (mounted) {
          showToast(context, '删除失败: $e');
        }
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: '模型管理',
            subtitle: '下载和管理本地AI模型',
            showBack: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: 12.0.scaled(context, ref),
                vertical: 8.0.scaled(context, ref),
              ),
              children: [
                // 模型列表
                for (final model in PredefinedModels.all)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8.0.scaled(context, ref)),
                    child: _buildModelCard(model),
                  ),

                // 提示信息
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: BeeTokens.textSecondary(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '关于本地模型',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: BeeTokens.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• 本地模型完全离线运行，保护隐私\n'
                        '• 下载的模型将存储在应用目录中\n'
                        '• 首次使用需要下载，之后可离线使用\n'
                        '• 模型仅用于辅助账单信息提取',
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textTertiary(context),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(ModelInfo model) {
    final state = _downloadStates[model.id] ?? ModelDownloadState.notDownloaded;
    final progress = _downloadProgress[model.id] ?? 0.0;

    return SectionCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模型信息
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ref.watch(primaryColorProvider).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.memory,
                    color: ref.watch(primaryColorProvider),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatBytes(model.size)} · ${model.version}',
                        style: TextStyle(
                          fontSize: 13,
                          color: BeeTokens.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 状态与操作
            _buildStateWidget(model, state, progress),
          ],
        ),
      ),
    );
  }

  Widget _buildStateWidget(ModelInfo model, ModelDownloadState state, double progress) {
    switch (state) {
      case ModelDownloadState.notDownloaded:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _downloadModel(model),
            icon: const Icon(Icons.download, size: 20),
            label: const Text('下载模型'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ref.watch(primaryColorProvider),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        );

      case ModelDownloadState.downloading:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: BeeTokens.border(context),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        ref.watch(primaryColorProvider),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ref.watch(primaryColorProvider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelDownload(model),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('取消下载'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: BeeTokens.textSecondary(context),
                  side: BorderSide(color: BeeTokens.border(context)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        );

      case ModelDownloadState.downloaded:
        return Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '已下载',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _deleteModel(model),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('删除'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red[700],
                side: BorderSide(color: Colors.red[200]!),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );

      case ModelDownloadState.failed:
        return Column(
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '下载失败',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _downloadModel(model),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ref.watch(primaryColorProvider),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }
}
