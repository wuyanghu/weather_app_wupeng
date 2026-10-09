import 'package:dio/dio.dart';

import '../cancel_signal.dart';
import '../errors/app_exception.dart';
import '../errors/error_reporter.dart';

/// 与 HTTP 客户端打交道的那一层：Dio 配置、重试策略、异常映射，
/// 以及仓储实现用到的三个小工具（取消桥接 / 状态码检查 / 异常漏斗）。
///
/// 后三件放在这里而不是 repository 内部，是因为它们**不认识业务** ——
/// 和同文件的 `mapDioError` 一样属于传输层，跟「这是天气还是地点」无关。
Dio createApiDio() {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
      // 我们自己抛出带类型的 [AppException]，这里让 Dio 保持静默。
      validateStatus: (code) => true,
    ),
  );
  dio.interceptors.add(_RetryInterceptor(dio));
  return dio;
}

/// 重试计数挂在 requestOptions 上，这样重试的每一次都能读到自己是第几次。
const _retryAttemptKey = 'weather_app.retryAttempt';

/// 只对「再试一次可能就好了」的失败重试，并且退避。
///
/// 判断标准不是「出错了」，而是「重发一次有没有意义」：
/// - 超时 / 连接失败 / 5xx → 重试。这两个接口都是 GET，幂等，重发没有副作用。
/// - **主动取消** → 不重试。用户已经不等这个结果了（更快的输入已经取代它），
///   重发只会白占一个连接。
/// - 4xx → 不重试。请求本身是错的，再来一次还是错的，只是把失败慢一倍。
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  /// 最多重试 2 次（共 3 次请求）：再往上加，用户就先放弃了。
  ///
  /// 退避合计只有 1.6 秒，但它不是失败路径的耗时上界 —— 每次请求自身还有
  /// 10 秒超时，而重试次数与超时是相乘的：最坏 3 × 10 + 1.6 ≈ 32 秒才判失败。
  /// 要收紧这条路径，该动的是超时，不是重试次数。
  static const _maxRetries = 2;

  /// 固定退避而不是随机抖动 —— 只有单个客户端在重试，没有惊群问题，
  /// 随机化带来的复杂度换不到什么。
  static const _backoff = <Duration>[
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  final Dio _dio;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = err.requestOptions.extra[_retryAttemptKey] as int? ?? 0;
    if (!_isRetryable(err) || attempt >= _maxRetries) {
      return handler.next(err);
    }

    final retried = await _retryAfterBackoff(err.requestOptions, attempt);
    if (retried == null) return handler.next(err);
    return handler.resolve(retried);
  }

  /// 5xx 会走到这里，而**不是** [onError]。
  ///
  /// 因为 `BaseOptions.validateStatus` 全放行：状态码判定在仓库层的 `_ensureOk`，
  /// Dio 不会为非 200 抛 `DioException`，`DioExceptionType.badResponse`
  /// 永远不会出现 —— 所以服务端错误要不要重试，只能在这里自己看状态码。
  @override
  Future<void> onResponse(
    Response<dynamic> res,
    ResponseInterceptorHandler handler,
  ) async {
    final attempt = res.requestOptions.extra[_retryAttemptKey] as int? ?? 0;
    if ((res.statusCode ?? 200) < 500 || attempt >= _maxRetries) {
      return handler.next(res);
    }

    final retried = await _retryAfterBackoff(res.requestOptions, attempt);
    // 重试本身也失败了：把第一次那个 5xx 交回去，让 `_ensureOk` 照常报错。
    if (retried == null) return handler.next(res);
    return handler.resolve(retried);
  }

  /// 退避后原样重发；**已取消**或重试又失败时返回 `null`，交给调用方决定。
  Future<Response<dynamic>?> _retryAfterBackoff(
    RequestOptions options,
    int attempt,
  ) async {
    final index = attempt < _backoff.length ? attempt : _backoff.length - 1;
    final cancelToken = options.cancelToken;
    // 退避的这几百毫秒里，调用方可能已经不等了（用户敲了新字符，更快的输入
    // 取代了这次请求）。所以退避要和取消**竞速**：取消先到就不重发。
    // 否则那一发是白占一次连接 —— 而且错误类型会搞错：真正发生的是"已取消"，
    // 上报的却是当初那个超时（于是界面渲染一个早就没人等的"请求超时"）。
    await Future.any([
      Future<void>.delayed(_backoff[index]),
      if (cancelToken != null) cancelToken.whenCancel,
    ]);
    if (cancelToken?.isCancelled ?? false) return null;
    try {
      // 用同一份 requestOptions 重发：重试的语义就是「把刚才那次原样再来一遍」。
      return await _dio.fetch(options..extra[_retryAttemptKey] = attempt + 1);
    } on DioException {
      return null;
    }
  }

  static bool _isRetryable(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    // 当前配置下 badResponse 不会出现（validateStatus 全放行，5xx 走
    // onResponse）。留着它是为了以后改配置时这里不会静默失效。
    DioExceptionType.badResponse => (e.response?.statusCode ?? 0) >= 500,
    _ => false,
  };
}

