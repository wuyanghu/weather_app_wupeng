/// 地理编码命中项的分类，取自 Open-Meteo 透传的 GeoNames `feature_code`
/// —— 深圳 是 `PPLA2`，同名的村落是 `PPL`，机场是 `AIRP`。
///
/// 两个用途：
///  * [rank] 给结果排序，让用户真正想搜的那个命中浮到同名村落、机场之上；
///  * [label] 说明这一行*是什么*，同名命中因此一眼就能排除（地理编码会
///    毫不犹豫地返回三个 深圳）。
enum PlaceKind {
  capital(0, '首都'),
  specialRegion(1, '特别行政区'),
  provinceSeat(2, '省会'),
  city(3, '地级市'),
  district(4, '区县'),
  village(5, '村镇'),
  area(6, '行政区域'),
  other(7, '');

  const PlaceKind(this.rank, this.label);

  /// 值越小，在结果列表里排得越靠前。
  final int rank;

  /// 展示用的类别名；挂上徽章只会添噪而不给信息的类别留空。
  final String label;

  bool get hasLabel => label.isNotEmpty;

  /// GeoNames feature code → 类别。
  ///
  /// 首字母是 feature *class*（`P` 居民点、`A` 行政区、`S` 点状 / 建筑类 ——
  /// 机场和医院直升机场都落在这一类，搜 "Taipei" 会同时返回两者）。
  /// `P`/`A` 之外的 code 不丢弃，统一降级为 [other]：Open-Meteo 没有服务端的
  /// class 过滤参数，而查机场天气本身仍然是一个合理请求。
  static PlaceKind fromFeatureCode(String code) {
    switch (code) {
      case 'PPLC':
        return capital;
      case 'PPLA':
        return provinceSeat;
      case 'PPLA2':
        return city;
      case 'PPLA3':
      case 'PPLA4':
      case 'PPLA5':
      case 'PPLX':
        return district;
      case 'PPL':
      case 'PPLL':
      case 'PPLQ':
      case 'PPLR':
      case 'PPLS':
        return village;
    }
    if (code.startsWith('ADM') || code.startsWith('PCL')) return area;
    return other;
  }
}
