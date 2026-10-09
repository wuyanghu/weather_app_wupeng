import 'package:flutter_test/flutter_test.dart';
import 'package:weather_app/features/weather/domain/place.dart';
import 'package:weather_app/features/weather/domain/place_kind.dart';

import '../helpers/fixtures.dart';

/// 「三个 深圳」问题：geocoder 只按名字匹配，于是一个 1700 万人的城市、
/// 台湾一个 6700 人的村子、福建一个无名村落会被混进同一组结果（真实 API
/// 行为，2026-09-22 观察到）。这些测试钉住排序 / 标注 / 去重策略——
/// 正是它把用户想要的那条命中留在最前面。
void main() {
  group('PlaceKind.fromFeatureCode', () {
    test('maps the populated-place ladder', () {
      expect(PlaceKind.fromFeatureCode('PPLC'), PlaceKind.capital);
      expect(PlaceKind.fromFeatureCode('PPLA'), PlaceKind.provinceSeat);
      expect(PlaceKind.fromFeatureCode('PPLA2'), PlaceKind.city);
      expect(PlaceKind.fromFeatureCode('PPLA3'), PlaceKind.district);
      expect(PlaceKind.fromFeatureCode('PPL'), PlaceKind.village);
    });

    test('demotes non-populated classes instead of dropping them', () {
      // 搜索"台北"时同样会返回机场和医院直升机场（AIRP / AIRH）——
      // 服务端没有按类别过滤的能力。
      expect(PlaceKind.fromFeatureCode('AIRP'), PlaceKind.other);
      expect(PlaceKind.fromFeatureCode('ADM1'), PlaceKind.area);
      expect(PlaceKind.fromFeatureCode('PCLS'), PlaceKind.area);
    });

    test('unknown or missing codes fall through to other', () {
      expect(PlaceKind.fromFeatureCode('ZZZZ'), PlaceKind.other);
      expect(PlaceKind.fromFeatureCode(''), PlaceKind.other);
    });
  });

  group('Place.kind compliance remap', () {
    test('PPLC in TW / HK / MO never renders as 首都', () {
      Place placeIn(String cc) =>
          placeFixture(name: '台北市', countryCode: cc, featureCode: 'PPLC');

      expect(placeIn('CN').kind, PlaceKind.capital);
      expect(placeIn('TW').kind, PlaceKind.provinceSeat);
      expect(placeIn('HK').kind, PlaceKind.specialRegion);
      expect(placeIn('MO').kind, PlaceKind.specialRegion);
    });
  });

  group('Place display labels', () {
    test('TW rows drop the duplicated division, not the region label', () {
      // API 返回的 admin1 是 "臺灣省 or 台灣省"，而国家会渲染成 中国台湾
      // ——重复一遍省份只会重新引入繁简不一致的问题。
      final place = placeFixture(
        name: '深圳',
        admin1: '臺灣省 or 台灣省',
        country: '台湾',
        countryCode: 'TW',
        featureCode: 'PPL',
        population: 6700,
      );
      expect(place.region, '');
      expect(place.countryOrRegion, '中国台湾');
      expect(place.displayName, '深圳 · 中国台湾');
      expect(place.locationLabel, '中国台湾');
      expect(place.kind, PlaceKind.village);
    });

    test('mainland rows keep the division and repeat it in displayName', () {
      final place = placeFixture(
        name: '深圳',
        admin1: '广东',
        country: '中国',
        featureCode: 'PPLA2',
        admin2: '深圳市',
        population: 17494398,
      );
      expect(place.region, '广东');
      expect(place.district, '深圳市');
      expect(place.displayName, '深圳 · 广东, 中国');
      expect(place.locationLabel, '深圳市, 广东, 中国');
    });
  });

  group('comparePlacesByRelevance', () {
    Place p(String name, {int id = 1, String fc = 'PPL', int? pop}) =>
        placeFixture(id: id, name: name, featureCode: fc, population: pop);

    test('the real city outranks its same-named villages and airports', () {
      final hits = [
        p('深圳', id: 3), // 村镇，无人口
        p('深圳机场', id: 4, fc: 'AIRP'), // 机场
        p('深圳', id: 1, fc: 'PPLA2', pop: 17494398), // 地级市
        p('深圳', id: 2, pop: 6700), // 台湾的同名村镇
      ]..sort(comparePlacesByRelevance);

      expect(hits.map((h) => h.id).toList(), [1, 2, 3, 4]);
      expect(hits.first.kind, PlaceKind.city);
    });

    test('population breaks ties inside a kind', () {
      final hits = [p('甲', id: 2, pop: 6700), p('乙', id: 1, pop: 17494398)]
        ..sort(comparePlacesByRelevance);
      expect(hits.first.id, 1);
    });

    test('unknown population sorts last, not as zero', () {
      final hits = [
        p('甲', id: 2), // 人口未知
        p('乙', id: 1, pop: 1), // 只有 1 人，但已知
      ]..sort(comparePlacesByRelevance);
      expect(hits.first.id, 1);
    });
  });

  group('Place.displayKey', () {
    test('collapses the PPLC / PCLS duplicate the API returns for 香港', () {
      final plc = placeFixture(
        id: 1819729,
        name: '香港',
        country: '',
        admin1: '',
        countryCode: 'HK',
        featureCode: 'PPLC',
        population: 7396076,
      );
      final pls = placeFixture(
        id: 1819730,
        name: '香港',
        country: '',
        admin1: '',
        countryCode: 'HK',
        featureCode: 'PCLS',
        population: 7396076,
      );
      expect(plc.displayKey, pls.displayKey);
    });

    test('keeps same-name hits from different divisions apart', () {
      final gd = placeFixture(id: 1, name: '深圳', admin1: '广东');
      final fj = placeFixture(id: 2, name: '深圳', admin1: '福建省');
      expect(gd.displayKey, isNot(fj.displayKey));
    });
  });
}
