import 'package:flutter/material.dart';

import '../../../../core/widgets/status_views.dart';

/// 天气内容区自己那两个状态视图。
///
/// 留在这里而不是下沉 `core/` 的理由，是它们**认识天气**：
///  * [IdlePlaceholder] 的文案写死了「查看天气」；
///  * [WeatherSkeleton] 三块占位方块的高度，是照着三张天气卡的实际高度摆的
///    —— 换个 feature 这个布局就对不上了。
/// 真正通用的那个（[ErrorRetryView]）在 `core/widgets/status_views.dart`。

/// 空态：还没有搜索或选中任何地点。
class IdlePlaceholder extends StatelessWidget {
  const IdlePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StatusScrollArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.travel_explore,
              size: 72, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('搜索一个地点查看天气', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '支持全球城市搜索，数据来自 Open-Meteo',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// 加载骨架——三块占位方块，与内容布局对位，
/// 这样数据到位时页面不会跳动。
class WeatherSkeleton extends StatelessWidget {
  const WeatherSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _block(context, height: 160),
        const SizedBox(height: 12),
        _block(context, height: 110),
        const SizedBox(height: 12),
        _block(context, height: 220),
      ],
    );
  }

  Widget _block(BuildContext context, {required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
