import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'model_info.dart';

/// 下载进度回调
typedef ProgressCallback = void Function(int received, int total);

/// 模型下载状态
enum ModelDownloadState {
  /// 未下载
  notDownloaded,

  /// 下载中
  downloading,

  /// 已下载
  downloaded,

  /// 下载失败
  failed,
}

/// 模型管理器
///
/// 负责模型的下载、验证、删除和管理
class ModelManager {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};

  /// 获取模型存储目录
  Future<Directory> getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/ai_models');

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return modelsDir;
  }

  /// 获取模型文件路径
  Future<String> getModelPath(String modelId) async {
    final modelsDir = await getModelsDirectory();
    return '${modelsDir.path}/$modelId.tflite';
  }

  /// 获取临时下载文件路径
  Future<String> _getTempPath(String modelId) async {
    final modelsDir = await getModelsDirectory();
    return '${modelsDir.path}/$modelId.tflite.tmp';
  }

  /// 检查模型是否已下载
  Future<bool> isModelDownloaded(String modelId) async {
    final path = await getModelPath(modelId);
    return File(path).existsSync();
  }

  /// 获取模型下载状态
  Future<ModelDownloadState> getModelState(String modelId) async {
    if (_cancelTokens.containsKey(modelId)) {
      return ModelDownloadState.downloading;
    }

    if (await isModelDownloaded(modelId)) {
      return ModelDownloadState.downloaded;
    }

    return ModelDownloadState.notDownloaded;
  }

  /// 下载模型
  ///
  /// [modelInfo] 模型信息
  /// [onProgress] 进度回调
  /// [validateChecksum] 是否验证SHA256（默认true）
  ///
  /// 支持断点续传
  Future<void> downloadModel(
    ModelInfo modelInfo, {
    required ProgressCallback onProgress,
    bool validateChecksum = true,
  }) async {
    final modelPath = await getModelPath(modelInfo.id);
    final tempPath = await _getTempPath(modelInfo.id);

    // 创建CancelToken
    final cancelToken = CancelToken();
    _cancelTokens[modelInfo.id] = cancelToken;

    try {
      // 检查是否有未完成的下载
      int downloadedBytes = 0;
      if (File(tempPath).existsSync()) {
        downloadedBytes = await File(tempPath).length();
        print('📥 [ModelManager] 恢复下载，已下载: ${downloadedBytes}字节');
      }

      // 下载
      await _dio.download(
        modelInfo.url,
        tempPath,
        onReceiveProgress: (received, total) {
          onProgress(received + downloadedBytes, total);
        },
        options: Options(
          headers: {
            if (downloadedBytes > 0) 'Range': 'bytes=$downloadedBytes-',
          },
        ),
        cancelToken: cancelToken,
      );

      // 验证SHA256
      if (validateChecksum && modelInfo.sha256 != 'skip') {
        print('🔍 [ModelManager] 验证文件完整性...');
        final hash = await _calculateSHA256(File(tempPath));

        if (hash != modelInfo.sha256) {
          await File(tempPath).delete();
          throw Exception('SHA256校验失败\n期望: ${modelInfo.sha256}\n实际: $hash');
        }

        print('✅ [ModelManager] 文件校验通过');
      } else if (modelInfo.sha256 == 'skip') {
        print('⚠️ [ModelManager] 跳过SHA256校验');
      }

      // 重命名为正式文件
      await File(tempPath).rename(modelPath);
      print('✅ [ModelManager] 模型下载完成: ${modelInfo.name}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        print('⏸️ [ModelManager] 下载已取消');
        rethrow;
      } else {
        print('❌ [ModelManager] 下载失败: $e');
        rethrow;
      }
    } catch (e) {
      print('❌ [ModelManager] 下载失败: $e');
      rethrow;
    } finally {
      _cancelTokens.remove(modelInfo.id);
    }
  }

  /// 取消下载
  Future<void> cancelDownload(String modelId) async {
    final cancelToken = _cancelTokens[modelId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('User cancelled');
    }
  }

  /// 删除模型
  Future<void> deleteModel(String modelId) async {
    final modelPath = await getModelPath(modelId);
    final tempPath = await _getTempPath(modelId);

    // 取消下载（如果正在下载）
    await cancelDownload(modelId);

    // 删除模型文件
    if (File(modelPath).existsSync()) {
      await File(modelPath).delete();
      print('🗑️ [ModelManager] 已删除模型: $modelId');
    }

    // 删除临时文件
    if (File(tempPath).existsSync()) {
      await File(tempPath).delete();
    }
  }

  /// 获取已下载的模型列表
  Future<List<String>> getDownloadedModels() async {
    final modelsDir = await getModelsDirectory();

    if (!await modelsDir.exists()) {
      return [];
    }

    final files = await modelsDir
        .list()
        .where((entity) =>
            entity is File && entity.path.endsWith('.tflite'))
        .toList();

    return files
        .map((file) => file.path.split('/').last.replaceAll('.tflite', ''))
        .toList();
  }

  /// 获取模型文件大小
  Future<int?> getModelFileSize(String modelId) async {
    final path = await getModelPath(modelId);
    final file = File(path);

    if (await file.exists()) {
      return await file.length();
    }

    return null;
  }

  /// 计算文件SHA256
  Future<String> _calculateSHA256(File file) async {
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 清理所有模型
  Future<void> clearAllModels() async {
    final modelsDir = await getModelsDirectory();

    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
      print('🗑️ [ModelManager] 已清空所有模型');
    }
  }
}
