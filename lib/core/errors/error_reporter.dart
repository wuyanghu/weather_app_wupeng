import 'package:flutter/foundation.dart';

import 'app_exception.dart';

/// 错误上报的出口 —— `AppException.cause` 的去处就在这里。
///
/// [log] 与 [upload] 分开：前者是开发期排查用的，后者取决于有没有接入远端
/// 服务 —— take-home 没有埋点需求，默认实现是空的（接口先就位，实现留白）。
abstract interface class ErrorReporter {
  /// 本地打印。release 下应当静默（由实现自行判断）。
  void log(AppException error);

  /// 远端上报。没有接入服务时允许是空实现。
  void upload(AppException error);
}

/// 默认实现：什么都不做。
///
/// 不依赖 Flutter，纯 Dart 环境也能用 —— repository 的默认参数就是它，
/// 因此既有的仓库测试无需改动、行为完全不变。
class SilentErrorReporter implements ErrorReporter {
  const SilentErrorReporter();

  @override
  void log(AppException error) {}

  @override
  void upload(AppException error) {}
}

/// debug 打印实现：把 `message` 和被映射掉的原始异常一起打出来。
///
/// 用 `kDebugMode` 而不是运行时判断：`kDebugMode` 是编译期常量，release 构建里
/// 整个分支会被 tree-shake 掉，既不留运行时开销也不留日志字符串。
class DebugErrorReporter implements ErrorReporter {
  const DebugErrorReporter();

  @override
  void log(AppException error) {
    if (!kDebugMode) return;
    debugPrint('[error] ${error.runtimeType}: ${error.message}');
    final cause = error.cause;
    // cause 是这一整套映射最容易丢掉的东西：用户只看到 message，排查要靠它。
    if (cause != null) debugPrint('  cause: $cause');
  }

  /// 刻意不实现：没有接入上报服务。
  ///
  /// 真要接 Sentry / Firebase 时，实现这一个方法就够了 —— 调用点一个都不用动，
  /// 只要在 DI 装配处把这个类换成新实现。
  @override
  void upload(AppException error) {}
}
