import 'package:flutter/material.dart';

/// 跨 feature 复用的状态视图。
///
/// 这里的判据不是「被用到几次」，而是**不认识任何业务**：[ErrorRetryView]
/// 只知道「一句话 + 一个重试回调」，天气、空气质量、任何一个新 feature 都能
/// 直接用，不需要改它一个字。认识业务的那部分（骨架屏的高度、空态的文案）
/// 留在各自 feature 的 `presentation/widgets/` 下。
///
/// 依赖 Flutter 是允许的 —— 纯 Dart 的约束在 `domain`，不在 `core`
/// （`core/theme/app_theme.dart` 同样 import material）。

/// 有空间时把内容居中，没有空间时*改为滚动*。
///
/// 矮屏上键盘弹起时，内容区可能只剩几个像素高 —— 单纯的
/// `Center(Column(...))` 在那里就会溢出（黄黑条纹，
/// "RenderFlex overflowed by N pixels"）。
class StatusScrollArea extends StatelessWidget {
  const StatusScrollArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.all(24);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 扣掉 padding 之后留给 child 的空间。做了 clamp，
        // 以免接近零高度的视口产生负的约束值。
        final available =
            (constraints.maxHeight - padding.vertical).clamp(0.0, double.infinity);
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: available),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// 错误态：带一个明确的重试入口。
///
/// 文案与回调都由调用方给，所以这个组件不认识「天气」——它只认识「失败了」。
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StatusScrollArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 64, color: theme.colorScheme.error.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
