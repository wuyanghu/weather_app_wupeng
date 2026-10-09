import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/widgets/status_views.dart';
import '../providers/search_providers.dart';
import '../providers/weather_providers.dart';
import 'weather_cards.dart';
import 'weather_status_views.dart';

/// 天气内容区。没有选中地点时显示初始空态；搜索已开始但尚未选中地点时，
/// 搜索区自行承载 loading / 空结果 / 错误，避免与下方初始空态同时出现。
class WeatherSection extends ConsumerWidget {
  const WeatherSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weatherControllerProvider);
    final searchState = ref.watch(searchControllerProvider);

    return async.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (report) {
        if (report == null) {
          return searchState is SearchInitial
              ? const IdlePlaceholder()
              : const SizedBox.shrink();
        }
        return RefreshIndicator(
          onRefresh: () async =>
              ref.read(weatherControllerProvider.notifier).refresh(),
          child: WeatherContent(report: report),
        );
      },
      loading: () => const WeatherSkeleton(),
      error: (error, _) => ErrorRetryView(
        message: error is AppException ? error.message : '出了点问题，请稍后重试',
        onRetry: () => ref.read(weatherControllerProvider.notifier).refresh(),
      ),
    );
  }
}
