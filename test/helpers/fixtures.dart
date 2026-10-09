import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:weather_app/core/cancel_signal.dart';
import 'package:weather_app/core/errors/app_exception.dart';
import 'package:weather_app/features/weather/domain/place.dart';
import 'package:weather_app/features/weather/domain/weather_models.dart';
import 'package:weather_app/features/weather/domain/weather_repository.dart';

/// 可编排的 repository 假实现，供 widget / 状态测试使用。
class FakeWeatherRepository implements WeatherRepository {
  FakeWeatherRepository({
    this.places = const [],
    this.report,
    this.searchError,
    this.weatherError,
    this.searchDelay = Duration.zero,
    this.callDelays = const [],
    this.resultsByCall = const [],
    this.searchCrash,
  });

  List<Place> places;
  WeatherReport? report;
  AppException? searchError;
  AppException? weatherError;
  Duration searchDelay;

  /// 原样抛出（绕过「只抛 AppException」这条约定），用来验证状态机会
  /// 降级成错误，而不是一直卡在加载转圈上。
  Object? searchCrash;

  /// 每次调用的延迟（下标 = 调用顺序）；缺省回落到 [searchDelay]。
  /// 用于模拟早发的请求反而*晚于*后发的才完成。
  List<Duration> callDelays;

  /// 每次调用的返回结果；缺省回落到 [places]。
  List<List<Place>> resultsByCall;

  int searchCallCount = 0;
  int weatherCallCount = 0;
  final List<String> searchQueries = [];

  /// 传给每次调用的取消句柄，这样测试就能断言被取代的请求确实被中止了，
  /// 而不只是结果被忽略掉。
  final List<CancelSignal> cancelSignals = [];

  @override
  Future<List<Place>> searchPlaces(
    String query, {
    int limit = 10,
    CancelSignal? cancel,
  }) async {
    final index = searchCallCount++;
    searchQueries.add(query);
    final signal = cancel ?? CancelSignal();
    cancelSignals.add(signal);
    final delay = index < callDelays.length ? callDelays[index] : searchDelay;
    if (delay > Duration.zero) {
      await Future.any([Future<void>.delayed(delay), signal.whenCancelled]);
    }
    if (signal.isCancelled) throw const CancelledException();
    if (searchCrash != null) throw searchCrash!;
    if (searchError != null) throw searchError!;
    return index < resultsByCall.length ? resultsByCall[index] : places;
  }

  @override
  Future<WeatherReport> fetchWeather(Place place) async {
    weatherCallCount++;
    if (weatherError != null) throw weatherError!;
    final r = report;
    if (r == null) throw const ServerException(statusCode: 500);
    return r;
  }
}

/// 假传输层：让 repository 测试无需任何网络访问，就能覆盖状态码、畸形
/// 载荷和 socket 故障。
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (cancelFuture == null) return handler(options);
    // 真实传输会中断 socket。让 handler 与 cancel future 竞争，
    // 就是在复现这一行为——这才让取消行为可测。
    return Future.any([
      handler(options),
      cancelFuture.then(
        (_) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      ),
    ]);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object json, {int statusCode = 200}) =>
    ResponseBody.fromString(
      json is String ? json : jsonEncode(json),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 小工具，让测试能简短地拼出 place / report。
Place placeFixture({
  int id = 1,
  String name = '杭州',
  String admin1 = '浙江省',
  String country = '中国',
  String admin2 = '',
  String countryCode = '',
  String featureCode = 'PPLA',
  int? population = 9236032,
}) => Place(
  id: id,
  name: name,
  country: country,
  countryCode: countryCode,
  admin1: admin1,
  featureCode: featureCode,
  admin2: admin2,
  population: population,
  latitude: 30.2741,
  longitude: 120.1551,
);

WeatherReport reportFixture({
  Place? place,
  double temperature = 24.5,
  int weatherCode = 1,
  int hourlyCount = 24,
  int dailyCount = 7,
}) {
  final p = place ?? placeFixture();
  final base = DateTime.now();
  return WeatherReport(
    place: p,
    currentTime: base,
    current: CurrentWeather(
      temperature: temperature,
      apparentTemperature: 26.0,
      humidity: 63,
      windSpeed: 12.3,
      precipitation: 0.0,
      weatherCode: weatherCode,
      isDay: true,
    ),
    hourly: [
      for (var i = 0; i < hourlyCount; i++)
        HourlyWeather(
          time: base.add(Duration(hours: i)),
          temperature: 20 + i % 5,
          weatherCode: i % 3,
          precipitationProbability: i * 2,
        ),
    ],
    daily: [
      for (var i = 0; i < dailyCount; i++)
        DailyWeather(
          date: base.add(Duration(days: i)),
          weatherCode: 2,
          temperatureMax: 28 + i % 3,
          temperatureMin: 18 + i % 3,
          precipitationProbability: 10 + i,
        ),
    ],
  );
}
