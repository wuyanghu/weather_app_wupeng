# 天气应用 · Weather App (Flutter Take-Home)

搜索地点 → 查看当前天气 → 查看预报。数据来自 [Open-Meteo](https://open-meteo.com/)（免费、无需 API Key，评审者 clone 后可直接运行）。

## 三条值得一读的决策

1. **防抖、取消、世代计数是三件事，不是一件。** 只靠世代计数的话，旧响应确实被丢弃了，但字节还是下载完了 —— 所以测试断言的不是「UI 最终显示对了」，而是「被取代那次的 signal 真的 `isCancelled`」。
2. **降级必须一直传到消费端。** 数据层会把缺了必需字段的那一条丢掉，于是「空数组」是一种**合法结果** —— widget 必须扛得住，否则优雅降级会变成一次崩溃。
3. **「现在」永远是传进来的，不去读设备时钟。** `timezone=auto` 意味着时区由服务端决定；人在北京问纽约的天气，「今天」是另一天。

---

## 快速开始

```bash
flutter pub get
flutter run                 # 连接设备 / 模拟器
flutter test                # 72 个测试，全部离线运行
flutter analyze             # 静态检查，零告警
```

环境：**Flutter 3.44.6 / Dart 3.12.2**。项目根目录带 `.fvmrc`，装了 [fvm](https://fvm.app) 的话 `fvm use` 就对齐了；没装就自己确认版本。

⚠️ `pubspec.yaml` 里的 `sdk: ^3.12.2` 约束的是 **Dart SDK**，管不到 Flutter —— Flutter 版本只能靠工具或 CI 钉，所以 CI 写的是 `flutter-version: '3.44.6'`，不拉 latest（理由见下）。**没有任何需要配置的密钥** —— 不用注册账号，不用填 `.env`。

CI（`.github/workflows/ci.yml`）在每次 push / PR 上跑 `flutter analyze --fatal-warnings` + `flutter test`，Flutter 版本钉死为 3.44.6 —— 不拉 latest，否则升级会以「和代码无关」的方式把 CI 变红，那种红没人会去查。

---

## 一、功能范围（主动划定）

| 需求 | 实现 |
| --- | --- |
| 搜索地点 | 输入即搜（防抖 300 ms），支持中文 / 英文；结果行带行政级别标签（「地级市」「村镇」），并按级别 + 人口重排、去重 |
| 当前天气 | 温度、天气现象、体感、湿度、风速、降水、观测时间 |
| 天气预报 | 未来 **24 小时**逐时（横向滚动，含降水概率）+ 未来 **7 天**（含温度区间条） |
| Loading / Error | 搜索 4 态 + 天气 4 态，全部有对应 UI；错误可重试，加载有骨架屏 |

**未实现并在此说明理由**（不是漏做，是主动控制范围）：

- **GPS 定位**：题目要求是"搜索地点"。定位会引入权限申请、拒权降级、模拟器定位配置等与考点无关的分支。
- **本地缓存**：缓存的价值在"离线可用"，而离线场景需要一套完整的数据陈旧策略才站得住；4–6 小时里做半套反而破坏错误处理的一致性。
- **多语言 / 深色主题 / 地图 / 收藏**：与本次考察的架构、状态、错误处理维度无关的体力活。

---

## 二、架构

```
lib/
├── main.dart                          # 入口：ProviderScope + 主题
├── app/                               # 应用级组装：不属于任何 feature
│   └── home_screen.dart               # 把各 feature 提供的区块拼成一屏
├── core/                              # 不认识业务的基础设施
│   ├── cancel_signal.dart             # 纯 Dart 取消信号：domain 契约用得上，但它不认识业务
│   ├── errors/app_exception.dart      # sealed 异常体系（网络 / 超时 / 服务端 / 解析）
│   ├── errors/error_reporter.dart     # 上报出口（log 有实现，upload 留空）
│   ├── network/api_client.dart        # Dio 配置 + 重试 + 异常映射 + 三个与业务无关的小工具
│   ├── theme/app_theme.dart
│   ├── utils/formatters.dart
│   ├── utils/json.dart                # 容错取值：缺字段是给默认值还是给 null
│   └── widgets/status_views.dart      # 跨 feature 复用的状态视图（错误 + 重试）
└── features/
    └── weather/
        ├── domain/                    # 纯 Dart：不依赖 Flutter / Dio / JSON
        │   ├── place.dart             # Place + 同名命中排序策略（地理概念，不是天气概念）
        │   ├── place_kind.dart        # GeoNames feature_code → 行政级别
        │   ├── weather_models.dart    # CurrentWeather / HourlyWeather / DailyWeather / WeatherReport
        │   ├── weather_code.dart      # WMO 天气码 → 中文描述
        │   └── weather_repository.dart# 仓储契约：searchPlaces + fetchWeather
        ├── data/                      # 只知道"怎么拿到数据"
        │   ├── open_meteo_dto.dart        # 两个 endpoint 的 DTO：JSON → 强类型，容错缺字段
        │   └── open_meteo_repository.dart # OpenMeteoRepository
        └── presentation/              # 只知道"怎么展示状态"
            ├── providers/             # Riverpod：DI / 搜索状态机 / 天气状态机 / 选中地点
            └── widgets/               # 纯展示组件：搜索区、区块、卡片、天气自己的状态视图
```

依赖方向单向：`presentation → domain ← data`。domain 层既不 import Flutter 也不 import Dio —— 它能在纯 Dart VM 里跑测试，也意味着换一家天气服务只改 `data/` 一个文件加一处 DI 注册。

**目录判据**：同一个问题问三遍 —— 它认不认识业务？有几个消费方？是不是壳？

| 位置 | 判据 | 反例 |
| --- | --- | --- |
| `core/` | 不认识任何业务。`ErrorRetryView` 只知道「一句话 + 一个重试回调」 | 天气的骨架屏三块占位高度是按天气卡摆的，所以它留在 weather 而不是下沉 core |
| `features/weather/` | 认识业务，且**现在只有天气一个消费方** | 把一个只有天气在用的东西说成"公共的"，就是给假想需求先付了费 |
| `app/` | 是壳，不是 feature。`HomeScreen` 的工作是拼装各 feature 的区块 | 它住在 weather 下时，加空气质量就得改 weather 的文件 |

**`features/shared/` 现在是空的，所以不建。** 判据不是「它像不像公共模块」，而是「现在有没有第二个消费方」：`Place` 确实是个地理概念（字段里一个天气词都没有），但只有天气在读它。为一个还不存在的 feature 先建目录，是纯粹的预支 —— 而且真到那天搬家的成本只是移动文件加改 import，**那时搬，是因为那时才知道对方到底要什么**。

同一个判据也决定了**搜索框的位置**：`SearchController` / `SearchSection` 在 `weather/presentation/` 下。它们现在唯一的消费方是查天气；等出现第二个要用搜索框的 feature，才搬去 `features/shared/`。

feature 之间**互不可见**：要共用东西，要么下沉 `core/`（不认识业务），要么抽 `features/shared/`（认识业务、且真有两个以上消费方）。这条同样是机器保证的（见下）。

**这条现在是机器保证的，不是约定**：`test/architecture_test.dart` 扫描 `lib/` 下每个文件的 import，断言 domain 不碰 Flutter / Dio / 外层、presentation 只能看见 domain（DI 装配处是唯一例外）、data 不反向依赖 presentation、**core 不依赖任何 feature**、**feature 之间互不 import**。谁在 domain 里 import 一个 Dio，CI 立刻变红 —— README 不会拦人，测试会。

扫描文件而不是看 `pubspec` 依赖，是因为粒度对不上：依赖声明是「整个包」级别的，而分层约束是「单个文件」级别的 —— 包里确实有 dio，但它不该出现在 domain。

### 关键取舍

**1. Riverpod，而不是 setState / Bloc**

题目把"妥善处理 Loading 与 Error"单列为需求，说明这是评审重点。Riverpod 的 `AsyncValue` 本身就是 `loading / data / error`（且能保留旧值）的联合类型，重试就是 `ref.invalidate`，不需要手写 `isLoading` + `errorMessage` 这类容易互相矛盾的字段组合。

代价：多一个依赖、多一层概念。如果应用只有一个页面两次请求，`setState` 更划算；但这里有三个互相耦合的状态源（搜索输入 ⇄ 选中地点 → 天气），用 `setState` 必然要手工做状态同步与竞态处理。

**2. 用 sealed class 表达搜索状态，而不是枚举 + 可空字段**

```dart
sealed class SearchState {}
class SearchInitial {}   // 还没搜：显示引导
class SearchLoading {}   // 搜索中：内联 loading
class SearchSuccess {}   // 有结果
class SearchEmpty {}     // 搜到了但无匹配
class SearchError {}     // 网络 / 服务端失败
```

UI 侧 `switch` 穷尽匹配，编译器保证新增状态时不会漏分支。**`SearchEmpty` 与 `SearchError` 是刻意分开的**：把"没找到"渲染成红色报错，是搜索类应用最常见的体验缺陷。

**3. Repository 接口定义在 domain，实现在 data**

接口由使用方定义、实现方依赖它，依赖方向不反转 —— 这是"API 整合"维度最直接的论据。附带好处是可测性：注入一个假实现就能覆盖全部 UI 状态，不需要起 HTTP server。

**4. DTO 与领域实体分离**

`PlaceDto` 保留接口原始字段，`Place` 是带 `displayName` 的领域对象。接口结构变化不会漏到 UI；反过来 UI 想改展示方式也不用碰解析逻辑。

**5. 单页面，不做多余路由**

题目是一个聚焦流程，加详情路由只增加导航样板而不增加信息。将来要支持多城市对比时，把 `weatherControllerProvider` 改成 family（按地点缓存）即可，不必重构页面。

---

## 三、状态管理与数据流

```
用户输入 ──► SearchController（防抖 300ms / 取消 / 代际校验）──► SearchState（5 态）
                     │ 点选结果
                     ▼
            selectedPlaceProvider ──► WeatherController（AsyncNotifier）
                     │                       │ build() 内 watch 地点
                     ▼                       ▼
              selectedPlaceProvider    WeatherReport → 3 张卡片
```

- **防抖 + 取消 + 代际（generation）校验**：输入 "hangzhou" 会触发 8 次 `onChanged`。防抖把请求压到 1 次；代际计数决定"谁有资格渲染"，丢弃先发后到的过期响应（否则慢的旧请求返回时会覆盖新结果）；`CancelSignal` 则真的把在途请求掐掉，而不是让它跑完再扔掉。三者各司其职——**只有代际的话，字节照样下载完**，这一点单靠读代码容易自我欺骗，所以测试里断言的是"被取代的那次请求的 signal 确实 `isCancelled`"，而不是只看最终渲染结果。
- **取消信号定义在 domain，不暴露 HTTP 库类型**：`WeatherRepository.searchPlaces(query, cancel: CancelSignal)` 收的是纯 Dart 信号（`Completer` 封装），data 层再桥接成 Dio 的 `CancelToken`。否则为了一个取消参数，domain 就得 import Dio——整个分层论证会为了 20 行代码破功。
- **选中地点自动拉天气**：`WeatherController.build()` 中 `ref.watch(selectedPlaceProvider)`，地点一变自动重建、自动重取，页面里不需要写"选完再去 fetch"。
- **刷新保留旧数据**：UI 侧 `skipLoadingOnRefresh: true`，下拉刷新不会把已有内容清空成骨架屏 —— 重新加载时闪白是最容易被扣分的细节。
- **搜索侧用 `Notifier`，不是 `AsyncNotifier`**：两者是同一代 API，选 `Notifier` 是因为这条链路**用不上 async** —— 防抖、代际计数、`CancelSignal` 三件事都发生在"提交请求的那一瞬间"，状态迁移是同步的；硬塞进 `AsyncNotifier` 等于把取消语义交给框架托管，再在 `.when()` 里重新发明一遍"被取代的请求不许回写"。天气侧确实是异步三态，所以用 `AsyncNotifier`；`selectedPlaceProvider` 仍是一个 `StateProvider<Place?>`：一个可空地点不值得为它写一个类。
- **输入不牵动结果列表**：清除按钮的显隐用 `ValueListenableBuilder` 挂在 `TextEditingController` 上，重建范围只有输入框自己。这条纯属自洽性要求：既然选型理由是"Riverpod 做细粒度重建"，UI 里就不该留一个每敲一个字符重建整块搜索区的 `setState`。

### 同名地点：排序、标签与去重

geocoding 接口是**纯名字匹配**，不看行政级别：搜「深圳」会同时返回 1700 万人口的地级市、台湾一个 6700 人的同名村、福建一个无名同级居民点；搜「Taipei」甚至会带回机场和医院停机坪（`AIRP` / `AIRH`）。直接按 API 顺序展示，用户想要的城市不一定在第一条，也不知道某一行到底是什么。三步处理，全部在 domain / data 层完成：

1. **重排**（`comparePlacesByRelevance`）：行政级别（GeoNames `feature_code`：`PPLC` → `PPLA` → `PPLA2` → `PPL*` → 其他）→ 人口降序（人口未知排在已知之后，而不是当 0）→ 名称 / id 兜底保证结果稳定。
2. **标签**：每行渲染「地级市 / 省会 / 村镇 / 特别行政区…」徽章，让重名结果一眼可排除。`PPLC`（首都）在中国台湾 / 香港 / 澳门按同一套合规映射转成「省会 / 特别行政区」，绝不渲染为「首都」。
3. **去重**：接口对「香港」会同时返回 `PPLC` 和 `PCLS` 两条、对「上海」会返回三条显示完全一样的云南村庄。凡是**渲染出来一模一样**的行（同名 + 同地区 + 同国家），保留排序后的第一条 —— 对用户来说无法区分的重复行就是噪音。

两个刻意不做的决定：**不过滤**非居民点（接口没有服务端 feature-class 过滤参数，机场对查天气仍然合法，降级排序即可）；**不做完整繁简转换**（「臺灣省 or 台灣省」这类 OSM 双写取主变体，TW/HK/MO 的层级信息由「中国台湾」等已表达，完整 T2S 需要真映射表，不属于本题范围）。

---

## 四、API 集成

| 用途 | 接口 |
| --- | --- |
| 地点搜索 | `GET geocoding-api.open-meteo.com/v1/search?name=&count=&language=zh` |
| 天气数据 | `GET api.open-meteo.com/v1/forecast?latitude=&longitude=&current=&hourly=&daily=&timezone=auto&forecast_days=7` |

- `timezone=auto` 由服务端按地点时区返回时间，客户端不做时区推算 —— 搜"东京"时显示的是东京当地时间。这条约束**一路贯彻到格式化**：`Formatters.weekday(date, now)` 把"现在"做成必传参数，调用方必须传 `WeatherReport.currentTime`。早先它自己取 `DateTime.now()`，于是同一份数据里出现了两个"现在"（仓库层裁 24 小时用服务端时间，UI 判"今天"用设备时间）——设备时区与地点时区差半天以上时，"今天"会标错一天，而且错得很隐蔽：只有查异地城市才看得出来。把它变成参数还顺带让这个函数成了纯函数，测试可以直接换一个"现在"来断言。
- 逐时数据返回 7 天共 168 条，仓库层裁剪为**当前小时起的 24 条**，UI 不用关心数据量。
- **字段缺失不补默认值。** DTO 的数值字段一律可空，「接口没给」原样传到转换层，由它决定这一项要不要。容错策略是：**能展示的都展示，缺的不展示** —— 不是"缺的补个 0"。
  - **判据只有一句：这个字段缺了，这条数据还成立吗？** 成立（体感 / 湿度 / 风速 / 降水 / 降水概率）→ 传 `null`，UI 不显示那一格；不成立（当前温度 / 天气码 / 日夜 / 观测时刻；逐时逐日的温度与天气码）→ 丢掉这一条，或让整次请求失败。**少显示一项，胜过显示一条假的。**
  - **接口确实会不给**，不是理论风险：Open-Meteo 文档原话 "Depending on the model … **not all weather variables are available**"；官方 SDK 文档说请求了不可用的变量会得到 **empty data arrays without an explicit error**；真实 issue（open-meteo#1319）里 `precipitation_probability` 返回过整列 `null`。
  - 这条不是靠自觉守住的：`core/utils/json.dart` **只有 `…OrNull` 一族**，压根没有"缺了给个默认值"的方法 —— 和 `guarded()` 同一个思路：与其写注释说"别这么干"，不如让这个工具类根本干不了。
  - ⚠️ 降水是最容易蒙混过关的一个，也因此最容易被漏：`weather_code` 补 0 是"晴天"、`temperature` 补 0 是"0°"、`is_day` 补 0 是"夜间图标"，都错得刺眼；而 `precipitation` 补 0 是"降水 0.0 mm" —— **看起来完全正常**，而且多数时候确实没下雨。但判据不能建立在"大概率蒙对"上：**0.0 是"实测没下雨"，缺失是"没有这个测量"**，界面不该陈述一件它并不知道的事。
- 同一个判据也用在 geocoding 上：**命中缺坐标就直接丢掉**。坐标补 0 会变成 (0, 0) —— 几内亚湾，一个**合法**坐标，界面会正常显示一份完全错误的天气，而且没有任何一个值看起来不对。宁可少一条搜索结果。
- 降级必须一路做到消费层。上面这条策略有个直接推论：**空数组是合法的降级结果**。消费层若直接 `list.reduce(...)`，一次降级就会把"少了逐日预报"升级成整页崩溃（`StateError: Bad state: No element`）—— 防御做在数据层却漏在消费层，等于整条容错链白写。`DailyList` 对空日报渲染"暂无逐日预报"，并有测试钉住。
- DTO 解析集中在一个文件，接口改结构时只改一处。
- **重试与退避**：超时 / 连接失败 / 5xx 各重试最多 2 次（共 3 次请求），退避 400ms → 1200ms。判断标准是**「重发一次有没有意义」**，不是「出错了没」—— **主动取消不重试**（调用方已经不等这个结果了，重发只是白占连接），**4xx 不重试**（请求本身是错的，再来一次只是把失败慢一倍）。两个接口都是 GET、幂等，所以重发没有副作用。
  - **退避期间调用方可能已经取消了**：让退避和 `cancelToken.whenCancel` 竞速，取消先到就不重发。否则那一发白占一次连接，而且错误类型会搞错 —— 真正发生的是"已取消"，上报的却是当初那个超时，界面于是渲染一个早就没人等的「请求超时」。
  - **退避合计 1.6 秒，但那不是失败路径的耗时上界**：每次请求自身还有 10 秒超时，而重试次数与超时是**相乘**的 —— 最坏 3 × 10 + 1.6 ≈ 32 秒才判失败。要收紧，正确的做法是给整条链路一个**总预算（deadline）**：第 N 次请求只能用剩余预算，而不是各自拿满 10 秒（gRPC 的 deadline 就是这个思路）。
  - 重试次数挂在 `requestOptions.extra` 上，`onError` 与 `onResponse` **共用同一个计数器**，所以 `5xx → 网络错误 → 5xx` 这种混合路径的总请求数仍被限死在 3 次。
- ⚠️ 上面这条有个容易踩空的地方：**5xx 的重试必须写在 `onResponse` 里自己看状态码**，不能写在 `onError` 里等 `DioExceptionType.badResponse`。因为 `validateStatus` 被设成全放行（状态码的判定有意挪到了仓库层 `ensureOk`），Dio **不会**为非 200 抛异常 —— 那个分支会变成永远执行不到的死代码，而且测试不写「5xx 真的重试了」就发现不了。
- **错误响应体不丢**：Open-Meteo 出错时会在 body 里给 `reason`，只把一个状态码往上报等于把服务端自己说的原因扔了。`ensureOk` 现在把响应体塞进 `ServerException.cause`。

---

## 五、错误处理

统一异常体系，UI 永远看不到 `DioException` / `SocketException` / HTTP 状态码：

| 触发 | 映射为 | 用户看到 |
| --- | --- | --- |
| 连接超时 / 收发超时 | `TimeoutException` | 请求超时，请稍后重试 |
| DNS 失败 / 连接被拒 / 断网 | `NetworkException` | 网络连接不可用，请检查网络后重试 |
| HTTP 4xx / 5xx | `ServerException(statusCode)` | 服务暂时不可用，请稍后重试 |
| 响应无法解析成模型 | `ParseException` | 数据解析失败，请稍后重试 |
| 被更新的输入取代 | `CancelledException` | **不显示**，静默丢弃 |

约定：**仓储层只抛 `AppException` 子类**，上层状态机只 catch 这一种类型。这条契约现在由结构保证而非靠自觉——仓储实现走 `core/network/api_client.dart` 里那一个 `guarded` 漏斗（`Dio → AppException`、`TypeError / FormatException → ParseException`、其余兜底 `NetworkException`）。此前两个方法各写各的 catch 列表，`searchPlaces` 少了解析那两条，畸形响应就以裸 `TypeError` 逃出去。放在 core 而不是每个方法各写一份，是因为「哪些异常算 Parse、哪些算 Network」是一处全局判断 —— 复制两份，漏掉的那几条就会各自不同。文案藏在异常里，所以任何新增页面天然具备一致的错误提示；要接埋点时 `cause` 字段保留了原始错误对象。

状态机侧还额外留了一道 catch-all，因为"只抛 `AppException`"不是编译器能保证的事：漏掉它的那一刻，搜索框会**永久停在 loading 且没有重试入口**——那比报一个错严重得多，所以宁可多兜一层。

**`cause` 必须有去处，否则整套映射等于白做**：映射必然丢信息 —— 用户看到的是"网络连接不可用"，排查却需要知道底层是 DNS 失败还是连接被拒。所以 `AppException.cause` 留着原始异常，`ErrorReporter` 是它的出口：`log()` 在 debug 下打印类型、文案和 cause，`upload()` 留给远端上报。**`upload()` 现在是空实现** —— 没有接入服务，但接口先就位；接 Sentry 时只实现这一个方法、再改 DI 装配处一行，调用点一个都不用动。

上报的调用点只有一处：`guarded` 漏斗，两个 endpoint 的错误全部从这里出去，因此不会漏。还有一条刻意的过滤：**`CancelledException` 不上报** —— 每敲一个字符都可能产生一次取消，报上去全是噪音，会把真正的错误淹掉。

界面上，错误不是一条 Toast 就完事：主内容区显示图标 + 原因 + **重试按钮**（重试幂等，直接 `invalidate` 重新请求）；搜索区域的错误是内联提示，不打断输入。

---

## 六、测试

```
test/
├── core/api_client_test.dart                 # 错误映射表 + 取消映射 + 重试策略：5xx / 超时会重试，4xx 与取消不重试，用满 2 次就停，退避期间取消不重发（12 例）
├── architecture_test.dart                    # 分层约束：domain 不碰 Flutter / Dio；presentation 不直接碰 data；core 不反向依赖 feature；feature 之间互不 import（6 例）
├── features/open_meteo_repository_test.dart  # 两个 endpoint：地点解析 / 排序去重 / 缺坐标丢弃 / 预报解析 / 24h 裁剪 / 可选字段缺了是 null / 必需字段缺了整次失败 / 缺字段那格丢弃 / 500 / 断网 / 畸形响应 / 取消在途请求 / 上报出口（18 例）
├── features/place_kind_test.dart             # 级别映射 / 合规重映射 / 排序策略 / 去重键（11 例）
├── features/search_controller_test.dart      # 防抖 / 清空 / 空结果 / 错误 / 竞态丢弃 / 取代请求被真正取消 / 仓储崩溃降级 / 选中提交 / 重试（12 例）
├── features/home_flow_test.dart              # 端到端：空闲 → 搜索 → 选中 → 渲染；天气错误 → 重试；搜索错误 → 重试；徽章；清除按钮；布局回归（10 例）
└── features/weather_cards_test.dart          # 消费层防御：空日报不崩溃且给出空态；"今天"以传入的"现在"为基准（3 例）
```

- **只测核心逻辑，不追覆盖率数字**：数据层（解析 + 错误映射）和状态层（状态迁移）属于"错了会静默出错"的地方，值得测；纯展示组件的断言基本等于把 UI 代码重写一遍。
- **例外是降级路径**：上一条很容易被理解成"组件不用测"，但真正该测的是**边界输入会不会崩**——空日报那条断言的是"数据层降级出来的空数组流到 UI 也不会炸"，这是在给降级链补最后一环，不是在重写 UI。
- **不依赖网络**：仓储测试通过 `HttpClientAdapter` 假实现注入响应，快、离线可跑、结果确定。
- 竞态那条测试是刻意构造的：第一次请求慢、第二次请求快，断言最终显示的是**后发**请求的结果。
- **假实现"能感知取消"才有意义**：最早的版本里 fake 观察不到取消这件事，于是"取消在途请求"这句注释在代码里根本没有对应实现也能全绿——假实现把接口的漏洞一起 fake 掉了。现在假 transport 会与 `cancelFuture` 竞速，状态测试则断言"被取代那次的 signal 确实 cancelled"。同理，等待全部改成**断言条件**（等到第 N 次调用发生、等到状态离开 loading），而不是 `sleep(380ms)`：真实防抖计时器在多文件并行跑时会让固定 sleep 先过期。

### 布局回归（真机发现的问题）

真机运行时报过 `RenderFlex overflowed by N pixels`，根因不是"某个组件太高"，而是**空间分配错了**：

搜索区与天气区同处一个 `Column`。搜索区的自然高度随结果条数增长，把天气区挤到 0 —— 溢出的是外层的 `Column`，报错却指向状态视图，容易看错方向。修完第一版（外层改 `Flexible(loose)`）后出现新问题：`Flexible` 与 `Expanded` 会**平摊**剩余空间，搜索区拿到 272px 却只画 60px，白扔一半屏幕。

最终方案：

- 搜索区高度用 `LayoutBuilder` 按**真实 body 高度**取上限（60%），保持**非弹性子节点** —— 弹性子节点会平摊，非弹性子节点只会占用自身需要的高度
- 结果列表在这个上限内再取 70%，超出部分列表内部滚动，10 条结果也不会吃掉内容区
- 状态视图（空态 / 错误态）用"够高居中、不够高可滚动"的布局，键盘弹出把视口压到几十像素时降级为滚动，而不是黑白条纹

这三条都有回归测试钉住：`useShortViewport()` 把测试视口压到 140px 高模拟键盘弹出，另有一条断言长结果列表不会让内容区消失。

---

## 七、如果有更多时间

按优先级：

1. **本地缓存 + 离线降级**（`shared_preferences` / `sqflite` + 数据陈旧标记）—— 此时才值得引入仓储层的缓存策略
2. **城市收藏与多城市切换** —— `weatherControllerProvider` 转 family + 加路由
3. **按天气码切换背景氛围**（晴 / 雨 / 夜）—— 视觉收益高、成本低
4. **CI 门禁**：`flutter analyze` + `flutter test` 挂到 PR 检查
5. **可访问性**：语义标签、动态字号下的布局回归测试
