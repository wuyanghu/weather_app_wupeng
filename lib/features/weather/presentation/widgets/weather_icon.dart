import 'package:flutter/material.dart';

/// 天气图标映射。用 Material 图标而非图片资源，这样不必带任何资产文件；
/// 真实应用里会换成一套专门的图标集。
///
/// 独立于 `weather_cards.dart`：三张卡片都在用它，它不属于任何一张 ——
/// 可复用的东西埋在「cards」这种按页面命名的文件里，只有这一页找得到。
class WeatherIcon extends StatelessWidget {
  const WeatherIcon({
    super.key,
    required this.code,
    required this.isDay,
    this.size = 24,
  });

  final int code;
  final bool isDay;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final icon = switch (code) {
      0 => isDay ? Icons.wb_sunny_outlined : Icons.nightlight_round,
      1 || 2 => isDay ? Icons.wb_cloudy_outlined : Icons.cloud_outlined,
      3 => Icons.cloud_outlined,
      45 || 48 => Icons.foggy,
      51 || 53 || 55 || 56 || 57 || 80 || 81 => Icons.grain,
      61 || 63 || 65 || 66 || 67 => Icons.umbrella_outlined,
      71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
      82 => Icons.water_drop_outlined,
      95 || 96 || 99 => Icons.flash_on_outlined,
      _ => Icons.cloud_outlined,
    };
    return Icon(icon, size: size, color: color);
  }
}
