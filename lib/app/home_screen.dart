import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/weather/presentation/providers/search_providers.dart';
import '../features/weather/presentation/widgets/search_section.dart';
import '../features/weather/presentation/widgets/weather_section.dart';

/// 单屏应用：上方搜索，下方天气内容。
///
/// 放在 `lib/app/` 而不是任何一个 feature 下，因为它**不属于天气** ——
/// 它是把各个 feature 提供的区块拼起来的壳。加空气质量时，这里多一行
/// `AirQualitySection()`，天气那边一个文件都不用动；反过来，如果它住在
/// `features/weather/` 里，新 feature 就得 import weather 才能组装页面。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('天气')),
      body: SafeArea(
        // 用 LayoutBuilder，才能按真实 body 高度给搜索区设上限。
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.6,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SearchSection(
                      onPlaceSelected: (place) {
                        FocusScope.of(context).unfocus();
                        ref
                            .read(searchControllerProvider.notifier)
                            .selectPlace(place);
                      },
                    ),
                  ),
                ),
                const Expanded(child: WeatherSection()),
              ],
            );
          },
        ),
      ),
    );
  }
}
