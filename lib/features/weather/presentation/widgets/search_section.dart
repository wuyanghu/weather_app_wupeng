import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/place.dart';
import '../../domain/place_kind.dart';
import '../providers/search_providers.dart';

/// 搜索输入框 + 结果列表 / 内联状态。
///
/// 所有分支都挂在 [SearchState] 这个 sealed class 上——编译器会强制
/// 每个状态都被处理，这正是用 sealed class 而不是
/// 「一个 isLoading 布尔 + 一个可空列表」的核心理由。
class SearchSection extends ConsumerStatefulWidget {
  const SearchSection({super.key, required this.onPlaceSelected});

  final ValueChanged<Place> onPlaceSelected;

  @override
  ConsumerState<SearchSection> createState() => _SearchSectionState();
}

// 之所以是有状态的，只是为了持有输入框的 controller 和 focus node；
class _SearchSectionState extends ConsumerState<SearchSection> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      ref
          .read(searchControllerProvider.notifier)
          .onQueryChanged(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        // HomeScreen 会给这个槽位设上限；结果列表只占所给高度的一部分，
        // 以保证下方的天气区域始终留有空间。
        final listCap = constraints.maxHeight.isFinite
            ? constraints.maxHeight * 0.7
            : MediaQuery.sizeOf(context).height * 0.4;
        // 做成可滚动的：视口被键盘挤压时退化为滚动，
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 清除按钮是这里唯一依赖文本内容的东西
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索城市，如：杭州、Tokyo…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              _controller.clear();
                              _focus.requestFocus();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: switch (state) {
                  SearchInitial() => const SizedBox.shrink(),
                  SearchLoading() => const _InlineHint(
                    key: ValueKey('loading'),
                    icon: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: '正在搜索…',
                  ),
                  SearchEmpty(:final query) => _InlineHint(
                    key: const ValueKey('empty'),
                    icon: const Icon(Icons.search_off, size: 18),
                    label: '没有找到「$query」相关地点',
                  ),
                  SearchError(:final exception) => _InlineHint(
                    key: const ValueKey('error'),
                    icon: const Icon(Icons.wifi_off, size: 18),
                    label: exception.message,
                    onRetry: () =>
                        ref.read(searchControllerProvider.notifier).retry(),
                  ),
                  SearchSuccess(:final places) => _ResultList(
                    key: const ValueKey('results'),
                    places: places,
                    maxHeight: listCap,
                    onSelected: widget.onPlaceSelected,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// 排序后的命中项，以可点击的行呈现在一张卡片里。
class _ResultList extends StatelessWidget {
  const _ResultList({
    super.key,
    required this.places,
    required this.maxHeight,
    required this.onSelected,
  });

  final List<Place> places;

  /// [SearchSection] 传下来的高度预算；列表只在这份预算内部滚动，
  /// 因此命中项再多也不会把天气区挤压到零。
  final double maxHeight;

  final ValueChanged<Place> onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: places.length,
          itemBuilder: (context, i) {
            final place = places[i];
            return Column(
              children: [
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  // 全局的 ListTile 主题把 contentPadding 置零
                  // （对通栏行来说没问题）；但在卡片里文字会贴到边缘，
                  // 所以要恢复它——divider 的 16px 缩进也就和文字对齐了。
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    place.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: place.locationLabel.isEmpty
                      ? null
                      : Text(
                          place.locationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 「地级市」/「村镇」——正是它让同名的命中结果
                      // 一眼就能被排除掉。
                      if (place.kind.hasLabel) ...[
                        _KindBadge(kind: place.kind),
                        const SizedBox(width: 6),
                      ],
                      const Icon(Icons.north_west, size: 16),
                    ],
                  ),
                  onTap: () => onSelected(place),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// 一个小胶囊，标出某个地点的行政级别（PlaceKind.label）。
class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final PlaceKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind.label,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

// 图标 + 一行截断文字，加载 / 无结果 / 出错时显示在输入框下方。
class _InlineHint extends StatelessWidget {
  const _InlineHint({
    super.key,
    required this.icon,
    required this.label,
    this.onRetry,
  });

  final Widget icon;
  final String label;

  /// 非空时在右侧渲染一个「重试」入口 —— 错误提示要给出下一步动作。
  /// 它只占一行，代价几乎为零。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              // 内联提示只有一行高，按钮必须 shrinkWrap，否则会把这一行撑成
              // 两倍并触发溢出。
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}
