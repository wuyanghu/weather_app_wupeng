/// 统一的异常体系。
///
/// 表现层永远看不到 Dio / Socket / HTTP 的细节 —— 一切都被映射成携带用户可见
/// 文案的 [AppException]，所以 widget 能统一渲染错误，重试逻辑也集中在同一处。
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  /// 可直接渲染给用户的提示文案，不含任何技术细节。
  final String message;

  /// 原始错误对象，只用于日志与排查。
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message (cause: $cause)';
}

/// 设备离线、DNS 解析失败、连接被重置……
final class NetworkException extends AppException {
  const NetworkException({Object? cause})
      : super('网络连接不可用，请检查网络后重试', cause);
}

/// 请求耗时过长。
final class TimeoutException extends AppException {
  const TimeoutException({Object? cause}) : super('请求超时，请稍后重试', cause);
}

/// 服务端返回了非预期状态码，或载荷畸形。
final class ServerException extends AppException {
  const ServerException({this.statusCode, Object? cause})
      : super('服务暂时不可用，请稍后重试', cause);

  final int? statusCode;
}

/// 响应已到达，但没能解析成我们的模型。
final class ParseException extends AppException {
  const ParseException({Object? cause}) : super('数据解析失败，请稍后重试', cause);
}

/// 调用方主动中止的请求（已被更新的查询取代）。状态机会把它丢弃而不是进入
/// 错误态，所以它需要一个专门类型 —— 处理的路径和错误完全不同。
final class CancelledException extends AppException {
  const CancelledException({Object? cause}) : super('请求已取消', cause);
}
