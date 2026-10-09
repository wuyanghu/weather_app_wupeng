/// 从 JSON 里取值的工具：**只回答「有没有」，不替调用方编一个值**。
///
/// 早先这里有 `toInt(v, [fallback = 0])` 这种带默认值的版本，结果数值字段缺了
/// 就悄悄变成 0 —— 而 0 在天气语义里全是真值（WMO 0 = 晴天、0° = 零度、
/// 0 mm = 没下雨）。那不是容错，是用**合法值表达缺失**：界面一个字都不少，
/// 只是那一格是假的，而且看不出来。
///
/// 所以现在只留 `…OrNull` 一族：拿不到就返回 null，由调用方（转换层）决定
/// 「这一项不要了」还是「这条数据不成立」。**工具本身不具备把缺失变成合法值
/// 的能力** —— 和 `guarded()` 一个思路：与其写注释说"别这么干"，不如让这个
/// 类根本干不了。
///
/// 住在 core 而不是 DTO 文件里当私有类，是因为它与业务无关：JSON 取值该不该
/// 容错，是解析层的通用判断，不是天气的知识。
class Json {
  const Json._();

  static int? toIntOrNull(Object? v) => (v is num) ? v.toInt() : null;

  static double? toDoubleOrNull(Object? v) => (v is num) ? v.toDouble() : null;

  /// Open-Meteo 的 `is_day` 是 0 / 1 —— 缺失时返回 null，而不是当成"夜间"。
  static bool? toBoolOrNull(Object? v) => (v is num) ? v == 1 : null;
}
