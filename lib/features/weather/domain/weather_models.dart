/// 领域实体 —— 纯不可变数据，不含任何 JSON / HTTP 知识。
///
/// 由 data 层把 Open-Meteo 载荷翻译成它们，所以以后换数据提供方只需要动
/// `data/`，不会波及 UI 与状态逻辑。
///
/// [Place] 不在这个文件里，而在 `domain/place.dart`：它不是天气的概念
/// （字段里一个天气词都没有），只是被天气**消费** ——
/// `WeatherReport.place` 是把 `fetchWeather` 的入参回显进去的标注。
library;

import 'place.dart';

// 某一时刻观测到的天气状况。
//
// ⚠️ **这里的每一处 `?` 都只说一句话：这一项可能没有，UI 要能不显示它。**
// 所以 `temperature` / `weatherCode` / `isDay` 是**非空**的 —— 它们缺了这条
// 天气数据根本不成立，转换层会直接让整次请求失败，而不是把判空推给 UI。
// 反过来带 `?` 的那几项是**可选**的：缺了照样是一份可用的天气，只是少显示
// 一格。判据见 README 四章。
class CurrentWeather {
  const CurrentWeather({
    required this.temperature,
    required this.weatherCode,
    required this.isDay,
    this.apparentTemperature,
    this.humidity,
    this.windSpeed,
    this.precipitation,
  });

  final double temperature;
  final int weatherCode;

  /// 白天 / 夜间决定图标用哪一套。它不是可选项：图标只有这两种形态，
  /// 没有"不知道"的第三种 —— 拿 `true` 兜底就是用一个真值表达缺失。
  final bool isDay;

  final double? apparentTemperature;
  final int? humidity;
  final double? windSpeed;

  /// 前一小时的累计降水。`0.0` 是"实测没下雨"，`null` 是"没有这个测量" ——
  /// 这两件事必须分得开，否则界面会显示一条它其实不知道的信息。
  final double? precipitation;
}

// 一个小时级预报，取自 repository 保留的那 24 个小时。
class HourlyWeather {
  const HourlyWeather({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    this.precipitationProbability,
  });

  final DateTime time;
  final double temperature;
  final int weatherCode;

  /// 部分地区 / 部分模型不给降水概率（见 README 四章）。为 null 时 UI 不显示
  /// 这一格的百分比 —— 而不是显示 0%。
  final int? precipitationProbability;
}

// 一天的预报，包含列表要画成条形的那段最低/最高温度区间。
class DailyWeather {
  const DailyWeather({
    required this.date,
    required this.weatherCode,
    required this.temperatureMax,
    required this.temperatureMin,
    this.precipitationProbability,
  });

  final DateTime date;
  final int weatherCode;
  final double temperatureMax;
  final double temperatureMin;
  final int? precipitationProbability;
}

/// 一次成功预报请求的聚合根。
class WeatherReport {
  const WeatherReport({
    required this.place,
    required this.currentTime,
    required this.current,
    required this.hourly,
    required this.daily,
  });

  final Place place;
  final DateTime currentTime;
  final CurrentWeather current;
  final List<HourlyWeather> hourly;
  final List<DailyWeather> daily;
}
