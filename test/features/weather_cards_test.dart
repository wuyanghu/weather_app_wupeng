import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/core/utils/formatters.dart';
import 'package:weather_app/features/weather/presentation/widgets/weather_cards.dart';

import '../helpers/fixtures.dart';

/// 消费层的防御性测试。
///
/// 前 48 个测试覆盖的是「正常路径 + 已知竞态」，缺的是**降级路径**：
/// 数据层会逐字段降级，降出来的空数组流到 UI 会怎样，没人钉住。
void main() {
  Future<void> pumpDailyList(
    WidgetTester tester, {
    required int dailyCount,
  }) async {
    final report = reportFixture(dailyCount: dailyCount);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyList(days: report.daily, currentTime: report.currentTime),
        ),
      ),
    );
  }

  testWidgets('日报为空时给出空态，而不是 reduce 抛 StateError', (tester) async {
    await pumpDailyList(tester, dailyCount: 0);

    // flutter_test 会把未处理的构建异常留到测试结束时才报错，这里显式取一次，
    // 让"没崩"成为断言本身，而不是"没报错就当通过了"。
    expect(tester.takeException(), isNull);
    expect(find.text('未来 7 天 · 暂无逐日预报'), findsOneWidget);
  });

  testWidgets('日报非空时照常渲染，首行是今天', (tester) async {
    await pumpDailyList(tester, dailyCount: 7);

    expect(tester.takeException(), isNull);
    expect(find.text('未来 7 天'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
  });

  test('"今天"以传入的现在为基准，不看设备时钟', () {
    // 2024-03-15 是周五，次日是周六。
    final friday = DateTime(2024, 3, 15);
    final saturday = DateTime(2024, 3, 16);

    expect(Formatters.weekday(friday, friday), '今天');
    expect(Formatters.weekday(saturday, friday), '周六');

    // 关键的一条：同一个日期，换一个"现在"，结论必须跟着变。
    // 修复前 weekday 读的是 DateTime.now()，这两行会直接失败。
    expect(Formatters.weekday(saturday, saturday), '今天');
    expect(Formatters.weekday(friday, saturday), '周五');
  });
}
