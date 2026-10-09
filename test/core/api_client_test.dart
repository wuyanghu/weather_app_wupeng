import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/core/errors/app_exception.dart';
import 'package:weather_app/core/network/api_client.dart';

import '../helpers/fixtures.dart';

/// 这张映射表就是挡住 HTTP 细节进入 UI 的契约，值得用测试钉住。
void main() {
  final options = RequestOptions(path: '/test');

  DioException dio(DioExceptionType type, {int? status}) => DioException(
        requestOptions: options,
        type: type,
        response: status == null
            ? null
            : Response<dynamic>(requestOptions: options, statusCode: status),
      );

  group('mapDioError', () {
    test('maps all timeout variants to TimeoutException', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout
      ]) {
        expect(mapDioError(dio(type)), isA<TimeoutException>());
      }
    });

    test('maps connection errors to NetworkException', () {
      expect(
        mapDioError(dio(DioExceptionType.connectionError)),
        isA<NetworkException>(),
      );
      expect(
        mapDioError(dio(DioExceptionType.unknown)),
        isA<NetworkException>(),
      );
    });

    test('maps bad responses to ServerException carrying the status code', () {
      final e = mapDioError(dio(DioExceptionType.badResponse, status: 503));
      expect(e, isA<ServerException>());
      expect((e as ServerException).statusCode, 503);
    });

    test('passes through existing AppException instances', () {
      const original = ParseException();
      expect(mapDioError(original), same(original));
    });

    test('maps cancellation to CancelledException, not a fake status code', () {
      expect(
        mapDioError(dio(DioExceptionType.cancel)),
        isA<CancelledException>(),
      );
    });

    test('wraps unexpected errors instead of leaking them', () {
      expect(mapDioError(ArgumentError('boom')), isA<NetworkException>());
    });
  });

  group('重试策略', () {
    /// 拦截器里第一次失败会等 400 ms 再重发，所以这条测试本身就慢 ——
    /// 慢是策略的一部分，不要为了让它变快而改退避。
    test('retries a 5xx and then succeeds', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        return calls == 1
            ? jsonResponse({'reason': 'boom'}, statusCode: 500)
            : jsonResponse({'results': []});
      });

      final res = await dio.get<Map<String, dynamic>>('https://example.com/x');

      expect(res.statusCode, 200);
      expect(calls, 2, reason: '5xx 是「再试一次可能就好了」，值得重试');
    });

    test('does not retry a 4xx', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        return jsonResponse({'reason': 'bad param'}, statusCode: 400);
      });

      await dio.get<Map<String, dynamic>>('https://example.com/x');

      expect(calls, 1, reason: '4xx 是请求本身错了，重试只会把失败慢一倍');
    });

    test('does not retry a request the caller cancelled', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return jsonResponse({'results': []});
      });

      final cancel = CancelToken();
      final pending = dio.get<Map<String, dynamic>>(
        'https://example.com/x',
        cancelToken: cancel,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();

      await expectLater(pending, throwsA(isA<DioException>()));
      expect(calls, 1, reason: '调用方已经不等这个结果了，重发只是白占连接');
    });

    test('retries a timeout, not just a 5xx', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((options) async {
        calls++;
        if (calls == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
          );
        }
        return jsonResponse({'results': []});
      });

      final res = await dio.get<Map<String, dynamic>>('https://example.com/x');

      expect(res.statusCode, 200);
      // 超时走 onError、5xx 走 onResponse —— 只有后者原先有测试钉着。
      expect(calls, 2, reason: '超时是「再试一次可能就好了」，值得重试');
    });

    test('stops once the retry budget is used up', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        return jsonResponse({'reason': 'boom'}, statusCode: 500);
      });

      final res = await dio.get<Map<String, dynamic>>('https://example.com/x');

      // 1 次原请求 + 2 次重试，之后必须停 —— 再往上加，用户就先放弃了。
      expect(calls, 3);
      expect(res.statusCode, 500);
    });

    test('does not resend when the caller cancels during backoff', () async {
      var calls = 0;
      final dio = createApiDio();
      dio.httpClientAdapter = FakeHttpAdapter((_) async {
        calls++;
        // 永远 500，于是拦截器拿响应后会进入退避、准备重发。
        return jsonResponse({'reason': 'boom'}, statusCode: 500);
      });

      final cancel = CancelToken();
      final pending = dio.get<Map<String, dynamic>>(
        'https://example.com/x',
        cancelToken: cancel,
      );
      // 第一次响应已回来、拦截器正在等 400 ms 退避 —— 此刻取消。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();

      // Dio 的取消语义是让调用方拿到取消异常，而非交回已被取代的 500 响应。
      await expectLater(
        pending,
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(calls, 1, reason: '退避期间调用方已经不等了，就不该再发');
    });
  });
}
