/// Open-Meteo 响应的 DTO：JSON → 强类型，字段跟着接口走。
///
/// 这里的 `*Dto` / `*Response` 只描述*接口的形状*，不代表业务概念 ——
/// 业务对象见 `domain/weather_models.dart`（`WeatherReport`）与
/// `domain/place.dart`（`Place`）。两个 endpoint 的解析**只**放在这一处：
/// 接口改了字段结构，要修的也只有这一个文件。
///
/// ⚠️ **这里的数值字段一律可空**，因为「接口没给」和「接口给了 0」是两件事，
/// 而 0 在天气语义里全是真值（WMO 0 = 晴天、0° = 零度、0 mm = 没下雨）。
/// 早先缺字段补 0，界面于是显示「晴天 0°」—— 那不是容错，是拿合法值表达
/// 缺失：一个字都不少，只是那一格是假的，而且看不出来。官方也明说了并非
/// 所有变量在所有模型上都提供（见 README 四章），所以这不是理论风险。
///
/// 「缺了怎么办」不在这里决定 —— 那是转换层的事：必需字段缺了这条数据就不
/// 成立，可选字段缺了只是这一项不显示。取值工具在 `core/utils/json.dart`，
/// 它只回答「有没有」，不替调用方编一个值。
library;

import '../../../core/utils/json.dart';

// /search 的响应载荷，保持 API 自己的那种结构。
class GeocodingResponse {
  const GeocodingResponse(this.results);

  final List<PlaceDto> results;