/// 把任意传输层失败映射到本项目的 [AppException] 体系。
///
/// 调用方用这个函数包住请求，因此永远不必直接跟 DioException 打交道。
AppException mapDioError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return TimeoutException(cause: error);
      case DioExceptionType.connectionError:
        return NetworkException(cause: error);
      case DioExceptionType.badResponse:
        return ServerException(
          statusCode: error.response?.statusCode,
          cause: error,
        );
      case DioExceptionType.cancel:
        // 主动取消（更新的查询已取代这一次请求）。调用方会丢弃它而不是渲染出来。
        return CancelledException(cause: error);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return NetworkException(cause: error);
    }
  }
  if (error is AppException) return error;
  return NetworkException(cause: error);
}

/// 把 domain 层那个不依赖 Dio 的 [CancelSignal] 桥接到客户端的原语上。请求
/// 发出*之后*才取消的 token Dio 一样认，所以在这里接好就够了 ——
/// 调用方不用管。
CancelToken? cancelTokenFor(CancelSignal? signal) {
  if (signal == null) return null;
  final token = CancelToken();
  if (signal.isCancelled) {
    token.cancel();
  } else {
    signal.whenCancelled.then((_) {
      if (!token.isCancelled) token.cancel();
    });
  }
  return token;
}

/// 只有 200 算成功；其余一律带着状态码失败。
///
/// 响应体塞进 [ServerException.cause]：Open-Meteo 出错时会在 body 里给
/// reason（比如参数不合法），那是排查唯一能拿到的线索。
void ensureOk(Response<Map<String, dynamic>?> res) {
  final code = res.statusCode ?? 0;
  if (code == 200) {
    if (res.data == null) throw const ParseException();
    return;
  }
  throw ServerException(statusCode: code, cause: res.data);
}

/// 每个仓储方法都要过的那道漏斗：把传输与解析失败统一转成 [AppException]。
///
/// 「哪些异常算 Parse、哪些算 Network」是一处与业务无关的判断，所以它跟着
/// `mapDioError` 住在传输层，而不是写在 repository 里。
Future<T> guarded<T>(Future<T> Function() body, ErrorReporter reporter) async {
  try {
    return await body();
  } on AppException catch (e) {
    _report(reporter, e);
    rethrow;
  } on DioException catch (e) {
    throw _report(reporter, mapDioError(e));
  } on TypeError catch (e) {
    // 载荷畸形（比如缺少 `current`，或字段的 JSON 类型不对）时，
    // 异常是从 DTO 的类型转换里抛出来的。
    throw _report(reporter, ParseException(cause: e));
  } on FormatException catch (e) {
    throw _report(reporter, ParseException(cause: e));
  } catch (e) {
    // 任何异常都不能原样离开仓储层，必须先变成 AppException。
    throw _report(reporter, mapDioError(e));
  }
}

/// 上报并把异常原样返回，这样每个分支只需一行。
AppException _report(ErrorReporter reporter, AppException error) {
  // 被取代的请求不是错误：每敲一个字符都可能产生一次取消，报上去全是噪音，
  // 会把真正的错误淹掉。
  if (error is CancelledException) return error;
  reporter.log(error);
  reporter.upload(error);
  return error;
}
