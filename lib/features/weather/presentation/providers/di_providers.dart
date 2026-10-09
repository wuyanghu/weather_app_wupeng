import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_reporter.dart';
import '../../data/open_meteo_repository.dart';
import '../../domain/weather_repository.dart';

/// 依赖装配 —— 只有这一处知道具体的 repository。
/// 把 Open-Meteo 换成另一家服务商，在这里就是一行改动。
final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return OpenMeteoRepository(reporter: const DebugErrorReporter());
});
