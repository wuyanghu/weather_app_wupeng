import 'package:dio/dio.dart';

import '../../../core/cancel_signal.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_reporter.dart';
import '../../../core/network/api_client.dart';
import '../domain/place.dart';
import '../domain/weather_models.dart';
import '../domain/weather_repository.dart';
import 'open_meteo_dto.dart';

/// [WeatherRepository] 的 Open-Meteo 实现。
///
/// 两个方法打的是**两个 endpoint**（geocoding 与 forecast），但它们是同一件
/// 事的两步 —— 搜索只是为了拿到坐标，所以放在同一个实现里共享一个 Dio 实例、
/// 一套超时与重试配置、以及同一个异常漏斗。
///
/// 这里硬编码 base URL 是可以接受的：换服务商就等于换掉这个类、再改 DI
/// 装配里的一行 —— repository 这层边界存在的意义正在于此。
class OpenMeteoRepository implements WeatherRepository {
  OpenMeteoRepository({Dio? dio, this._reporter = const SilentErrorReporter()})
    : _dio = dio ?? createApiDio();

  static const _geocodingBase = 'https://geocoding-api.open-meteo.com/v1';
  static const _forecastBase = 'https://api.open-meteo.com/v1';

  final Dio _dio;
  final ErrorReporter _reporter;

  @override
  Future<List<Place>> searchPlaces(
    String query, {
    int limit = 10,
    CancelSignal? cancel,
  }) => guarded(() async {
    if (query.trim().isEmpty) return const [];
    final res = await _dio.get<Map<String, dynamic>>(
      '$_geocodingBase/search',
      queryParameters: {
        'name': query.trim(),
        'count': limit,
        'language': 'zh',
        'format': 'json',
      },
      cancelToken: cancelTokenFor(cancel),
    );
    ensureOk(res);
    // 坐标 / 名字 / id 缺了，这条命中就是废的，直接丢掉：搜索地点就是
    // 为了拿坐标，而坐标补 0 会变成 (0, 0) —— 几内亚湾，一个**合法**坐标。
    // 它不会显示成任何看起来不对的值，只是悄悄查了一个完全错误的地方的
    // 天气，而且查成功了、界面完全正常。宁可少一条结果，也不要一条假的。
    final places = <Place>[];
    for (final dto in GeocodingResponse.fromJson(
      res.data ?? const {},
    ).results) {
      final id = dto.id;
      final name = dto.name;
      final lat = dto.latitude;
      final lon = dto.longitude;
      if (id == null || name == null || lat == null || lon == null) continue;
      places.add(
        Place(
          id: id,
          name: name,
          country: dto.country,
          countryCode: dto.countryCode,
          admin1: dto.admin1,
          latitude: lat,
          admin2: dto.admin2,
          longitude: lon,
          featureCode: dto.featureCode,
          population: dto.population,
        ),
      );
    }
    // 两轮整形，顺序如下：先排序，让重复项中存活的那条是最佳命中，
    // 再折叠渲染结果完全相同的行。API 自身的排序与相关度无关——它曾把
    // 一个 6700 人的 深圳 村和 1700 万人的大城市排在一起。
    places.sort(comparePlacesByRelevance);
    return _dedupe(places);
  }, _reporter);

