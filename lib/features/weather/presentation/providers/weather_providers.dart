import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/weather_models.dart';
import 'di_providers.dart';
import 'selected_place_provider.dart';

/// 选中的地点一变，就自动重建（重新拉取）。
///
/// 这个值**有意可空**：`null` 表示「还没有选中地点」，它是一个*空*状态，不是
/// 失败。把这一点编码进类型，`error` 分支就只留给真正的错误 —— UI 无需靠辨认
/// 某个魔法异常，就能避免把「什么都没选」渲染成崩溃。
///
/// `AsyncValue` 照样提供 loading / data / error，外加「data + 刷新中」（靠 UI
/// 侧的 skipLoadingOnRefresh）；重试也只是
/// `ref.invalidate(weatherControllerProvider)`。
class WeatherController extends AsyncNotifier<WeatherReport?> {
  @override
  Future<WeatherReport?> build() async {
    final place = ref.watch(selectedPlaceProvider);
    // 空闲：还没有选中地点。这不是错误 —— UI 针对这种情况显示落地占位。
    if (place == null) return null;

    final repo = ref.watch(weatherRepositoryProvider);
    // repository 的约定是只抛出 AppException 的子类。
    return repo.fetchWeather(place);
  }

  /// 手动下拉 / 按钮刷新。走 invalidate 是为了在重新加载期间保留上一份数据
  /// （底层即 AsyncValue.copyWithPrevious）。
  void refresh() => ref.invalidateSelf();
}

final weatherControllerProvider =
    AsyncNotifierProvider<WeatherController, WeatherReport?>(
  WeatherController.new,
);
