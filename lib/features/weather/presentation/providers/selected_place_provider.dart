import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/place.dart';

/// 当前选中的地点；用户点中某条搜索结果之前都是 `null`。
///
/// 它是两套状态机之间唯一的中转：搜索侧写入，天气侧 `ref.watch`。
/// 现在只有天气一个消费方，所以它跟天气住在一起；等出现第二个消费方时，
/// 它就该搬到 `features/shared/` 下 —— 那时搬，成本只是移动一个文件。
final selectedPlaceProvider = StateProvider<Place?>((ref) => null);