  @override
  Future<WeatherReport> fetchWeather(Place place) => guarded(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '$_forecastBase/forecast',
      queryParameters: {
        'latitude': place.latitude,
        'longitude': place.longitude,
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m',
        'hourly': 'temperature_2m,weather_code,precipitation_probability',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': 7,
      },
    );
    ensureOk(res);
    final dto = ForecastResponse.fromJson(res.data ?? const {});
    return _toReport(place, dto);
  }, _reporter);

  /// geocoder 会用好几个 feature code 返回同一个实体：搜 "香港" 同时出
  /// `PPLC` 和 `PCLS`，搜 "上海" 出三条一模一样的 云南 村庄。
  /// [Place.displayKey] 相同的行用户根本分不出差别，所以只留排名最前的那条
  /// （列表此时已排好序）。
  List<Place> _dedupe(List<Place> sorted) {
    final seen = <String>{};
    return [
      for (final place in sorted)
        if (seen.add(place.displayKey)) place,
    ];
  }

  /// 把接口载荷翻译成领域实体 —— **「缺了怎么办」在这里决定，不在 DTO 里**。
  ///
  /// 判据只有一句：**这个字段缺了，这条数据还成立吗？**
  /// - 不成立（当前温度 / 天气码 / 日夜 / 观测时刻；逐时的温度与天气码）→
  ///   丢掉这一条，或者让整次请求失败。补一个默认值只会得到「晴天 0°」——
  ///   那不是降级，是界面在陈述一件它并不知道的事。
  /// - 成立（体感 / 湿度 / 风速 / 降水 / 降水概率）→ 原样传 null，
  ///   UI 不显示那一格。**少显示一项，胜过显示一条假的。**
  WeatherReport _toReport(Place place, ForecastResponse dto) {
    // `current.time` 缺失就整次失败：24 小时裁剪和「今天」的判断都建立在它
    // 之上，拿设备的 DateTime.now() 兜底等于用设备的"现在"冒充服务端的"现在"
    // （见 README 四章 timezone=auto 那条）。
    final currentTime = DateTime.tryParse(dto.current.time ?? '');
    if (currentTime == null) throw const ParseException();

    final c = dto.current;
    final temperature = c.temperature;
    final weatherCode = c.weatherCode;
    final isDay = c.isDay;
    if (temperature == null || weatherCode == null || isDay == null) {
      throw const ParseException();
    }

    // 只保留从当前小时开始的接下来 24 小时。
    final hourly = <HourlyWeather>[];
    var hourlySlots = 0;
    for (var i = 0; i < dto.hourly.time.length; i++) {
      final t = DateTime.tryParse(dto.hourly.time[i]);
      if (t == null) continue;
      if (t.isBefore(
        DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
          currentTime.hour,
        ),
      )) {
        continue;
      }
      // 窗口按时间槽位而非成功解析条目计数；缺失一格不能用第 25 小时补上。
      if (hourlySlots >= 24) break;
      hourlySlots++;
      final hourTemperature = dto.hourly.temperature[i];
      final hourCode = dto.hourly.weatherCode[i];
      // 这一个小时缺了温度或天气码 → 整格丢掉。少显示一小时，胜过显示一条假的。
      if (hourTemperature == null || hourCode == null) continue;
      hourly.add(
        HourlyWeather(
          time: t,
          temperature: hourTemperature,
          weatherCode: hourCode,
          precipitationProbability: dto.hourly.precipitationProbability[i],
        ),
      );
    }

    final daily = <DailyWeather>[];
    for (var i = 0; i < dto.daily.time.length; i++) {
      final d = DateTime.tryParse(dto.daily.time[i]);
      if (d == null) continue;
      final max = dto.daily.temperatureMax[i];
      final min = dto.daily.temperatureMin[i];
      final dayCode = dto.daily.weatherCode[i];
      // 温度区间条是这一行的主体，缺了它就别画这一行。
      if (max == null || min == null || dayCode == null) continue;
      daily.add(
        DailyWeather(
          date: d,
          weatherCode: dayCode,
          temperatureMax: max,
          temperatureMin: min,
          precipitationProbability: dto.daily.precipitationProbability[i],
        ),
      );
    }

    return WeatherReport(
      place: place,
      currentTime: currentTime,
      current: CurrentWeather(
        temperature: temperature,
        weatherCode: weatherCode,
        isDay: isDay,
        apparentTemperature: c.apparentTemperature,
        humidity: c.humidity,
        windSpeed: c.windSpeed,
        precipitation: c.precipitation,
      ),
      hourly: hourly,
      daily: daily,
    );
  }
}
