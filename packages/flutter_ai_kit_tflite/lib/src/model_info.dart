/// 模型信息
class ModelInfo {
  /// 模型ID（唯一标识）
  final String id;

  /// 模型显示名称
  final String name;

  /// 模型版本
  final String version;

  /// 模型文件大小（字节）
  final int size;

  /// 下载URL
  final String url;

  /// SHA256校验值
  final String sha256;

  /// 模型描述
  final String? description;

  /// 支持的任务类型
  final List<String> supportedTasks;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.size,
    required this.url,
    required this.sha256,
    this.description,
    this.supportedTasks = const [],
  });

  /// 格式化大小显示
  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  String toString() {
    return 'ModelInfo(id: $id, name: $name, version: $version, size: $sizeFormatted)';
  }
}

/// 预定义模型
class PredefinedModels {
  /// 账单识别模型
  static const billRecognition = ModelInfo(
    id: 'bill_recognition_v1',
    name: '账单识别模型',
    version: '1.0.0',
    size: 43 * 1024 * 1024, // 43MB
    // 使用 CloudFlare R2 CDN 分发，国内访问速度快
    url: 'https://pub-8df06fb0382d45a698804819653c9abd.r2.dev/model/1.tflite',
    sha256: 'skip', // 跳过SHA256验证
    description: '账单信息提取模型，支持金额、时间、商户名称识别',
    supportedTasks: ['bill_extraction', 'ner'],
  );

  /// 所有预定义模型
  static const all = [billRecognition];
}
