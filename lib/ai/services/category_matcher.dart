/// 分类匹配器
///
/// 根据商家/备注关键词匹配分类
class CategoryMatcher {
  /// 分类规则（关键词 → 分类）
  static const Map<String, List<String>> _rules = {
    '餐饮美食': [
      '星巴克', '麦当劳', 'KFC', '肯德基', '必胜客', '汉堡王',
      '海底捞', '呷哺呷哺', '外婆家', '西贝', '绿茶',
      '美团外卖', '饿了么', '奶茶', '咖啡', '餐厅', '食堂',
      '面馆', '米线', '火锅', '烧烤', '快餐', '西餐', '日料',
      '蛋糕', '面包', '甜品', '小吃', '零食', '水果',
    ],
    '交通出行': [
      '滴滴', '出租车', '地铁', '公交', '打车',
      '中国石油', '中国石化', '加油', '停车',
      '高铁', '火车', '飞机', '机票', '火车票',
      '共享单车', '摩拜', '哈啰', '青桔',
    ],
    '购物': [
      '淘宝', '京东', '拼多多', '天猫', '闲鱼',
      '苏宁', '国美', '唯品会', '当当', '亚马逊',
      '超市', '便利店', '商场', '专卖店',
      '服饰', '鞋', '包', '化妆品', '电子产品',
      '家具', '家电', '数码',
    ],
    '娱乐': [
      '电影', '影院', '万达', 'IMAX',
      'KTV', '网吧', '游戏', '健身', '游泳',
      '旅游', '景点', '门票',
      '爱奇艺', '腾讯视频', '优酷', '会员',
      'Steam', 'PlayStation', 'Xbox', 'Nintendo',
    ],
    '生活缴费': [
      '电费', '水费', '燃气费', '物业费', '话费',
      '宽带', '网费', '房租',
      '中国移动', '中国联通', '中国电信',
    ],
    '医疗健康': [
      '医院', '诊所', '药店', '体检', '挂号',
      '药', '医疗', '保健', '看病',
    ],
    '教育学习': [
      '学费', '培训', '课程', '书', '网课',
      '知识付费', '得到', '极客时间',
    ],
    '金融保险': [
      '理财', '保险', '基金', '股票', '还款',
      '信用卡', '贷款', '转账',
    ],
  };

  /// 匹配分类
  ///
  /// [text] 商家名称或备注
  /// 返回分类名称，如果没有匹配则返回 "其他"
  String match(String text) {
    if (text.isEmpty) return '其他';

    final lowerText = text.toLowerCase();

    // 遍历所有规则
    for (final entry in _rules.entries) {
      final category = entry.key;
      final keywords = entry.value;

      // 检查是否包含任何关键词
      for (final keyword in keywords) {
        if (lowerText.contains(keyword.toLowerCase())) {
          return category;
        }
      }
    }

    return '其他';
  }

  /// 批量匹配（用于测试）
  Map<String, String> matchBatch(List<String> texts) {
    return {for (var text in texts) text: match(text)};
  }

  /// 获取所有支持的分类
  static List<String> get allCategories =>
      _rules.keys.toList()..add('其他');

  /// 获取分类的关键词数量
  int getKeywordCount(String category) {
    return _rules[category]?.length ?? 0;
  }

  /// 添加自定义规则
  void addCustomRule(String category, List<String> keywords) {
    // 注意：这会修改静态规则，不推荐在运行时使用
    // 这里仅作为扩展接口保留
  }
}
