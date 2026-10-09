/// 零散的时间 / 数字格式化辅助。
///
/// 刻意保持手写而不引入 `intl` —— 这里的格式化面很小，少一个依赖就少一条要
/// 盯着的升级路径。
class Formatters {
  Formatters._();

  static const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 本地时间，形如 "14:05"。
  static String hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 本地化的星期名；当天显示为 "今天"。
  ///
  /// [now] 必须显式传入。用设备时钟 `DateTime.now()` 判断"今天"是错的：
  /// 请求带 `timezone=auto`，时区由服务端算，设备所在时区未必是所查城市
  /// 的时区 —— 北京时间下午查纽约，两边算出来的"今天"不是同一天。
  /// 调用方应传 `WeatherReport.currentTime`（服务端返回的当地时间）。
  ///
  /// 顺带的好处是这个函数成了纯函数：不读全局时钟，测试能直接换一个
  /// "现在"来断言，不用 fake 系统时间。
  static String weekday(DateTime d, DateTime now) {
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '今天';
    }
    return _weekdays[d.weekday - 1];
  }
}
