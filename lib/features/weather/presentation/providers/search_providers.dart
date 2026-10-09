import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cancel_signal.dart';
import '../../../../core/errors/app_exception.dart';
import '../../domain/place.dart';
import '../../domain/weather_repository.dart';
import 'di_providers.dart';
import 'selected_place_provider.dart';

/// 搜索框的各个状态。`initial` 渲染落地提示
sealed class SearchState {
  const SearchState();
}

// 尚未执行过查询：渲染落地提示，而不是空列表。
class SearchInitial extends SearchState {
  const SearchInitial();
}

// 有查询正在进行；输入的文本留在 controller 里，不进 state。
class SearchLoading extends SearchState {
  const SearchLoading();
}

// 已有匹配项，repository 已完成排序、标注与去重。
class SearchSuccess extends SearchState {
  const SearchSuccess(this.places);
  final List<Place> places;
}

// 请求成功但什么都没匹配到 —— 有意不算错误。
class SearchEmpty extends SearchState {
  const SearchEmpty(this.query);
  final String query;
}

// 请求本身失败；携带面向用户的失败原因，以及**失败的那次查询** ——
// 重试按钮要靠它知道重发什么。
class SearchError extends SearchState {
  const SearchError(this.exception, this.query);

  final AppException exception;
  final String query;
}

/// 搜索 controller：300 ms 防抖 + 中止被取代的请求。少了这两样就是竞态：
/// 敲 "hangzhou" 会发出 8 个请求，还可能把更早前缀的结果盖在更晚的那次之上。
class SearchController extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchInitial();

  WeatherRepository get _repo => ref.read(weatherRepositoryProvider);

  Timer? _debounce;
  CancelSignal? _inFlight;
  int _generation = 0;

  void onQueryChanged(String query) {
    _debounce?.cancel();
    // 防抖只应该推迟「发新请求」，不能推迟「旧输入已经失效」这件事。否则
    // 用户改字后的 300ms 内，旧请求仍可能返回并把不属于当前输入的结果写回
    // 界面。先递增代际并取消在途请求，再等待新的输入稳定下来。
    _abortInFlight();
    if (query.trim().isEmpty) {
      state = const SearchInitial();
      return;
    }
    // 旧结果不能在新的查询等待防抖时继续留在屏幕上；这里也给用户即时反馈，
    // 而真正的网络请求仍由下面的 300ms timer 合并。
    state = const SearchLoading();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    final gen = ++_generation;
    _inFlight?.cancel(); // 不再为一个没人会渲染的结果继续付费
    final signal = CancelSignal();
    _inFlight = signal;
    state = const SearchLoading();
    try {
      final places = await _repo.searchPlaces(query, cancel: signal);
      // 只有最新的那次查询才允许更新 UI。
      if (gen != _generation) return;
      state = places.isEmpty ? SearchEmpty(query) : SearchSuccess(places);
    } on CancelledException {
      // 我们自己的取消：更新的查询已经接管 UI，所以保持静默。
    } on AppException catch (e) {
      if (gen != _generation) return;
      state = SearchError(e, query);
    } catch (e) {
      // repository 可以完全不守约定（这个契约不由编译器强制）。落到
      // 这里若不改变 state，搜索框会永远卡在加载转圈上，因此降级为可
      // 重试的错误状态。
      if (gen != _generation) return;
      state = SearchError(NetworkException(cause: e), query);
    } finally {
      if (identical(_inFlight, signal)) _inFlight = null;
    }
  }

  /// 重发 [SearchError] 携带的那次查询。
  ///
  /// 重试是幂等的：只把同一个 query 再走一遍 [_search]，不碰输入框文本，也不
  /// 动 generation 以外的任何状态 —— 所以它可以被点很多次。
  ///
  /// 从 state 里取 query，而不是让 UI 把文本传回来：重试重的是**失败的那次**
  /// 查询，不是输入框当前的内容（用户可能已经改了字）。
  void retry() {
    final current = state;
    if (current is! SearchError) return;
    if (current.query.trim().isEmpty) return;
    _search(current.query);
  }

  /// 递增 generation 计数**并**中止进行中的请求，这两步永远一起发生 ——
  /// 少做任何一半，都会留下一条随时可能被渲染的过期响应。
  void _abortInFlight() {
    _generation++;
    _inFlight?.cancel();
    _inFlight = null;
  }

  /// 把 [place] 提交为当前生效的地点**并**清空搜索 UI。
  ///
  /// 合成一个方法，而不是「写 `selectedPlaceProvider`、再单独 reset」：拆成
  /// 两次调用时，顺序只是一条隐式契约，漏掉任一行都会引出另一个不同的静默
  /// bug —— 要么结果列表挂在屏上不走，要么点一下看着什么都没发生。
  void selectPlace(Place place) {
    _debounce?.cancel();
    _abortInFlight();
    ref.read(selectedPlaceProvider.notifier).state = place;
    state = const SearchInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inFlight?.cancel();
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
