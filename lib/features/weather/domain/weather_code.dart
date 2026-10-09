/// Open-Meteo 返回的 WMO 天气码，映射为简短的中文描述。
///
/// 图标映射在 `presentation/widgets/weather_icon.dart` —— 那是展示决策，
/// 且 domain 不依赖 Flutter。
extension WeatherCodeX on int {
  String get description => switch (this) {
        0 => '晴',
        1 => '大致晴朗',
        2 => '多云',
        3 => '阴',
        45 || 48 => '雾',
        51 || 53 || 55 => '毛毛雨',
        56 || 57 => '冻毛毛雨',
        61 || 63 || 65 => '雨',
        66 || 67 => '冻雨',
        71 || 73 || 75 => '雪',
        77 => '雪粒',
        80 || 81 || 82 => '阵雨',
        85 || 86 => '阵雪',
        95 => '雷阵雨',
        96 || 99 => '雷阵雨伴冰雹',
        _ => '未知',
      };

  /// 昼 / 夜的区分交给知道 `isDay` 的调用方处理。
  String get descriptionDay => this == 0 ? '晴' : description;
}
