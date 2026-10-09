import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/core/errors/app_exception.dart';
import 'package:weather_app/features/weather/presentation/providers/di_providers.dart';
import 'package:weather_app/main.dart';

import '../helpers/fixtures.dart';

/// 近似端到端的流程测试：在真实 widget 树上跑，repository 用编排好的假实现。
/// 覆盖用户可见的状态：空闲 → 搜索中 → 结果 → 天气详情，
/// 以及出错 → 重试这条路径。
void main() {
  Future<void> pumpApp(WidgetTester tester, FakeWeatherRepository repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [weatherRepositoryProvider.overrideWithValue(repo)],
        child: const WeatherApp(),
      ),
    );
    await tester.pump();
  }

  /// 等过 300 ms 的搜索防抖，并让微任务跑完。
  Future<void> settleSearch(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  /// 把测试视口压窄，模拟键盘弹出的手机——内容区可能只剩几像素高。
  void useShortViewport(WidgetTester tester, {double height = 140}) {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the idle placeholder before anything is searched', (
    tester,
  ) async {
    await pumpApp(tester, FakeWeatherRepository());
    expect(find.text('搜索一个地点查看天气'), findsOneWidget);
  });

  testWidgets('search → select → renders current weather and forecast', (
    tester,
  ) async {
    final place = placeFixture();
    final repo = FakeWeatherRepository(
      places: [place],
      report: reportFixture(place: place, temperature: 24.5),
    );
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '杭州');
    await settleSearch(tester);

    // 结果行（裸用 `find.text` 会连 TextField 一起匹配到）。
    expect(find.widgetWithText(ListTile, '杭州'), findsOneWidget);
    // 副标题展示位置信息，不重复标题里的地名。
    expect(find.text('浙江省, 中国'), findsOneWidget);
    expect(find.text('省会'), findsOneWidget); // 类别徽章
    expect(find.text('搜索一个地点查看天气'), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, '杭州'));
    await settleSearch(tester);

    // 当前天气卡片。
    expect(find.text('25°'), findsOneWidget); // 24.5 四舍五入为 25
    expect(find.text('未来 24 小时'), findsOneWidget);
    expect(find.text('未来 7 天'), findsOneWidget);
    expect(repo.weatherCallCount, 1);
  });

  testWidgets('shows the empty-search hint when nothing matches', (
    tester,
  ) async {
    await pumpApp(tester, FakeWeatherRepository(places: const []));

    await tester.enterText(find.byType(TextField), 'zzzzzz');
    await settleSearch(tester);

    expect(find.textContaining('没有找到'), findsOneWidget);
  });

  testWidgets('weather failure shows a message and retry re-fetches', (
    tester,
  ) async {
    final repo = FakeWeatherRepository(
      places: [placeFixture()],
      weatherError: const NetworkException(),
    );
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '杭州');
    await settleSearch(tester);
    await tester.tap(find.widgetWithText(ListTile, '杭州'));
    await settleSearch(tester);

    expect(find.text('网络连接不可用，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 恢复：这次重试会成功。
    repo
      ..weatherError = null
      ..report = reportFixture();
    await tester.tap(find.text('重试'));
    await settleSearch(tester);

    expect(repo.weatherCallCount, 2);
    expect(find.text('未来 7 天'), findsOneWidget);
  });

  testWidgets('a failed search offers retry and re-runs the same query', (
    tester,
  ) async {
    final repo = FakeWeatherRepository(searchError: const NetworkException());
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '杭州');
    await settleSearch(tester);

    expect(find.text('网络连接不可用，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 恢复网络后，重试应当重发**失败的那次**查询。
    repo.searchError = null;
    await tester.tap(find.text('重试'));
    await settleSearch(tester);

    expect(repo.searchQueries, ['杭州', '杭州']);
    // 这次返回空结果而不是错误 —— 说明重试走通了，不是又报错。
    expect(find.textContaining('没有找到'), findsOneWidget);
  });

  testWidgets('idle placeholder does not overflow a very short viewport', (
    tester,
  ) async {
    // 回归测试：键盘弹出时内容区可能只剩几像素高；固定高度的 Column
    // 会被渲染成黄黑相间的条纹。
    useShortViewport(tester);
    await pumpApp(tester, FakeWeatherRepository());

    expect(tester.takeException(), isNull);
  });

  testWidgets('error view does not overflow a very short viewport', (
    tester,
  ) async {
    final repo = FakeWeatherRepository(
      places: [placeFixture()],
      weatherError: const NetworkException(),
    );
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '杭州');
    await settleSearch(tester);
    await tester.tap(find.widgetWithText(ListTile, '杭州'));
    await settleSearch(tester);

    expect(find.text('重试'), findsOneWidget);

    // 此时用户再次点击输入框：键盘把 viewport 压得只剩一线。
    // 错误视图必须优雅降级，而不是出现黄黑条纹。
    useShortViewport(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('search results carry a kind badge so look-alikes are '
      'dismissable at a glance', (tester) async {
    final repo = FakeWeatherRepository(
      places: [
        placeFixture(
          id: 1,
          name: '深圳',
          admin1: '广东',
          featureCode: 'PPLA2',
          population: 17494398,
        ),
        placeFixture(id: 2, name: '深圳', admin1: '福建省', featureCode: 'PPL'),
      ],
    );
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '深圳');
    await settleSearch(tester);

    expect(find.text('地级市'), findsOneWidget);
    expect(find.text('村镇'), findsOneWidget);
  });

  testWidgets('the clear button tracks the field text', (tester) async {
    // 后缀图标由监听 controller 的 ValueListenableBuilder 驱动，
    // 所以用户输入时这一块的其余部分不需要重建。
    await pumpApp(tester, FakeWeatherRepository());
    expect(find.byIcon(Icons.close), findsNothing);

    await tester.enterText(find.byType(TextField), '杭州');
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('搜索一个地点查看天气'), findsOneWidget);
  });

  testWidgets('a long result list cannot squeeze the weather area to zero', (
    tester,
  ) async {
    // 回归测试：结果列表是非 flexible 的 Column 子节点，
    // 所以过去 10 条命中就会吃满整屏，把内容区撑到溢出。
    final repo = FakeWeatherRepository(
      places: [for (var i = 0; i < 10; i++) placeFixture(id: i, name: '城市$i')],
    );
    await pumpApp(tester, repo);

    await tester.enterText(find.byType(TextField), '城市');
    await settleSearch(tester);

    expect(tester.takeException(), isNull);
    // 搜索结果出现后，初始空态必须隐藏，避免两种状态同时呈现。
    expect(find.text('搜索一个地点查看天气'), findsNothing);
  });
}