  static GeocodingResponse fromJson(Map<String, dynamic> json) {
    final list = (json['results'] as List<Object?>?) ?? const [];
    return GeocodingResponse(
      list
          .map(
            (e) => PlaceDto.fromJson(
              (e as Map<Object?, Object?>).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}

// 一条 geocoder 命中结果，按 JSON 字段名取值；在 repo 中转为领域 Place。
//
// 只有 `country` / `admin1` / `countryCode` / `featureCode` 保留了 `?? ''`：
// 它们是纯展示信息，空串在 UI 侧就是"这一段不显示"（`Place.locationLabel`
// 会跳过空的部分），不像 0 那样会被当成一个真值读出来。反过来，坐标与名字
// 缺了这条命中就完全不能用，所以它们必须是可空的 —— 交给转换层丢弃。
class PlaceDto {
  const PlaceDto({
    required this.id,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.admin1,
    required this.latitude,
    required this.longitude,
    required this.admin2,
    required this.featureCode,
    required this.population,
  });

  final int? id;
  final String? name;
  final String country;
  final String countryCode;
  final String admin1;
  final double? latitude;
  final double? longitude;
  final String admin2;

  /// GeoNames 分类（`PPLA2` 城市、`PPL` 村庄、`AIRP` 机场…）与普查人口数 ——
  /// 结果排序就是建立在这两个信号之上。
  final String featureCode;
  final int? population;

  static PlaceDto fromJson(Map<String, dynamic> j) => PlaceDto(
    id: Json.toIntOrNull(j['id']),
    name: j['name'] as String?,
    country: (j['country'] as String?) ?? '',
    countryCode: (j['country_code'] as String?) ?? '',
    admin1: (j['admin1'] as String?) ?? '',
    latitude: Json.toDoubleOrNull(j['latitude']),
    longitude: Json.toDoubleOrNull(j['longitude']),
    admin2: (j['admin2'] as String?) ?? '',
    featureCode: (j['feature_code'] as String?) ?? '',
    population: Json.toIntOrNull(j['population']),
  );
}

// /forecast 的响应载荷：current + hourly + daily。
class ForecastResponse {
  const ForecastResponse(this.current, this.hourly, this.daily);

  final CurrentDto current;
  final HourlyDto hourly;
  final DailyDto daily;

  static ForecastResponse fromJson(Map<String, dynamic> j) => ForecastResponse(
    CurrentDto.fromJson(
      (j['current'] as Map<Object?, Object?>).cast<String, dynamic>(),
    ),
    HourlyDto.fromJson(
      (j['hourly'] as Map<Object?, Object?>).cast<String, dynamic>(),
    ),
    DailyDto.fromJson(
      (j['daily'] as Map<Object?, Object?>).cast<String, dynamic>(),
    ),
  );
}

// `current` 对象，键就是我们请求的那些参数名。
class CurrentDto {
  const CurrentDto({
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.windSpeed,
    required this.precipitation,
    required this.weatherCode,
    required this.isDay,
    required this.time,
  });

  final double? temperature;
  final double? apparentTemperature;
  final int? humidity;
  final double? windSpeed;
  final double? precipitation;
  final int? weatherCode;
  final bool? isDay;

  /// 观测时刻。它不是"可选展示项" —— 24 小时裁剪和「今天」的判断全靠它，
  /// 所以它缺失必须让整次请求失败，而不是回落到设备的 `DateTime.now()`
  /// （那会用设备的"现在"冒充服务端的"现在"，见 README 四章时区那条）。
  final String? time;

  static CurrentDto fromJson(Map<String, dynamic> j) => CurrentDto(
    temperature: Json.toDoubleOrNull(j['temperature_2m']),
    apparentTemperature: Json.toDoubleOrNull(j['apparent_temperature']),
    humidity: Json.toIntOrNull(j['relative_humidity_2m']),
    windSpeed: Json.toDoubleOrNull(j['wind_speed_10m']),
    precipitation: Json.toDoubleOrNull(j['precipitation']),
    weatherCode: Json.toIntOrNull(j['weather_code']),
    isDay: Json.toBoolOrNull(j['is_day']),
    time: j['time'] as String?,
  );
}

// `hourly` 块：并行数组，每个小时一项。
class HourlyDto {
  const HourlyDto(
    this.time,
    this.temperature,
    this.weatherCode,
    this.precipitationProbability,
  );

  final List<String> time;
  final List<double?> temperature;
  final List<int?> weatherCode;
  final List<int?> precipitationProbability;

  static HourlyDto fromJson(Map<String, dynamic> j) {
    final times = (j['time'] as List<Object?>?)?.cast<String>() ?? const [];
    final n = times.length;

    /// 按 `time` 的长度对齐并行数组：短一截的那些位置给 null（那一个小时
    /// 的这一项缺失），整个 key 不存在时整列都是 null。两种情况都不填默认
    /// 值 —— 由转换层决定这一小时要不要。
    List<T?> sized<T>(List<Object?>? raw, T? Function(Object?) f) => [
      for (var i = 0; i < n; i++)
        f(raw != null && i < raw.length ? raw[i] : null),
    ];

    return HourlyDto(
      times,
      sized(j['temperature_2m'] as List<Object?>?, Json.toDoubleOrNull),
      sized(j['weather_code'] as List<Object?>?, Json.toIntOrNull),
      sized(j['precipitation_probability'] as List<Object?>?, Json.toIntOrNull),
    );
  }
}

// `daily` 块：并行数组，每一天一项。
class DailyDto {
  const DailyDto(
    this.time,
    this.weatherCode,
    this.temperatureMax,
    this.temperatureMin,
    this.precipitationProbability,
  );

  final List<String> time;
  final List<int?> weatherCode;
  final List<double?> temperatureMax;
  final List<double?> temperatureMin;
  final List<int?> precipitationProbability;

  static DailyDto fromJson(Map<String, dynamic> j) {
    final times = (j['time'] as List<Object?>?)?.cast<String>() ?? const [];
    final n = times.length;
    List<T?> sized<T>(List<Object?>? raw, T? Function(Object?) f) => [
      for (var i = 0; i < n; i++)
        f(raw != null && i < raw.length ? raw[i] : null),
    ];

    return DailyDto(
      times,
      sized(j['weather_code'] as List<Object?>?, Json.toIntOrNull),
      sized(j['temperature_2m_max'] as List<Object?>?, Json.toDoubleOrNull),
      sized(j['temperature_2m_min'] as List<Object?>?, Json.toDoubleOrNull),
      sized(
        j['precipitation_probability_max'] as List<Object?>?,
        Json.toIntOrNull,
      ),
    );
  }
}
