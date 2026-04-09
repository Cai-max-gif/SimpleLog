import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/data/category_service.dart';
import '../services/custom_icon_service.dart';
import '../data/db.dart';
import '../data/models/category_icon.dart';
import '../providers/theme_providers.dart';

/// 统一的分类名称到图标映射，供列表与分类选择共用，保证一致性
/// 现在使用CategoryService的智能推导功能
///
/// 已废弃：请使用 getCategoryIconData 函数代替
@Deprecated('Use getCategoryIconData instead')
IconData iconForCategory(String name) {
  return CategoryService.getCategoryIconByName(name);
}

/// 获取分类的图标数据
///
/// 优先使用分类对象中存储的icon字段,如果为空则根据分类名称智能推导
///
/// [category] 分类对象,可以为null(用于默认分类或虚拟分类)
/// [categoryName] 分类名称,当category为null时必须提供
///
/// 示例:
/// ```dart
/// // 使用分类对象(推荐)
/// final icon = getCategoryIconData(category: myCategory);
///
/// // 仅使用分类名称(回退方案)
/// final icon = getCategoryIconData(categoryName: '餐饮');
/// ```
IconData getCategoryIconData({Category? category, String? categoryName}) {
  // 优先使用分类对象的icon字段
  if (category != null && category.icon != null && category.icon!.isNotEmpty) {
    return CategoryService.getCategoryIcon(category.icon);
  }

  // 回退到名称推导
  final name = category?.name ?? categoryName;
  if (name == null || name.isEmpty) {
    return CategoryService.getCategoryIcon(null); // 返回默认图标
  }

  return CategoryService.getCategoryIconByName(name);
}

/// 分类图标组件
/// 支持 Material Icons 和自定义图片
class CategoryIconWidget extends ConsumerWidget {
  final Category? category;
  final String? categoryName;
  final double size;
  final Color? color;
  final Color? backgroundColor;
  final bool showBackground;
  final bool circular; // 是否使用完全圆形（50%圆角），默认为微圆角（20%）

  const CategoryIconWidget({
    super.key,
    this.category,
    this.categoryName,
    this.size = 24,
    this.color,
    this.backgroundColor,
    this.showBackground = false,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final iconColor = color ?? primaryColor;

    // 检查是否有自定义图标
    if (category != null && category!.iconType == 'custom' && category!.customIconPath != null) {
      return _buildCustomIcon(category!.customIconPath!, iconColor);
    }

    // 使用 Material Icon
    final iconData = getCategoryIconData(category: category, categoryName: categoryName);

    if (showBackground) {
      return Container(
        width: size * 1.5,
        height: size * 1.5,
        decoration: BoxDecoration(
          color: backgroundColor ?? iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(size * 0.375),
        ),
        child: Center(
          child: Icon(iconData, size: size, color: iconColor),
        ),
      );
    }

    return Icon(iconData, size: size, color: iconColor);
  }

  Widget _buildCustomIcon(String path, Color fallbackColor) {
    // 需要异步解析相对路径,使用 FutureBuilder
    return FutureBuilder<String>(
      future: CustomIconService().resolveIconPath(path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // 加载中,显示占位图标
          return Icon(
            Icons.category,
            size: size,
            color: fallbackColor,
          );
        }

        final absolutePath = snapshot.data!;
        final file = File(absolutePath);

        // 图标本身 - 不做圆角裁剪，但填满1:1区域
        final iconWidget = Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover, // 填满整个区域，保持1:1比例
          errorBuilder: (_, __, ___) => Icon(
            Icons.category,
            size: size,
            color: fallbackColor,
          ),
        );

        if (showBackground) {
          // circular 参数只影响背景容器的形状
          final backgroundRadius = circular ? size * 0.75 : size * 0.375;
          return Container(
            width: size * 1.5,
            height: size * 1.5,
            decoration: BoxDecoration(
              color: backgroundColor ?? fallbackColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(backgroundRadius),
            ),
            child: Center(child: iconWidget),
          );
        }

        return iconWidget;
      },
    );
  }
}

/// 从 Category 创建 CategoryIconData
CategoryIconData getCategoryIconDataFromCategory(Category category) {
  return CategoryIconData.fromCategory(category);
}
