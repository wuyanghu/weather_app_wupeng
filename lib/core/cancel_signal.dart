import 'dart:async';

/// 取消单个在途请求。
///
/// 这份契约刻意不暴露 HTTP 库的类型：[CancelSignal] 是纯 Dart，domain 层
/// 因此不用 import Dio；由 data 层把它映射成所用客户端的取消机制。
///
/// 住在 `core/` 而不是某个 feature 的 `domain/` 下：它**不认识业务** ——
/// 取消就是取消，跟这条请求是查天气还是查地点无关。放在 domain 里也行，但
/// 那样 domain 就得自带一个与业务无关的工具类；放 core 更贴它的性质。
class CancelSignal {
  CancelSignal();

  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  /// 只完成一次：在 [cancel] 被调用时。
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _completer.complete();
  }
}
