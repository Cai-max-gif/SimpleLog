import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_provider_config.dart';
import '../system/logger_service.dart';

/// AI 服务商管理服务
///
/// 管理多个服务商配置和能力绑定
class AIProviderManager {
  static const String _tag = 'AIProviderManager';
  static const String _keyProviders = 'ai_providers_v2';
  static const String _keyBinding = 'ai_capability_binding_v2';

  /// 生成简单的唯一ID
  static String _generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'provider_${timestamp}_$random';
  }

  /// 获取所有服务商配置
  static Future<List<AIServiceProviderConfig>> getProviders() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyProviders);

    if (jsonStr == null || jsonStr.isEmpty) {
      // 首次使用，尝试从旧配置迁移
      await migrateFromOldConfig();

      // 迁移后重新读取
      final migratedStr = prefs.getString(_keyProviders);
      if (migratedStr == null || migratedStr.isEmpty) {
        // 如果迁移后仍为空，初始化默认服务商
        final defaultProviders = [AIServiceProviderConfig.zhipuDefault];
        await _saveProviders(defaultProviders);
        return defaultProviders;
      }
      // 迁移成功，继续解析
      return _parseProviders(migratedStr);
    }

    return _parseProviders(jsonStr);
  }

  /// 解析服务商配置 JSON
  static Future<List<AIServiceProviderConfig>> _parseProviders(String jsonStr) async {
    try {
      final jsonList = jsonDecode(jsonStr) as List;
      var providers = jsonList
          .map((e) => AIServiceProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();

      // 确保智谱GLM始终存在
      if (!providers.any((p) => p.id == 'zhipu_glm')) {
        providers.insert(0, AIServiceProviderConfig.zhipuDefault);
        await _saveProviders(providers);
      }

      // 修复：如果智谱GLM的API Key为空，尝试从旧配置读取
      final zhipuIndex = providers.indexWhere((p) => p.id == 'zhipu_glm');
      if (zhipuIndex >= 0 && !providers[zhipuIndex].isValid) {
        final prefs = await SharedPreferences.getInstance();
        final oldApiKey = prefs.getString('ai_glm_api_key') ?? '';
        if (oldApiKey.isNotEmpty) {
          logger.info(_tag, '从旧配置恢复智谱API Key');
          providers[zhipuIndex] = providers[zhipuIndex].copyWith(
            apiKey: oldApiKey,
            textModel: prefs.getString('ai_glm_model') ?? providers[zhipuIndex].textModel,
            visionModel: prefs.getString('ai_glm_vision_model') ?? providers[zhipuIndex].visionModel,
            audioModel: prefs.getString('ai_glm_audio_model') ?? providers[zhipuIndex].audioModel,
          );
          await _saveProviders(providers);
        }
      }

      return providers;
    } catch (e, st) {
      logger.error(_tag, '解析服务商配置失败', e, st);
      return [AIServiceProviderConfig.zhipuDefault];
    }
  }

  /// 获取单个服务商配置
  static Future<AIServiceProviderConfig?> getProvider(String id) async {
    final providers = await getProviders();
    try {
      return providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 添加服务商
  static Future<AIServiceProviderConfig> addProvider({
    required String name,
    required String apiKey,
    required String baseUrl,
    String textModel = '',
    String visionModel = '',
    String audioModel = '',
  }) async {
    final providers = await getProviders();

    final newProvider = AIServiceProviderConfig(
      id: _generateId(),
      name: name,
      isBuiltIn: false,
      apiKey: apiKey,
      baseUrl: baseUrl,
      textModel: textModel,
      visionModel: visionModel,
      audioModel: audioModel,
      createdAt: DateTime.now(),
    );

    providers.add(newProvider);
    await _saveProviders(providers);

    logger.info(_tag, '添加服务商: ${newProvider.name}');
    return newProvider;
  }

  /// 直接添加服务商配置（保留原始 ID，用于配置导入）
  static Future<void> addProviderWithConfig(AIServiceProviderConfig provider) async {
    final providers = await getProviders();
    providers.add(provider);
    await _saveProviders(providers);
    logger.info(_tag, '导入服务商: ${provider.name} (ID: ${provider.id})');
  }

  /// 更新服务商
  static Future<void> updateProvider(AIServiceProviderConfig provider) async {
    final providers = await getProviders();
    final index = providers.indexWhere((p) => p.id == provider.id);

    if (index >= 0) {
      providers[index] = provider;
      await _saveProviders(providers);
      logger.info(_tag, '更新服务商: ${provider.name}');
    }
  }

  /// 删除服务商
  static Future<bool> deleteProvider(String id) async {
    final providers = await getProviders();
    final provider = providers.firstWhere(
      (p) => p.id == id,
      orElse: () => AIServiceProviderConfig.zhipuDefault,
    );

    // 内置服务商不可删除
    if (provider.isBuiltIn) {
      logger.warning(_tag, '无法删除内置服务商');
      return false;
    }

    providers.removeWhere((p) => p.id == id);
    await _saveProviders(providers);

    // 如果删除的服务商正在使用，重置为默认
    final binding = await getCapabilityBinding();
    var needUpdate = false;
    var newBinding = binding;

    if (binding.textProviderId == id) {
      newBinding = newBinding.copyWith(textProviderId: 'zhipu_glm');
      needUpdate = true;
    }
    if (binding.visionProviderId == id) {
      newBinding = newBinding.copyWith(visionProviderId: 'zhipu_glm');
      needUpdate = true;
    }
    if (binding.speechProviderId == id) {
      newBinding = newBinding.copyWith(speechProviderId: 'zhipu_glm');
      needUpdate = true;
    }

    if (needUpdate) {
      await saveCapabilityBinding(newBinding);
    }

    logger.info(_tag, '删除服务商: ${provider.name}');
    return true;
  }

  /// 保存服务商列表
  static Future<void> _saveProviders(List<AIServiceProviderConfig> providers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(providers.map((p) => p.toJson()).toList());
    await prefs.setString(_keyProviders, jsonStr);
  }

  /// 获取能力绑定配置
  static Future<AICapabilityBinding> getCapabilityBinding() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyBinding);

    if (jsonStr == null || jsonStr.isEmpty) {
      return AICapabilityBinding.defaultBinding;
    }

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AICapabilityBinding.fromJson(json);
    } catch (e, st) {
      logger.error(_tag, '解析能力绑定失败', e, st);
      return AICapabilityBinding.defaultBinding;
    }
  }

  /// 保存能力绑定配置
  static Future<void> saveCapabilityBinding(AICapabilityBinding binding) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(binding.toJson());
    await prefs.setString(_keyBinding, jsonStr);
    logger.info(_tag, '保存能力绑定: text=${binding.textProviderId}, vision=${binding.visionProviderId}, speech=${binding.speechProviderId}');
  }

  /// 设置单个能力的服务商
  static Future<void> setCapabilityProvider(
    AICapabilityType type,
    String providerId,
  ) async {
    final binding = await getCapabilityBinding();
    AICapabilityBinding newBinding;

    switch (type) {
      case AICapabilityType.text:
        newBinding = binding.copyWith(textProviderId: providerId);
        break;
      case AICapabilityType.vision:
        newBinding = binding.copyWith(visionProviderId: providerId);
        break;
      case AICapabilityType.speech:
        newBinding = binding.copyWith(speechProviderId: providerId);
        break;
    }

    await saveCapabilityBinding(newBinding);
  }

  /// 获取指定能力的服务商配置
  static Future<AIServiceProviderConfig?> getProviderForCapability(
    AICapabilityType type,
  ) async {
    final binding = await getCapabilityBinding();
    String? providerId;

    switch (type) {
      case AICapabilityType.text:
        providerId = binding.textProviderId;
        break;
      case AICapabilityType.vision:
        providerId = binding.visionProviderId;
        break;
      case AICapabilityType.speech:
        providerId = binding.speechProviderId;
        break;
    }

    if (providerId == null) {
      return AIServiceProviderConfig.zhipuDefault;
    }

    return await getProvider(providerId);
  }

  /// 迁移旧配置到新格式
  static Future<void> migrateFromOldConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // 检查是否已迁移
    if (prefs.containsKey(_keyProviders)) {
      return;
    }

    logger.info(_tag, '开始迁移旧配置');

    // 读取旧配置 - 使用 AIConstants 中定义的 key
    final oldProvider = prefs.getString('ai_service_provider') ?? 'zhipuGLM';
    final isCustom = oldProvider == 'custom';

    // 读取智谱 GLM 配置（使用正确的 key）
    final glmApiKey = prefs.getString('ai_glm_api_key') ?? '';
    final glmTextModel = prefs.getString('ai_glm_model') ?? 'glm-4-flash';
    final glmVisionModel = prefs.getString('ai_glm_vision_model') ?? 'glm-4v-flash';
    final glmAudioModel = prefs.getString('ai_glm_audio_model') ?? 'glm-4-voice';

    logger.info(_tag, '迁移智谱配置: apiKey=${glmApiKey.isNotEmpty ? "已配置" : "未配置"}');

    final providers = <AIServiceProviderConfig>[
      // 智谱GLM（从旧配置读取 API Key）
      AIServiceProviderConfig.zhipuDefault.copyWith(
        apiKey: glmApiKey,
        textModel: glmTextModel,
        visionModel: glmVisionModel,
        audioModel: glmAudioModel,
      ),
    ];

    // 如果有自定义服务商配置，也迁移过来（使用正确的 key）
    final customApiKey = prefs.getString('ai_custom_api_key') ?? '';
    final customBaseUrl = prefs.getString('ai_custom_base_url') ?? '';
    if (customApiKey.isNotEmpty && customBaseUrl.isNotEmpty) {
      providers.add(AIServiceProviderConfig(
        id: 'custom_migrated',
        name: '自定义服务商',
        apiKey: customApiKey,
        baseUrl: customBaseUrl,
        textModel: prefs.getString('ai_custom_text_model') ?? '',
        visionModel: prefs.getString('ai_custom_vision_model') ?? '',
        audioModel: prefs.getString('ai_custom_audio_model') ?? '',
        createdAt: DateTime.now(),
      ));
      logger.info(_tag, '迁移自定义服务商配置');
    }

    await _saveProviders(providers);

    // 设置能力绑定
    final defaultProviderId = isCustom && customApiKey.isNotEmpty
        ? 'custom_migrated'
        : 'zhipu_glm';

    await saveCapabilityBinding(AICapabilityBinding(
      textProviderId: defaultProviderId,
      visionProviderId: defaultProviderId,
      speechProviderId: defaultProviderId,
    ));

    logger.info(_tag, '配置迁移完成');
  }
}
