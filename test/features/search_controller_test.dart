import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/core/errors/app_exception.dart';
import 'package:weather_app/features/weather/presentation/providers/di_providers.dart';
import 'package:weather_app/features/weather/presentation/providers/search_providers.dart';
import 'package:weather_app/features/weather/presentation/providers/selected_place_provider.dart';

import '../helpers/fixtures.dart';

/// 搜索是整个应用里活动部件最多的一块（防抖、取消、竞态防护、四种
/// UI 状态），因此分给它的测试也最多。
void main() {
  ProviderContainer containerWith(FakeWeatherRepository repo) {
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 阻塞到假实现被调用满 [n] 次。
  ///
  /// 这些测试跑在真实定时器上（300 ms 防抖，再加每次调用的延迟）；一旦套件
  /// 并行跑多个文件，那种「固定 sleep 到足够长」的写法会在定时器触发前就过期。
  /// 所以这里的每次等待都写明在等什么条件，而不是去猜它要多久。
  Future<void> callsSeen(FakeWeatherRepository repo, int n) async {
    for (var attempt = 0; attempt < 400; attempt++) {
      if (repo.searchCallCount >= n) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('expected $n search calls, saw ${repo.searchCallCount}');
  }

  /// 阻塞到状态机离开 [SearchLoading]。
  Future<void> resolved(ProviderContainer container) async {
    for (var attempt = 0; attempt < 400; attempt++) {
      if (container.read(searchControllerProvider) is! SearchLoading) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('state never left SearchLoading: '
        '${container.read(searchControllerProvider)}');
  }

  test('starts in the idle state', () {
    final container = containerWith(FakeWeatherRepository());
    expect(container.read(searchControllerProvider), isA<SearchInitial>());
  });

  test('debounces rapid typing into a single request', () async {
    final repo = FakeWeatherRepository(places: [placeFixture()]);
    final container = containerWith(repo);

    final controller = container.read(searchControllerProvider.notifier);
    controller.onQueryChanged('h');
    controller.onQueryChanged('ha');
    controller.onQueryChanged('han');
    controller.onQueryChanged('hang');

    await callsSeen(repo, 1);
    await resolved(container);

    expect(repo.searchCallCount, 1);
    expect(repo.searchQueries.single, 'hang');
    expect(container.read(searchControllerProvider), isA<SearchSuccess>());
  });

  test('clearing the query returns to idle without a request', () async {
    final repo = FakeWeatherRepository(places: [placeFixture()]);
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('hang');
    await callsSeen(repo, 1);
    await resolved(container);
    controller.onQueryChanged('');

    expect(container.read(searchControllerProvider), isA<SearchInitial>());
    expect(repo.searchCallCount, 1);
  });

  test('exposes an empty state (not an error) when nothing matches', () async {
    final repo = FakeWeatherRepository(places: const []);
    final container = containerWith(repo);

    container.read(searchControllerProvider.notifier).onQueryChanged('zzzz');
    await callsSeen(repo, 1);
    await resolved(container);

    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchEmpty>());
    expect((state as SearchEmpty).query, 'zzzz');
  });

  test('surfaces transport failures as SearchError with a message', () async {
    final repo = FakeWeatherRepository(
      searchError: const NetworkException(),
    );
    final container = containerWith(repo);

    container.read(searchControllerProvider.notifier).onQueryChanged('杭州');
    await callsSeen(repo, 1);
    await resolved(container);

    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchError>());
    expect((state as SearchError).exception.message, isNotEmpty);
    // 失败的那次查询必须留在 state 里 —— 否则「错误可重试」这句话无处安放。
    expect(state.query, '杭州');
  });

  test('retry re-runs the query that failed', () async {
    final repo = FakeWeatherRepository(
      searchError: const NetworkException(),
    );
    final container = containerWith(repo);

    container.read(searchControllerProvider.notifier).onQueryChanged('杭州');
    await callsSeen(repo, 1);
    await resolved(container);
    expect(container.read(searchControllerProvider), isA<SearchError>());

    container.read(searchControllerProvider.notifier).retry();
    await callsSeen(repo, 2);
    await resolved(container);

    // 重发的是**失败那次**的查询，不是输入框当前的文本。
    expect(repo.searchQueries.last, '杭州');
  });

  test('retry does nothing unless the state is an error', () async {
    final repo = FakeWeatherRepository();
    final container = containerWith(repo);

    container.read(searchControllerProvider.notifier).retry();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(repo.searchCallCount, 0);
  });

  test('ignores a stale response that arrives after a newer one', () async {
    // 第一次调用很慢，返回杭州；第二次很快，返回上海。
    final repo = FakeWeatherRepository(
      callDelays: const [Duration(milliseconds: 200), Duration.zero],
      resultsByCall: [
        [placeFixture(id: 1, name: '杭州')],
        [placeFixture(id: 2, name: '上海')],
      ],
    );
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('杭州');
    await callsSeen(repo, 1);
    controller.onQueryChanged('上海');
    await callsSeen(repo, 2);
    await resolved(container);

    expect(repo.searchCallCount, 2);
    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchSuccess>());
    // 必须以较晚那次查询的结果为准，而不是更早但更慢的那次。
    expect((state as SearchSuccess).places.single.name, '上海');
  });

  test('cancels the superseded request rather than only ignoring it',
      () async {
    // 只靠 generation 计数做防护，丢弃的只是过期的*结果*：请求仍会跑到结束、
    // 字节仍会到达。没人察觉，因为无法观察取消的假实现也不可能失败。
    final repo = FakeWeatherRepository(
      places: [placeFixture()],
      searchDelay: const Duration(milliseconds: 800),
    );
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('hang');
    await callsSeen(repo, 1); // #0 号请求正在途中
    controller.onQueryChanged('shang');
    await callsSeen(repo, 2); // 因此 #1 启动时 #0 必须已被中止
    expect(repo.cancelSignals.first.isCancelled, isTrue);
    await resolved(container);

    expect(repo.cancelSignals.last.isCancelled, isFalse);
    // 被取消不能以失败的形式暴露给用户。
    expect(container.read(searchControllerProvider), isA<SearchSuccess>());
  });

  test('invalidates and cancels the old request before the next debounce ends',
      () async {
    final repo = FakeWeatherRepository(
      places: [placeFixture()],
      searchDelay: const Duration(milliseconds: 800),
    );
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('hang');
    await callsSeen(repo, 1);
    controller.onQueryChanged('shang');

    // 不能等到下一次请求启动才取消：那会留下一个 300ms 的陈旧结果窗口。
    expect(repo.cancelSignals.single.isCancelled, isTrue);
    expect(container.read(searchControllerProvider), isA<SearchLoading>());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(repo.searchCallCount, 1);

    await callsSeen(repo, 2);
    await resolved(container);
    expect(container.read(searchControllerProvider), isA<SearchSuccess>());
  });

  test('a repository crash degrades to an error instead of a spinner',
      () async {
    // 「只抛 AppException」这条约定不由编译器强制：碰到它没捕获的抛出时，
    // 搜索框就曾永久停在 SearchLoading —— 对一个全部职责就是始终抵达*某个*
    // 状态的状态机来说，这是最坏的失败方式。
    final repo = FakeWeatherRepository(searchCrash: StateError('boom'));
    final container = containerWith(repo);

    container.read(searchControllerProvider.notifier).onQueryChanged('hang');
    await callsSeen(repo, 1);
    await resolved(container);

    final state = container.read(searchControllerProvider);
    expect(state, isA<SearchError>());
    expect((state as SearchError).exception.cause, isA<StateError>());
  });

  test('selectPlace commits the place and resets the search UI', () async {
    final repo = FakeWeatherRepository(places: [placeFixture()]);
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('hang');
    await callsSeen(repo, 1);
    await resolved(container);
    expect(container.read(searchControllerProvider), isA<SearchSuccess>());

    final place = placeFixture();
    controller.selectPlace(place);

    // 两半都属于 controller：既要重置结果列表，*也*要提交当前生效的地点。
    // 拆成两次调用（视图侧先写 provider，再 reset）时，顺序只是一条隐式约定，
    // 漏掉任一行都会产生另一个不同的静默 bug。
    expect(container.read(searchControllerProvider), isA<SearchInitial>());
    expect(container.read(selectedPlaceProvider), same(place));
  });

  test('selectPlace discards an in-flight search', () async {
    final repo = FakeWeatherRepository(
      places: [placeFixture()],
      searchDelay: const Duration(milliseconds: 600),
    );
    final container = containerWith(repo);
    final controller = container.read(searchControllerProvider.notifier);

    controller.onQueryChanged('hang');
    await callsSeen(repo, 1); // 此时请求已在途中
    controller.selectPlace(placeFixture());

    // 断言的是变化的*缺失*，所以这里的等待是有意为之：给被中止的请求充分的
    // 机会，让它把结果列表复活。
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(container.read(searchControllerProvider), isA<SearchInitial>());
  });
}
