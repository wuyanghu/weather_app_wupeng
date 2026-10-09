/// 一个可搜索的地点 —— 纯不可变数据，不含任何 JSON / HTTP 知识。
library;

import 'place_kind.dart';

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.country,
    required this.admin1,
    required this.latitude,
    required this.longitude,
    this.admin2 = '',
    this.countryCode,
    this.featureCode = '',
    this.population,
  });

  final int id;
  final String name;
  final String country;
  final String admin1;
  final String admin2;
  final String? countryCode;
  final String featureCode;
  final int? population;
  final double latitude;
  final double longitude;

  PlaceKind get kind {
    final base = PlaceKind.fromFeatureCode(featureCode);
    if (base != PlaceKind.capital) return base;
    switch (countryCode?.toUpperCase()) {
      case 'TW':
        return PlaceKind.provinceSeat;
      case 'HK':
      case 'MO':
        return PlaceKind.specialRegion;
      default:
        return base;
    }
  }

  String get countryOrRegion {
    switch (countryCode?.toUpperCase()) {
      case 'TW':
        return '中国台湾';
      case 'HK':
        return '中国香港';
      case 'MO':
        return '中国澳门';
      default:
        return country;
    }
  }

  /// 一级行政区，例如“浙江省”。
  String get region {
    switch (countryCode?.toUpperCase()) {
      case 'TW':
      case 'HK':
      case 'MO':
        return '';
    }
    return admin1.split(' or ').first.trim();
  }

  /// 二级行政区，例如地级市或县；结果行优先显示它以区分同名地点。
  String get district => admin2.split(' or ').first.trim();

  /// 天气卡片不重复城市名，只显示一级行政区与国家。
  String get displayName {
    final parts = <String>[
      if (region.isNotEmpty) region,
      if (countryOrRegion.isNotEmpty) countryOrRegion,
    ];
    final location = parts.join(', ');
    return location.isEmpty ? name : '$name · $location';
  }

  /// 搜索结果的副标题；二级行政区优先帮助用户分辨同名地点。
  String get locationLabel {
    final parts = <String>[
      if (district.isNotEmpty) district,
      if (region.isNotEmpty) region,
      if (countryOrRegion.isNotEmpty) countryOrRegion,
    ];
    return parts.join(', ');
  }

  /// 一条已渲染行的标识；用户看不出差别的命中才会被折叠。
  String get displayKey =>
      '${name.toLowerCase()}|${admin1.toLowerCase()}|${admin2.toLowerCase()}|$countryOrRegion';
}

/// 用户最可能想搜的地点排在前面：行政级别、人口、名称、id 依次比较。
int comparePlacesByRelevance(Place a, Place b) {
  final byKind = a.kind.rank.compareTo(b.kind.rank);
  if (byKind != 0) return byKind;

  final byPopulation = (b.population ?? -1).compareTo(a.population ?? -1);
  if (byPopulation != 0) return byPopulation;

  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;

  return a.id.compareTo(b.id);
}
