import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层约束的机器检查。
///
/// 「domain 不依赖 Flutter 也不依赖 Dio」「presentation 不直接 import data」——
/// 这两句话写在 README 里只是**约定**，而约定会腐化：哪天有人顺手在 domain 里
/// import 一个 Dio，README 不会报错，这个测试会。
///
/// 用扫描文件而不是看 `pubspec` 依赖：依赖声明是「整个包」级别的，分层是
/// 「单个文件」级别的约束，粒度对不上 —— 包里确实有 dio，但不该出现在 domain。
void main() {
  List<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  Iterable<String> importsOf(File f) => RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(f.readAsStringSync()).map((m) => m.group(1)!);

  /// 把相对 import 还原成相对 `lib/` 的路径 —— 分层规则是按目录说的，而
  /// 文件里写的是 `../../../` 这种相对写法，不还原就看不出它落在哪一层。
  String resolveImport(String fromPath, String importPath) {
    if (!importPath.startsWith('.')) return importPath;
    final segments = fromPath.split('/')..removeLast();
    for (final part in importPath.split('/')) {
      if (part == '.') continue;
      if (part == '..') {
        segments.removeLast();
        continue;
      }
      segments.add(part);
    }
    return segments.join('/');
  }

  /// 文件所属的 feature 名；不在 feature 下则返回 null。
  String? featureOf(String path) =>
      RegExp(r'features/([^/]+)/').firstMatch(path)?.group(1);

  test('scans a non-trivial number of files', () {
    // 目录拿错或正则失效时，下面每条断言都会因为「没找到违规」而假绿 ——
    // 这条先把这个漏洞堵上。
    expect(dartFiles().length, greaterThanOrEqualTo(15));
  });

  test('domain imports neither Flutter, Dio, nor the outer layers', () {
    final violations = <String>[];
    for (final f in dartFiles().where((f) => f.path.contains('/domain/'))) {
      for (final import in importsOf(f)) {
        if (import.startsWith('package:flutter') ||
            import.startsWith('package:dio') ||
            import.contains('/data/') ||
            import.contains('/presentation/')) {
          violations.add('${f.path} → $import');
        }
      }
    }
    // 这条约束的分量在于：domain 能在纯 Dart VM 里跑测试，而不是「我觉得分层了」。
    expect(violations, isEmpty,
        reason: 'domain 一旦依赖 Flutter / Dio / 外层，就不再是纯 Dart 契约层');
  });

  test('presentation does not reach into data, except for DI assembly', () {
    final violations = <String>[];
    for (final f in dartFiles().where((f) => f.path.contains('/presentation/'))) {
      // DI 装配处是唯一允许知道具体实现的地方 —— 换数据源只改它一个文件。
      // 这个例外必须显式写出来，否则「presentation 直接 import data」会一点点扩散。
      if (f.path.endsWith('di_providers.dart')) continue;
      for (final import in importsOf(f)) {
        if (import.contains('/data/')) violations.add('${f.path} → $import');
      }
    }
    expect(violations, isEmpty,
        reason: 'presentation 只能看见 domain；具体实现由 DI 装配处注入');
  });

  test('data does not depend on presentation', () {
    final violations = <String>[];
    for (final f in dartFiles().where((f) => f.path.contains('/data/'))) {
      for (final import in importsOf(f)) {
        if (import.contains('/presentation/')) {
          violations.add('${f.path} → $import');
        }
      }
    }
    expect(violations, isEmpty, reason: '依赖方向必须单向：presentation → domain ← data');
  });

  test('core does not depend on features', () {
    final violations = <String>[];
    for (final f in dartFiles().where((f) => f.path.contains('/core/'))) {
      for (final import in importsOf(f)) {
        if (resolveImport(f.path, import).contains('/features/')) {
          violations.add('${f.path} → $import');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'core 是最内层：它一旦认识 feature，就再也提不出来了');
  });

  test('features do not import each other', () {
    final violations = <String>[];
    for (final f in dartFiles().where((f) => featureOf(f.path) != null)) {
      final own = featureOf(f.path);
      for (final import in importsOf(f)) {
        final target = featureOf(resolveImport(f.path, import));
        if (target == null || target == own) continue;
        violations.add('${f.path} → $import');
      }
    }
    // 这条现在只有一个 feature，看上去形同虚设。它的价值在第二个 feature
    // 加进来那天：那时「顺手 import 一下」是最省事的写法，也是两个 feature
    // 再也拆不开的第一步 —— 真到了那天，共享的东西要么下沉 core，要么搬到
    // `features/shared/` 下；现在没这个目录，是因为还没人需要它。
    expect(violations, isEmpty, reason: 'feature 之间必须互不可见');
  });
}
