import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/core/cancel_signal.dart';
import 'package:weather_app/core/errors/app_exception.dart';
import 'package:weather_app/core/errors/error_reporter.dart';
import 'package:weather_app/core/network/api_client.dart';
import 'package:weather_app/features/weather/data/open_meteo_repository.dart';
import 'package:weather_app/features/weather/domain/place_kind.dart';

import '../helpers/fixtures.dart';

/// repository 测试打在假传输层上，所以快、确定、能离线跑——同时又确实
/// 覆盖了真正要紧的请求 / 解析 / 错误路径。
void main() {
  Dio dioWith(FakeHttpAdapter adapter) {
    final dio = createApiDio();
    dio.httpClientAdapter = adapter;
    return dio;
  }

  group('OpenMeteoRepository.searchPlaces', () {
    test('parses geocoding results into domain places', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((options) async {
            expect(options.path, contains('/search'));
            expect(options.queryParameters['name'], '杭州');
            return jsonResponse({
              'results': [
                {
                  'id': 1808926,
                  'name': '杭州',
                  'country': '中国',
                  'admin1': '浙江省',
                  'latitude': 30.29365,
                  'admin2': '杭州市',
                  'longitude': 120.16142,
                },
              ],
            });
          }),
        ),
      );

      final places = await repo.searchPlaces('杭州');

      expect(places, hasLength(1));
      expect(places.single.name, '杭州');
      expect(places.single.latitude, closeTo(30.29365, 1e-6));
      expect(places.single.displayName, '杭州 · 浙江省, 中国');
      expect(places.single.locationLabel, '杭州市, 浙江省, 中国');
    });

    test('drops a geocoding hit that has no coordinates', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter(
            (_) async => jsonResponse({
              'results': [
                // 没有 latitude / longitude 的一条命中。
                {'id': 1, 'name': '无坐标', 'country': '中国'},
                {
                  'id': 1808926,
                  'name': '杭州',
                  'country': '中国',
                  'admin1': '浙江省',
                  'latitude': 30.29365,
                  'longitude': 120.16142,
                },
              ],
            }),
          ),
        ),
      );

      final places = await repo.searchPlaces('杭州');

      // 坐标补 0 会变成 (0, 0) —— 几内亚湾，一个**合法**坐标。它不会显示成
      // 任何"看起来不对"的值，只是悄悄查了个完全错误的地方。宁可少一条结果。
      expect(places, hasLength(1));
      expect(places.single.name, '杭州');
    });

    test('ranks the real city above same-named villages', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter(
            (_) async => jsonResponse({
              'results': [
                // 返回顺序出自 API，而非相关度：一个村落排在最前。
                {
                  'id': 3,
                  'name': '深圳',
                  'country': '中国',
                  'admin1': '福建省',
                  'latitude': 24.79,
                  'longitude': 118.43,
                  'feature_code': 'PPL',
                },
                {
                  'id': 2,
                  'name': '深圳',
                  'country': '台湾',
                  'country_code': 'TW',
                  'admin1': '臺灣省 or 台灣省',
                  'latitude': 24.95,
                  'longitude': 121.01,
                  'feature_code': 'PPL',
                  'population': 6700,
                },
                {
                  'id': 1,
                  'name': '深圳',
                  'country': '中国',
                  'admin1': '广东',
                  'latitude': 22.54,
                  'longitude': 114.06,
                  'feature_code': 'PPLA2',
                  'population': 17494398,
                },
              ],
            }),
          ),
        ),
      );

      final places = await repo.searchPlaces('深圳');

      expect(places.map((p) => p.id).toList(), [1, 2, 3]);
      expect(places.first.kind, PlaceKind.city);
      // 合规名称改写对排序后的行依然生效。
      expect(places[1].countryOrRegion, '中国台湾');
      expect(places[1].displayName, '深圳 · 中国台湾');
    });

    test('collapses rows that would render identically', () async {
      // 真实 API 的行为：香港会返回两条（PPLC 与 PCLS），标签让用户无从分辨。
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter(
            (_) async => jsonResponse({
              'results': [
                {
                  'id': 1819730,
                  'name': '香港',
                  'country': '',
                  'country_code': 'HK',
                  'latitude': 22.25,
                  'longitude': 114.1667,
                  'feature_code': 'PCLS',
                  'population': 7396076,
                },
                {
                  'id': 1819729,
                  'name': '香港',
                  'country': '',
                  'country_code': 'HK',
                  'latitude': 22.2783,
                  'longitude': 114.1747,
                  'feature_code': 'PPLC',
                  'population': 7396076,
                },
              ],
            }),
          ),
        ),
      );

      final places = await repo.searchPlaces('香港');

      expect(places, hasLength(1));
      // 保留下来的是排序最优的一行（PPLC），而不是先出现的那一行。
      expect(places.single.featureCode, 'PPLC');
      expect(places.single.kind, PlaceKind.specialRegion);
    });

    test('maps a malformed geocoding body to ParseException', () async {
      // "results" 带错误的 JSON 类型时，曾以裸 TypeError 逃逸出去；
      // 搜索状态机捕获不到它 —— 于是搜索框永久转圈，也没有任何重试入口。
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async => jsonResponse({'results': 'not-a-list'})),
        ),
      );

      await expectLater(
        repo.searchPlaces('杭州'),
        throwsA(isA<ParseException>()),
      );
    });

    test('aborts the pending request when the caller cancels', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return jsonResponse({'results': []});
          }),
        ),
      );
      final signal = CancelSignal();
      final pending = repo.searchPlaces('杭州', cancel: signal);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      signal.cancel();

      await expectLater(pending, throwsA(isA<CancelledException>()));
    });

    test('returns an empty list when the API finds nothing', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(FakeHttpAdapter((_) async => jsonResponse({}))),
      );

      expect(await repo.searchPlaces('zzzzz'), isEmpty);
    });

    test('skips the network entirely for a blank query', () async {
      var called = false;
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            called = true;
            return jsonResponse({});
          }),
        ),
      );

      expect(await repo.searchPlaces('   '), isEmpty);
      expect(called, isFalse);
    });

    test('maps a 500 response to ServerException', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter(
            (_) async => jsonResponse({'reason': 'boom'}, statusCode: 500),
          ),
        ),
      );

      await expectLater(
        repo.searchPlaces('杭州'),
        throwsA(
          isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('maps a socket failure to NetworkException', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async => throw Exception('connection refused')),
        ),
      );

      await expectLater(
        repo.searchPlaces('杭州'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('OpenMeteoRepository.fetchWeather', () {
    test('parses current / hourly / daily into one report', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((options) async {
            expect(options.path, contains('/forecast'));
            expect(options.queryParameters['timezone'], 'auto');
            expect(options.queryParameters['forecast_days'], 7);
            return jsonResponse(_forecastJson());
          }),
        ),
      );

      final report = await repo.fetchWeather(placeFixture());

      expect(report.current.temperature, 26.4);
      expect(report.current.isDay, isTrue);
      expect(report.current.weatherCode, 1);
      // 只有从当前小时起的 24 小时会保留下来：fixture 从过去 12 小时开始，
      // 所以首行必须落在下标 12（温度 20 + 12 % 7）。
      expect(report.hourly, hasLength(24));
      final hourFloor = DateTime(
        report.currentTime.year,
        report.currentTime.month,
        report.currentTime.day,
        report.currentTime.hour,
      );
      expect(report.hourly.first.time, hourFloor);
      expect(report.hourly.first.temperature, 25.0);
      expect(
        report.hourly.last.time.difference(report.hourly.first.time),
        const Duration(hours: 23),
      );
      expect(report.daily, hasLength(7));
      expect(report.daily.first.temperatureMax, 29.1);
      expect(report.place.name, '杭州');
    });

    test('missing optional fields become null, never zero', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            final json = _forecastJson();
            // 模拟一个完全不返回降水数组的 API。官方明说并非所有变量在所有模型
            // 上都提供，所以这不是假想场景。
            (json['hourly'] as Map).remove('precipitation_probability');
            (json['daily'] as Map).remove('precipitation_probability_max');
            (json['current'] as Map).remove('precipitation');
            return jsonResponse(json);
          }),
        ),
      );

      final report = await repo.fetchWeather(placeFixture());

      // 关键：缺了是 null，不是 0。0 在天气语义里全是真值（0% = 不会下雨），
      // 拿它表达"没有这一项"，界面就会陈述一件它并不知道的事。
      expect(report.hourly.first.precipitationProbability, isNull);
      expect(report.daily.first.precipitationProbability, isNull);
      expect(report.current.precipitation, isNull);
      // 可选字段缺失不该连累整份天气 —— 必需的那几项仍然完好。
      expect(report.current.temperature, 26.4);
      expect(report.hourly.first.temperature, 25.0);
    });

    test('fails the whole request when a required field is missing', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            final json = _forecastJson();
            (json['current'] as Map).remove('temperature_2m');
            return jsonResponse(json);
          }),
        ),
      );

      // 当前温度缺了，这份天气就不成立。补 0 会得到「0°」—— 那是界面在用
      // 一个合法值表达缺失，比干脆报错糟糕得多。
      await expectLater(
        repo.fetchWeather(placeFixture()),
        throwsA(isA<ParseException>()),
      );
    });

    test('drops an hour whose required fields are missing', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            final json = _forecastJson();
            // 挖掉"当前小时"之后第 3 格的温度（数组起点比 now 早 12 小时）。
            // fixture 的原数组是 List<double>，先复制成 JSON 允许的可空列表，
            // 否则 null 会在 FakeHttpAdapter 返回响应前就触发类型错误。
            final hourly = Map<String, Object?>.from(json['hourly'] as Map);
            final temperatures = List<Object?>.from(
              hourly['temperature_2m'] as List,
            );
            temperatures[14] = null;
            hourly['temperature_2m'] = temperatures;
            json['hourly'] = hourly;
            return jsonResponse(json);
          }),
        ),
      );

      final report = await repo.fetchWeather(placeFixture());

      // 24 格少了一格，其余照旧 —— 少显示一小时，胜过显示一条假的。
      expect(report.hourly, hasLength(23));
      expect(report.daily, hasLength(7));
    });

    test('throws ParseException on a body that is not a forecast', () async {
      final repo = OpenMeteoRepository(
        dio: dioWith(FakeHttpAdapter((_) async => jsonResponse([]))),
      );

      await expectLater(
        repo.fetchWeather(placeFixture()),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('错误上报出口', () {
    test(
      'hands the mapped exception to the reporter, cause included',
      () async {
        final reporter = _RecordingReporter();
        final repo = OpenMeteoRepository(
          dio: dioWith(
            FakeHttpAdapter(
              (_) async => jsonResponse({'error': true}, statusCode: 500),
            ),
          ),
          reporter: reporter,
        );

        await expectLater(
          repo.searchPlaces('杭州'),
          throwsA(isA<ServerException>()),
        );

        expect(reporter.logged, hasLength(1));
        expect(reporter.logged.single, isA<ServerException>());
        // 关键的一条：cause 终于有了消费者 —— 映射前的原始异常被带了过来，不是 null。
        expect(reporter.logged.single.cause, isNotNull);
        expect(reporter.uploaded, hasLength(1));
      },
    );

    test('does not report a request that was superseded', () async {
      final reporter = _RecordingReporter();
      final repo = OpenMeteoRepository(
        dio: dioWith(
          FakeHttpAdapter((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return jsonResponse({'results': []});
          }),
        ),
        reporter: reporter,
      );
      final signal = CancelSignal();
      final pending = repo.searchPlaces('杭州', cancel: signal);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      signal.cancel();

      await expectLater(pending, throwsA(isA<CancelledException>()));

      // 取消是正常流程，每敲一个字符都可能发生一次 —— 报上去只会淹没真错误。
      expect(reporter.logged, isEmpty);
      expect(reporter.uploaded, isEmpty);
    });

    test(
      'stays silent by default, so existing callers are unaffected',
      () async {
        final repo = OpenMeteoRepository(
          dio: dioWith(
            FakeHttpAdapter(
              (_) async => jsonResponse({'error': true}, statusCode: 500),
            ),
          ),
        );

        await expectLater(
          repo.searchPlaces('杭州'),
          throwsA(isA<ServerException>()),
        );
      },
    );
  });
}

/// 记录型 reporter：断言「异常有没有被送出来」而不是「打印了什么」。
class _RecordingReporter implements ErrorReporter {
  final List<AppException> logged = [];
  final List<AppException> uploaded = [];

  @override
  void log(AppException error) => logged.add(error);

  @override
  void upload(AppException error) => uploaded.add(error);
}

Map<String, dynamic> _forecastJson() {
  final now = DateTime.now();
  final hourFloor = DateTime(now.year, now.month, now.day, now.hour);
  String iso(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}T${t.hour.toString().padLeft(2, '0')}:00';

  return {
    'current': {
      'time': iso(hourFloor),
      'temperature_2m': 26.4,
      'relative_humidity_2m': 61,
      'apparent_temperature': 28.0,
      'is_day': 1,
      'precipitation': 0.0,
      'weather_code': 1,
      'wind_speed_10m': 9.7,
    },
    'hourly': {
      // 起点比 "now" 早 12 小时，这样裁剪逻辑才真正被考验到。
      'time': [
        for (var i = -12; i < 36; i++) iso(hourFloor.add(Duration(hours: i))),
      ],
      'temperature_2m': [for (var i = 0; i < 48; i++) 20.0 + i % 7],
      'weather_code': [for (var i = 0; i < 48; i++) i % 4],
      'precipitation_probability': [for (var i = 0; i < 48; i++) (i * 3) % 100],
    },
    'daily': {
      'time': [
        for (var i = 0; i < 7; i++)
          '${hourFloor.add(Duration(days: i)).year}-'
              '${hourFloor.add(Duration(days: i)).month.toString().padLeft(2, '0')}-'
              '${hourFloor.add(Duration(days: i)).day.toString().padLeft(2, '0')}',
      ],
      'weather_code': [for (var i = 0; i < 7; i++) 1 + i % 3],
      'temperature_2m_max': [for (var i = 0; i < 7; i++) 29.1 + i % 4],
      'temperature_2m_min': [for (var i = 0; i < 7; i++) 18.2 + i % 3],
      'precipitation_probability_max': [for (var i = 0; i < 7; i++) 10 + i * 5],
    },
  };
}
