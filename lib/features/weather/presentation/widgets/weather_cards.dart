import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/weather_models.dart';
import '../../domain/weather_code.dart';
import 'weather_icon.dart';

/// 三张内容卡片。纯展示：传入实体、渲染数值——没有 provider、没有请求，
/// 因此随手就能单独预览。

/// 把已加载的 report 组装成可滚动的页面主体。
class WeatherContent extends StatelessWidget {
  const WeatherContent({super.key, required this.report});

  final WeatherReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        CurrentWeatherCard(report: report),
        const SizedBox(height: 12),
        HourlyStrip(hours: report.hourly),
        const SizedBox(height: 12),
        DailyList(days: report.daily, currentTime: report.currentTime),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '数据来源：Open-Meteo · 下拉可刷新',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

// 主卡片：地名、实测温度以及四项指标。
class CurrentWeatherCard extends StatelessWidget {
  const CurrentWeatherCard({super.key, required this.report});

  final WeatherReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = report.current;
    // 这四项都是可选字段，缺了就少画一格 —— 见 [_metricsOf]。
    final metrics = _metricsOf(c);
    return Card(
      // margin 设为零：ListView 本身已带 16px 的页面 padding，
      // 因此每张卡片都能与上方的搜索区对齐。
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(report.place.displayName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '更新于 ${Formatters.hhmm(report.currentTime)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.temperature.round()}°',
                  style: theme.textTheme.displayLarge
                      ?.copyWith(fontWeight: FontWeight.w300),
                ),
                const Spacer(),
                WeatherIcon(code: c.weatherCode, isDay: c.isDay, size: 56),
              ],
            ),
            const SizedBox(height: 4),
            Text(c.weatherCode.description,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            if (metrics.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: metrics,
              ),
          ],
        ),
      ),
    );
  }
}

/// 当前天气那一行指标（体感 / 湿度 / 风速 / 降水）。
///
/// **接口没给的项直接不画**，而不是画一个 0。降人格外典型：`0.0 mm` 看起来
/// 完全正常，用户会当成"实测没下雨"，而实际可能是"这一项根本没测" —— 那不是
/// 显示错了，是界面陈述了一件它并不知道的事。少一格，胜过一格假的。
List<Widget> _metricsOf(CurrentWeather c) => [
      if (c.apparentTemperature case final v?)
        _Metric(label: '体感', value: '${v.round()}°'),
      if (c.humidity case final v?) _Metric(label: '湿度', value: '$v%'),
      if (c.windSpeed case final v?)
        _Metric(label: '风速', value: '${v.toStringAsFixed(0)} km/h'),
      if (c.precipitation case final v?)
        _Metric(label: '降水', value: '${v.toStringAsFixed(1)} mm'),
    ];

// 指标行里的一组「标签在上、数值在下」的组合（体感 / 湿度 / 风速 / 降水）。
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            )),
        const SizedBox(height: 2),
        Text(value,
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// 小时条：横向滚动，展示未来 24 小时。
class HourlyStrip extends StatelessWidget {
  const HourlyStrip({super.key, required this.hours});

  final List<HourlyWeather> hours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('未来 24 小时',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: hours.length,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (context, i) {
                  final h = hours[i];
                  final isNow = i == 0;
                  // 降水概率是可选字段（部分地区 / 部分模型不给）。没有时写
                  // '—' 而不是 0%：0% 是一个会误导的合法值，'—' 明确是
                  // "这一项没有数据"。
                  final probability = h.precipitationProbability;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isNow ? '现在' : Formatters.hhmm(h.time),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: isNow ? FontWeight.w700 : null,
                        ),
                      ),
                      WeatherIcon(code: h.weatherCode, isDay: true, size: 24),
                      Text(
                        '${h.temperature.round()}°',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        probability == null ? '—' : '$probability%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: probability != null && probability >= 30
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 7 天列表：每行带一根温度区间条。
class DailyList extends StatelessWidget {
  const DailyList({
    super.key,
    required this.days,
    required this.currentTime,
  });

  final List<DailyWeather> days;

  /// 服务端返回的当地时间，用来判断哪一天是"今天"。见 [Formatters.weekday]。
  final DateTime currentTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 数据层对缺失字段是逐项降级的（sized() 对齐数组长度、坏掉的时间戳
    // 跳过而不是让整段解析失败），因此 daily 整段为空是*合法的降级结果*。
    // 这里必须拦住：reduce 在空列表上会抛 StateError，把"少了逐日预报"
    // 升级成"整页崩溃"——正好和降级策略相反。防御做在了数据层，就不能
    // 漏在消费层。
    if (days.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Text(
            '未来 7 天 · 暂无逐日预报',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    final weekMin =
        days.map((d) => d.temperatureMin).reduce((a, b) => a < b ? a : b);
    final weekMax =
        days.map((d) => d.temperatureMax).reduce((a, b) => a > b ? a : b);
    final span = (weekMax - weekMin).abs().clamp(1, double.infinity);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text('未来 7 天',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        Formatters.weekday(d.date, currentTime),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    WeatherIcon(code: d.weatherCode, isDay: true, size: 22),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 3,
                      child: Text(d.weatherCode.description,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        // 同逐时：降水概率是可选字段，没有就写 '—' 而不是 0%。
                        switch (d.precipitationProbability) {
                          final p? => '$p%',
                          _ => '—',
                        },
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${d.temperatureMin.round()}°',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        )),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: LayoutBuilder(builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        return Stack(
                          children: [
                            Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Positioned(
                              left: w * (d.temperatureMin - weekMin) / span,
                              width: w * (d.temperatureMax - d.temperatureMin) / span,
                              child: Container(
                                height: 5,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [
                                    Color(0xFF6FB4F5),
                                    Color(0xFFF5B45A),
                                  ]),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(width: 6),
                    Text('${d.temperatureMax.round()}°',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

