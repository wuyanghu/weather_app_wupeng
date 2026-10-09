import '../../../core/cancel_signal.dart';
import '../../../core/errors/app_exception.dart';
import 'place.dart';
import 'weather_models.dart';

/// 天气数据的契约 —— 接口由 domain 拥有，data 层负责实现。
/// UI / 状态代码只依赖这个抽象。
///
/// 两个方法背后是 Open-Meteo 的两个 endpoint（geocoding 与 forecast），
/// 但它们同属「查天气」这一件事：搜索只是拿到坐标的手段，不是一项独立的能力 ——
/// 现在没有任何调用方只要其中一个。等真出现「只要地点、不要天气」的调用方时，
/// 再按 endpoint 拆成两个接口，成本是新建一个文件加一行装配。
abstract interface class WeatherRepository {
  /// 地点模糊搜索（geocoding）。最多返回 [limit] 条；空列表表示"无匹配"，
  /// 这是正常结果而不是错误。
  ///
  /// [cancel] 触发后，在途请求会被中止，future 以 [CancelledException]
  /// 失败，而不是把过期结果交回去。
  ///
  /// 传输失败时抛 [AppException] 的子类。
  Future<List<Place>> searchPlaces(
    String query, {
    int limit,
    CancelSignal? cancel,
  });

  /// [place] 的完整报告：当前天气 + 未来 24 小时逐时 + 7 天逐日预报。
  ///
  /// 传输失败时抛 [AppException] 的子类。
  Future<WeatherReport> fetchWeather(Place place);
}
