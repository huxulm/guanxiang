# 观象（Guanxiang）开发计划

跨平台（Windows、Linux、Android）天文事件搜索工具。核心用 Rust 编写，界面用 Flutter。

最后更新：2026-11-10

## 1. 目标

- 快速搜索日月食、水金凌日、行星合冲、月掩星和卫星凌月。
- 既能查全球事件，也能查某地能否看到、何时看到。
- 长期事件可离线使用，卫星凌月在有网络时更新。

第一版暂不做：iOS 和 macOS、星图渲染、望远镜控制、历史卫星事件、公元前的长期推算。

## 2. 当前状态

| 项目 | 状态 |
|---|---|
| Rust 工作区骨架 | 已完成：core + CLI，fmt / clippy（`-D warnings`）/ test 全部通过 |
| M1 星历与坐标 | 时间尺度、ΔT、视位置、站心与地平坐标、CLI `position` 已完成并通过对照验证；**真机测试未做** |
| 第三方依赖 | 已接入 anise 1.0.0-beta（关闭默认 feature）、sofars 0.6.2、sgp4 2.4.0；sgp4 尚未实际调用 |
| 星历读取 | de440s 可读，J2000 TDB 地月距离 402 448.640 km，与参考值一致 |
| Windows（x86_64-pc-windows-msvc） | 编译、测试通过 |
| Linux（x86_64-unknown-linux-gnu） | 在 WSL Ubuntu 24.04 原生编译、测试通过 |
| Android（aarch64-linux-android） | NDK 30 + cargo-ndk 交叉编译通过；`.so` 只依赖 libc / libdl，LOAD 段 16 KB 对齐；**尚未在真机运行** |
| M2 合冲与凌日 | 合、冲、角距极小、凌日、可见性过滤、星表格式、CLI `search` 已完成，凌日次数和事件时刻验收通过；**真机耗时未测** |
| 手机上的搜索速度 | 未验证。桌面实测见 M1、M2 记录；按经验推算，月球相关的 100 年搜索在手机上可能超过 1 秒 |
| GitLab CI | gitlab.xao.ac.cn/xulingming/guanxiang，fmt、clippy、android-deps、test 全部通过。runner 无外网，de440s 由本项目 Generic Package Registry 提供 |
| M4 日月食 | 全球与本地情况、1900–2100 星表、CLI `eclipse`、App 支持已完成；与 NASA 21 世纪星表逐条一致 |
| M6 卫星凌月 | 已完成（除外部对比）：计算核心、CLI、App 卫星页（CelesTrak 下载缓存、频率限制、新旧预报比较、地图中心线、太阳安全提示、Android 后台刷新）；69 次接近与 Skyfield 相差 ≤ 0.007 秒。transit-finder 对比、实测核对未做 |
| 日月出没、晨昏、月相 | 计算核心 `events::almanac`、看板“今晚”卡片已完成；1045 个出没和晨昏事件与 Skyfield 相差 ≤ 0.03 秒，月相照亮比例差 ≤ 0.0001 |
| M5 月掩星 | 月掩行星和 550 颗亮星、本地掩始掩终、CLI `occultation`、App 支持已完成；92 次事件与 Skyfield 相差 ≤ 0.003 秒 |
| Flutter 应用（M3） | `app/` 已创建并接入 flutter_rust_bridge 2.13；搜索、进度、取消、详情页可用。**Android 模拟器**（Android 15，16 KB 页）上集成测试全部通过；**Windows 桌面**待开启开发者模式；**Linux 桌面**待准备 Linux 工具链；**Android 真机**未测 |

## 3. 关键技术决策

| 编号 | 决策 | 原因 |
|---|---|---|
| D1 | 星历以 JPL DE440s 为主，不使用 vsop87 | VSOP87 不含月球，日月食和掩星都用不上 |
| D2 | anise 只用于读取星历和基础坐标，事件搜索自己写 | anise 的事件查找偏航天器场景，长时段搜索需要按事件类型剪枝 |
| D3 | sofars 负责时间尺度、岁差章动和坐标变换 | 纯 Rust，无需 C 编译器 |
| D4 | 卫星用 `sgp4` crate，数据格式以 OMM 为主，编号用 `u32` | TLE 的 5 位编号已用完，新目标不再提供 TLE 格式 |
| D5 | 网络请求放在 Dart 层，Rust 只接收数据字符串 | Rust 核心不引入 TLS，也更容易测试 |
| D6 | 核心库不依赖 Flutter，桥接层保持很薄 | 核心可以用 CLI 独立测试，也能复用到别的前端 |
| D7 | 全球事件在桌面端预计算后随应用发布，手机上只算本地情况和自定义条件 | 这是提升速度最有效的手段 |
| D8 | 长期搜索和卫星凌月分成两个模块 | 两者的数据来源、搜索范围和结果稳定性都不同 |
| D9 | core 的公开 API 只用自己的类型（`Body`、`Tdb`、`Vec3`），不暴露 anise / hifitime / nalgebra 类型 | 以后换成自写 SPK 读取器时上层不受影响 |
| D10 | 星历查询用 anise 的 `ICRS`（NAIF 1）轴，不用 `J2000`（anise 1.0 中为 22，带约 23 mas 框架偏差） | DE440 本身就是 ICRF，避免多出一次旋转 |
| D11 | 视位置用 IAU 2006 岁差 + IAU 2000A 章动（SOFA `pnm06a`），站心用 CIO 方法（ERA + `c2i06a`），忽略极移 | 现行 IAU 标准；极移对事件时刻的影响可以忽略 |
| D12 | ΔT：1800–2026 查 USNO/IERS 表；表后用 Hermite 曲线过渡到 Espenak–Meeus 2050–2150 公式；可通过 `Time::with_delta_t` 注入实测值 | 历史段用实测值；未来段与 NASA 日月食星表的外推一致，便于 M4 对照 |
| D13 | 星历和光行时以 Horizons 为对照，视位置以 Skyfield 为对照 | Horizons 的视位置基于 IAU76/80，与 IAU 2006/2000A 有约 0.05″ 的春分点差，2027 年后还会漂移 |
| D14 | 预计算星表用自定义定长二进制格式（16 字节头 + 48 字节记录，按时间排序），不用 SQLite | SQLite 需要编译 C 代码，违背 M0 的无原生依赖；事件表只读、规模小，二分查找即可 |
| D15 | 桥接层按年分块搜索，每块后回传进度、检查取消标志；回传用普通结构体（`SearchUpdate`），不用带数据的枚举 | core 不需要进度和取消接口；Dart 端不需要 freezed 代码生成 |
| D16 | 日月食用地心视位置；月食默认 Danjon 地影放大；月球半径半影 k₁ = 0.2725076、本影 k₂ = 0.2722810 | 与 NASA 五千年星表逐条一致，便于对照和用户比对 |
| D17 | SGP4 用 WGS72 常数和 IAU 恒星时（与 python-sgp4 默认一致），不用 sgp4 crate 默认的 WGS84 | NORAD 根数按 WGS72 拟合；与参考实现一致 |

## 4. 架构

```text
Flutter app（app/）
  │  flutter_rust_bridge（Stream 回传进度）
  ▼
桥接层（app/rust，M3 创建）
  ▼
guanxiang-core
  ├─ body / time / geometry   基础类型
  ├─ ephemeris                星历接口，已接入 anise
  ├─ delta_t                  ΔT 模型（表 + 外推）
  ├─ astrometry               视位置、站心位置、地平坐标、大气折射
  ├─ observer                 测站（WGS84）
  ├─ search                   通用极小值与求根（Brent）
  ├─ stars                    月掩星用的精简星表（Hipparcos，550 颗）
  ├─ events                   合冲、角距极小、凌日、日月食（全球与本地）、月掩星、可见性、星表格式
  ├─ satellite                SGP4（OMM/TLE，WGS72）、TEME → 地固
  └─ events::sat_transit      卫星凌日、凌月：最小角距、历时、地面中心线、带宽

guanxiang-cli                 调试、验证、生成预计算星表
```

依赖方向固定为：`app → 桥接层 → core`，`cli → core`。`core` 不依赖上层，也不做网络请求。

### 目录

```text
guanxiang/
├─ Cargo.toml        Rust 工作区
├─ crates/
│  ├─ guanxiang-core/
│  └─ guanxiang-cli/
├─ app/              Flutter 应用（lib/ 界面，rust/ 桥接层，rust_builder/ Cargokit）
├─ data/             星历等数据，不进 Git
└─ docs/PLAN.md      本文档
```

## 5. 里程碑

工期按一人全职估算，只用于排序和粗略规划，共约 15.5 周。

### M0 工程基线（0.5 周）

- [x] 工作区、core、CLI 骨架
- [x] 建立 Git 仓库和 GitLab CI（fmt、clippy、test）
- [x] 加入 anise、sofars、sgp4 依赖，用 `cargo tree` 检查原生依赖和 TLS
- [x] 编译到 `x86_64-pc-windows-msvc`、`x86_64-unknown-linux-gnu`、`aarch64-linux-android`

**验收：** 三个目标都能编译，且 Android 的 `.so` 不依赖 OpenSSL。——已通过（2026-11-05）。

**不通过时：** 如果是 anise 带来的依赖问题，先调整 feature。仍不行就自己实现 SPK Type 2 读取器。

**M0 记录：**

- anise 的默认 feature `metaload` 会引入 ureq，`analysis` 会引入 rayon、csv 等，已全部关闭。关闭后 Android 依赖树里没有 TLS，也没有 `cc` / `-sys` 构建依赖。
- anise 目前最新版是 1.0.0-beta（预发布）。正式版发布后要重新核对 API。
- M0 只用 `cargo rustc --crate-type cdylib` 临时生成过 `.so`。因为没有导出符号，它比最终桥接库小得多，不能用来估算安装包大小。
- GitLab 共享 runner 42（Kubernetes，标签只有 `linux`）在拉取代码时总是报 `could not lock config file //.gitconfig`（HOME 不可写），与项目无关；自动重试也常常落回这个 runner。CI 已用 `tags: [h3c]` 限定到 runner 46（docker）或 47（shell）。根本解决需要 GitLab 管理员修复 runner 42。
- Android 构建命令：`cargo ndk -t arm64-v8a -P 24 build -p guanxiang-cli --release`（需设置 `ANDROID_NDK_HOME`）。

### M1 星历与坐标（2 周）

- [x] 用 anise 实现 `Ephemeris`，读取 de440s（几何位置和速度，M0 已提前完成）
- [x] 时间转换：UTC、TT、TDB、UT1，并实现 ΔT 模块
- [x] 计算视位置：光行时、太阳引力偏折、光行差、岁差章动
- [x] 计算站心位置、地平坐标和月球视差（另有大气折射）
- [x] CLI：`guanxiang position <body> <utc> [--at lat,lon,h]`
- [ ] 在 Android 真机上测试星历加载和单次查询耗时——没有设备，未做；测试程序已备好（`examples/bench_ephemeris.rs`）

**验收：**

- 与 JPL Horizons 对比 2000–2100 年的 100 个以上采样点，地心视位置差 ≤ 0.1″。
  ——**按 D13 调整后通过**：135 个样本，地心视位置与 Skyfield 的最大差 0.0001″；天体测量位置与 Horizons 的最大差 0.008″（月球），行星在 µas 级；站心视位置和地平坐标与 Skyfield 的差 ≤ 0.0004″。
- 真机上每秒至少完成 100 万次日、月、地位置查询（目标值，实测后调整）。——**未验证**，桌面实测为 70–100 万次/秒（见下）。

**M1 记录：**

- Horizons 的视位置与 IAU 2006/2000A 的差异：在 Horizons 的 EOP 实测期内（至 2026 年）只差赤经零点约 +0.05″，赤纬差 < 0.001″；EOP 预报截止（2027-01）后差异随时间增大，2100 年约 0.16″（赤经）和 0.09″（赤纬），与 IAU76 岁差速率误差相符。因此视位置改以 Skyfield 为对照（D13），Horizons 测试保留，检查 EOP 期内天极一致。
- 本库忽略极移。与 Horizons 的地平坐标对比，方位角差约 0.3″·sec(纬度)，特罗姆瑟（69.6°N）约 1.2″，对事件时刻没有影响。M6 卫星凌月接入 IERS 数据时可一并加入极移。
- ΔT 表由 `tools/deltat/gen_table.py` 从 USNO 的 `historic_deltat.data` 和 `deltat.data` 生成，最后一个值为 2026-10-01。**需要定期更新**（建议每次发布前）。表后为外推，界面需提示“不确定”。
- 1962 年以前 Horizons 的 ΔT 与 USNO 历史表差 0.1–0.4 秒，本库采用 USNO 表（与 IERS C04 在 1962 年衔接一致）。
- 桌面（Windows，release）实测：星历加载 38 ms；anise 单次位置查询约 1.1 µs（70–100 万次/秒）；月球完整地心视位置约 1.4 万次/秒，主要耗时在 IAU 2000A 章动。手机按经验慢 2–4 倍，达不到 100 万次/秒。对 M2 的影响和对策：粗搜用几何位置，只在精修时算完整视位置；必要时自写 SPK Type 2 读取器（预计比 anise 的通用查询快 10 倍以上）；同一时刻的多个天体共享岁差章动矩阵。
- 对照数据的生成脚本：`tools/horizons/fetch_fixtures.py`、`tools/skyfield/gen_fixtures.py`，数据进 Git，CI 不联网。

### M2 合冲与凌日（1.5 周）

- [x] 通用粗搜加精修流程（`events` 模块：几何位置粗搜 → 简化模型求根 → 完整视位置精修）
- [x] 行星与日月的合、冲、最小角距（任意两个天体）
- [x] 下合剪枝，以及水星、金星凌日（含四个接触时刻和凌甚）
- [x] 本地可见性过滤（目标视高度、太阳高度；凌日按任一接触或凌甚时太阳在地平线上）
- [x] 预计算星表的存储方案（D14，`events::catalog`）
- [x] CLI：`guanxiang search --kind conjunction|opposition|appulse|transit --from 2000 --to 2100 [--bodies a,b] [--at ...] [--out x.gxev]`

**验收：**

- 21 世纪水星凌日 14 次、金星凌日 2 次，一次不多，一次不少。——**通过**，日期与 NASA 星表逐一相同。
- 事件时刻与 Skyfield 的差 ≤ 5 秒。——**通过**：2000–2100 年行星与太阳的合、冲及 2024–2027 年月球与金星、木星、土星的合共 1779 次，数量一一对应，最大差 0.002 秒；凌甚最大差 0.012 秒，最小角距差 < 0.0001″；月球与金星、土星的角距极小 60 次，最大差 0.08 秒。
- 真机上搜索 100 年一组天体对的时间 ≤ 1 秒（目标值）。——**未验证**（没有设备）。桌面实测见下。

**M2 记录：**

- 事件定义：合、冲为地心视黄经（真黄道、真春分点）之差为 0 或 180°，与天文年历和 Skyfield 相同；角距和凌日用地心视方向。
- 凌日半径取 NASA（Espenak）星表的值：太阳 959.63″（1 AU），水星 2439.7 km，金星 6051.8 km。2019 年水星凌日的接触时刻与 NASA 星表相差 1 秒以内。
- 桌面（Windows，release）100 年搜索耗时：水星与太阳的合 170 ms（631 次）；火星冲 59 ms；木星与土星的合 52 ms；月球与木星的合 327 ms（1328 次）；月球与金星角距 ≤ 5° 427 ms（896 次）；水星凌日 57 ms；金星凌日 32 ms。按手机慢 2–4 倍估算，月球相关的搜索约在 0.7–1.7 秒，可能超出 1 秒目标。
- 已做的优化：精修用割线法（初值误差只有几分钟，3–4 次求值收敛）；同一时刻的两个天体共用地球、太阳状态；黄道矩阵每个事件只算一次（用 `pn06a` 避免重复计算章动）；角距极小先用几何位置定位再精修。月球与木星的合从 628 ms 降到 327 ms。
- 还能做的优化（真机实测后再定）：各事件的精修互相独立，可以多线程并行（手机有 8 核）；自写 SPK Type 2 读取器；月球类事件改为在桌面预计算（D7）。
- Brent 求极小值的容差含 √ε·|x| 项，自变量必须以区间中点为原点，否则用 J2000 起算的秒数（~10⁹）会把精度限制在十几秒。
- Skyfield 的 `find_minima` 在容差很小时会对同一个极小返回一串重复点，生成对照数据时按 0.01 天合并。
- CLI 输出接到 `head` 等提前关闭的管道时会 panic（Rust `println!` 的默认行为），只影响调试使用。

### M3 Flutter 竖切（2 周）

提前打通界面，尽早暴露三端打包问题。

- [x] 在 `app/` 创建 Flutter 应用，接入 flutter_rust_bridge（2.13.0）
- [x] 把 `app/rust` 加入工作区，确认 Cargokit 在工作区内正常构建（Android 已验证）
- [x] 打包星历：三端都把 asset 读成字节交给 `Engine.fromBytes`，Android 不需要释放到磁盘
- [x] 完成基础页面：搜索条件、结果列表、事件详情
- [x] 搜索进度回传和取消（D15）
- [x] 确认 Android 的 16 KB 页大小要求：Android 15 16 KB 页模拟器上运行通过；`librust_lib_guanxiang.so` LOAD 段 0x4000 对齐，`zipalign -c -P 16` 通过

**验收：** Windows、Linux 和 Android 真机都能完成一次凌日搜索，界面不卡顿。——**部分完成**：

| 平台 | 状态 |
|---|---|
| Android 模拟器（Android 15，16 KB 页，x86_64） | 通过：界面可用；集成测试 3 项全过（金星凌日 2004、2012；取消有效） |
| Android 真机 | 未测（没有设备） |
| Windows 桌面 | 未测：Flutter 插件构建需要符号链接，需在系统设置中开启“开发者模式” |
| Linux 桌面 | 未测：WSL 中没有 Linux 版 Flutter SDK 和 GTK/clang/cmake/ninja |

**M3 记录：**

- 构建说明见 `app/README.md`。星历需先从 `data/` 复制到 `app/assets/`（不进 Git）。debug APK 约 97 MB，主要是 32 MB 星历和 debug 版 Flutter 引擎。
- Flutter 默认的 NDK 28.2 本机未安装，`android/app/build.gradle.kts` 固定为 NDK 30.0.16248370（与 M0 交叉编译一致）。
- Gradle 不读 shell 的代理变量，构建时用 `JAVA_TOOL_OPTIONS` 传代理；反过来，`HTTP_PROXY`/`HTTPS_PROXY` 会让 `flutter test integration_test` 连不上设备上的 VM service（应用停在暂停状态），运行测试前要去掉。
- debug 包直接在设备上点开会停在启动画面，需用 `flutter run` 启动。release 包无此问题（待 M7 验证）。
- 桥接层经 flutter_rust_bridge → `dart-sys` 引入 `cc`（编译 Dart API 桩代码）。这是构建期依赖，由 NDK / MSVC / gcc 提供；core 和 CLI 仍为纯 Rust，CI 的依赖检查限定在这两个 crate。
- 模拟器（debug 包，core 未开优化，运行在本机 CPU 上）耗时：星历加载 4.4 s；9 年金星凌日 14 ms；100 年月木合 1.09 s。这些数字**不能代表手机**。星历加载比桌面从文件加载（38 ms）慢得多，主要是 32 MB asset 的读取和复制，M7 裁剪星历时一并处理。

### M4 日月食（3 周）

- [x] 朔望剪枝和食的初筛（朔、望时月球黄纬超过 1.65°、1.7° 直接跳过）
- [x] 月食：半影、偏食、全食，P1/U1/U2/U3/U4/P4，地影放大模型可配置（Danjon 默认，Chauvenet 可选）
- [x] 日食：贝塞尔根数、类型判定（全、环、全环、非中心、偏）、食甚、γ、食分
- [x] 本地情况：日食 C1–C4、本地类型、食分、食面积比、太阳高度；月食各接触的月亮高度；中心线和食带宽度（全食带边界线留待以后）
- [x] 全球事件预计算：`guanxiang eclipse --from 1900 --to 2101 --out eclipses.gxev`，912 次，桌面 2.1 秒，44 KB
- [x] App 支持日食、月食搜索和本地情况

**验收：**

- 21 世纪日食 224 次、月食 228 次，类型与 NASA 星表一致。半影月食边界如有差异，要逐条解释。
  ——**通过**：次数和类型逐条一致（含 7 次全环食、3 次非中心食，以及只差 0.0008 的 2015-04-04 月全食），没有需要解释的边界差异。
- 最大食时刻与 NASA 星表的差异可由 ΔT 和模型差异解释。——**通过**：食甚时刻（TD）差日食 ≤ 0.54 秒、月食 ≤ 2.3 秒；地心几何不依赖 ΔT，剩余差异来自星历（DE440 与 VSOP87/ELP）。

**M4 记录：**

- 太阳和月球都用地心**视位置**（与《天文年历补编》、NASA 一致）。最初月食用天体测量位置、影轴取太阳几何方向的反向，食甚系统性晚约 78 秒：在随地球运动的参考系里，地影轴是视太阳（含光行差）的反向；月球的天体测量方向含约 20″ 的 BCRS 光行时修正，只有加上光行差才等于真实地心方向。
- 地影放大：Danjon 与 NASA 五千年月食星表一致（食分差 ≤ 0.0002）；Chauvenet 会多出 2 次半影月食、1 次类型不同（2042-09-29），食分系统偏大约 0.03（半影）和 0.009（本影）。
- 月球半径按 NASA 约定：半影 k₁ = 0.2725076，本影和伪本影（全食、环食）k₂ = 0.2722810。本地环食最初用 k₁，持续时间差到 6.8 秒，改用 k₂ 后 ≤ 0.64 秒。
- 其他与 NASA 的对比：中心食的 γ、食分差 ≤ 0.0001；食甚点经纬度和太阳高度差 ≤ 0.5°（NASA 取整到 1°）；食带宽度差在 1% + 1 km 以内；食甚点的全食/环食持续时间差 ≤ 0.64 秒。偏食的食分差 ≤ 0.003（“离影轴最近的地面点”用基本面投影椭圆近似）。
- 食甚点经纬度和本地情况依赖 ΔT；与 NASA 比较时传入 NASA 的 ΔT（`greatest_point_with_delta_t`、`local_solar(.., Some(dt))`）。
- 全食带的南北界线还没做（只有中心线和宽度），M7 或之后在地图上显示时再补。
- 对照数据：`tools/nasa/parse_catalog.py` 把 NASA 网页转成 `tests/fixtures/nasa/*.csv`。

### M5 月掩星（1.5 周）

- [x] 月掩行星（站心计算），也支持月掩恒星
- [x] 精简星表和自行修正：Hipparcos V < 6.0、黄纬 |β| < 6.6° 共 550 颗（`stars` 模块），自行线性外推，含视差
- [x] 本地掩始、掩终时刻，及月亮、太阳高度
- [x] 全星表批量候选搜索（月球位置每步只算一次）；CLI `guanxiang occultation`；App 支持

**验收：** 随机抽取至少 20 个已知事件，时刻与权威预报或 Skyfield 的差 ≤ 5 秒。——**通过**：2024–2030 年 3 个测站、4 颗亮星和 4 颗行星共 92 次掩星，掩始、掩终与 Skyfield 的差 ≤ 0.003 秒；用本库 ΔT 模型时每组次数与 Skyfield 相同。

**M5 记录：**

- 掩始、掩终定义为月面边缘（k = 0.2725076）经过目标中心，站心视位置。行星圆面的外切、内切和掠掩（月面地形）还没做。
- 星表来源：CDS（VizieR、cdsarc）从本机访问超时，改用 NASA HEASARC 上的 Hipparcos 主星表（内容与 CDS I/239 相同）。生成脚本 `tools/stars/gen_occultation_stars.py`。
- 对照数据用 Skyfield 独立求解（`tools/skyfield/gen_occultations.py`），恒星参数从本库星表读取，每个事件记录 Skyfield 的 ΔT。毕宿五 2023 年后一轮掩星结束，2024–2030 年 0 次，符合实际。
- 桌面上搜索北京 2026 年全部行星和 550 颗亮星的月掩星：109 次，0.9 秒。

### M6 卫星凌月（3 周）

- [x] 用 `sgp4` 解析 OMM 并预报，确认输出坐标系（TEME；**必须用 WGS72 常数**，见记录）
- [x] TEME 到地固系转换，加入 UT1-UTC（GMST82(UT1)，忽略极移；UT1 由 ΔT 模型或传入值给出）
- [x] 预报过境，计算最小角距（`events::sat_transit`，卫星方向含光行时和周日光行差）
- [x] 计算地面中心线、带宽、持续时间和离带距离
- [x] CLI：`guanxiang satellite --omm iss.json --at lat,lon,h`
- [x] Dart 层拉取并缓存数据，遵守 CelesTrak 频率限制，非 200 响应时停止请求（`app/lib/src/celestrak.dart`）
- [x] Android 用 WorkManager 后台刷新（每 6 小时，仅联网时；仍受 2 小时频率限制）
- [x] 显示根数龄期；比较新旧预报，时刻变化 > 1 秒或中心线移动 > 1 km 时提醒，龄期 > 3 天也提醒
- [x] 地图上显示中心线（flutter_map + OpenStreetMap 瓦片）
- [x] 复用同一套逻辑支持卫星凌日（太阳和月球同一函数）；涉及太阳的结果和卫星页都显示观测安全提示

**验收：**

- 空间站和天宫至少 10 次预报与 transit-finder 对比，时刻差 ≤ 0.5 秒，中心线差 ≤ 500 米。
  ——**以 Skyfield 代替部分通过**：同一份 CelesTrak OMM、6 个测站、7 天内 69 次角距 < 10° 的接近，时刻差 ≤ 0.007 秒，角距差 ≤ 0.35″（剩余差异是本库多计入的光行时和周日光行差）。与 transit-finder 的逐条对比尚未做（需要手工从网站取数）。
- 至少 1 次实际观测或公开影像核对。——未做。

**M6 记录：**

- sgp4 crate（2.4）的 `Constants::from_elements` 默认用 **WGS84** 引力常数，而 NORAD 根数是按 WGS72 拟合的；python-sgp4（Skyfield）和 Vallado 参考实现默认 WGS72。用 WGS84 时与 Skyfield 的位置差 1 天约 12 m、7 天达百米级，对应凌日时刻差约 0.03 秒。改为自行构造 `Constants::new(WGS72, iau_epoch_to_sidereal_time, …)` 后，TEME 位置与 Skyfield 在 1 mm 内一致。
- 地面中心线：每个时刻从卫星沿“目标 → 卫星”方向延长到 WGS84 椭球的交点；可见带半宽近似为“离中心线距离 × 视半径 / 最小角距”。
- 根数从文件或字符串传入（D5），网络请求留给 Dart 层。测试数据 `tests/fixtures/satellite/omm_iss_css.json` 为 2026-11-04 的 CelesTrak 数据。
- Skyfield 的 `find_minima` 在容差很小时采样点会暴涨（曾占用 24 GB 内存），对照数据脚本改为批量计算加抛物线插值。
- 桌面上两颗卫星 7 天的搜索用时约 0.3 秒。
- 缓存（`OmmStore`）：`<应用支持目录>/omm/<编号>.json` 为当前根数，`<编号>.prev.json` 为上一份（历元变化时轮换），`meta.json` 记录每颗卫星的下载时间、出错暂停时间和关注列表。同一颗卫星 2 小时内只请求一次（CelesTrak 约 2 小时更新一次）；任何非 200 响应后本次运行不再请求，并持久化暂停 2 小时，后台任务同样遵守。网络不通不算出错。User-Agent 为 `guanxiang/0.1 (+项目地址)`。
- 后台任务运行在独立 isolate 里，只刷新缓存，不加载 Rust 和星历；根数是否有效用 Dart 解析 JSON 判断。
- 新旧预报比较在桥接层做（`satellite_transits` 的 `previous_omm_json`）：旧根数里 120 秒内的同一天体事件视为同一事件；中心线移动量为旧预报的中心线最近点到新中心线的距离。
- 桥接层的结果附带 ±10 秒、每 0.5 秒一点的中心线供地图使用；地图需要联网，离线时只是底图空白。
- 集成测试在模拟器上用同一份根数复现北京的 6 次天宫近日事件，与 Skyfield 时刻差 < 0.05 秒。6 项集成测试全部通过（模拟器 debug 包：星历加载 8.0 秒，100 年月木合 1.7 秒）。
- 构建：workmanager 插件的 Kotlin 源码在 pub 缓存（C 盘），工程在 A 盘，Kotlin 增量编译会失败，已在 `android/gradle.properties` 关闭增量编译。原 2 GB 内存的模拟器上测试工具反复掉线，换成 6 GB、6 核的 `guanxiang_api35_16k_hi` 后正常。

### M7 发布（2 周）

- [x] 确定星历裁剪范围和安装包大小：内置 de440s 的 1899-12 至 2101-02 部分（22 MB），arm64 release 包 49.0 → 39.2 MB；真机性能待测
- [x] 中英文界面、错误提示（离线时：根数用缓存并说明原因，地图底图空白、数据照常显示）
- [x] Android 发布版：上传密钥签名（密钥在仓库外，配置在不进 Git 的 `android/key.properties`），版本 0.1.0；arm64 包 39.7 MB，16 KB 对齐
- [ ] Windows 和 Linux 安装包（需先开启 Windows 开发者模式、安装 Linux 桌面工具链）—— **v0.1.0 只发布 Android**，桌面版留到下一版
- [x] 第三方许可声明，包括 SOFA 致谢（“关于与许可”页）
- [x] 确认 CelesTrak 数据使用方式（已符合其使用政策）；用户量较大时增加缓存服务 —— 以后再说
- [x] 确认 OpenStreetMap 瓦片使用政策，并按政策设置

**M7 记录：**

- 星历裁剪：`crates/guanxiang-core/examples/trim_spk.rs` 用 anise 的 `truncate` + `set_nth_data` 删掉范围外的整条切比雪夫记录，不重算系数。anise 写出时不更新 DAF 文件记录的 FREE 指针，SPICE、jplephem 读不了，工具里按删除的双精度个数修正。校验：随机 20 万个时刻、全部天体，anise 读出的位置与原文件逐位一致；jplephem 能读，差 < 3 cm（段起点变化导致的浮点舍入）。core 全部测试改用裁剪版星历也都通过。结果可复现（SHA-256 `1b7ff150…afaa`），CI 每次重新生成并校验。
- 冥王星（段 9，0.4 MB）也用不到，但为了让裁剪版只是 de440s 的时间子集，保留。
- 安装包构成（arm64 release，裁剪前）：星历 31.1 MB（双精度系数几乎不能压缩）、Flutter 引擎 11.8 MB、Dart AOT 6.1 MB、Rust 库 1.6 MB。
- 性能（模拟器 profile 包，x86_64，不能代表手机）：星历加载 105 ms（debug 包 8 s，主要是 debug 模式的 asset 复制），9 年金星凌日 10 ms，100 年月木合 671 ms。
- `flutter test integration_test` 不支持 `--profile`，性能数据用 `flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart`。
- 许可声明：Flutter 自动收集 Dart 包和引擎的许可证；Rust 依赖由 `tools/licenses/gen_rust_notices.py` 从 `cargo metadata` 收集（Android、Windows、Linux 的运行时依赖，117 个 crate，相同文本合并），写成 `app/assets/licenses/rust.txt`，在应用里注册到 `LicenseRegistry`。anise 没有附带许可证文件，使用 hifitime 的 MPL-2.0 文本，并写明两个 MPL 组件的源码地址。另加“算法与数据来源”一条：DE440、SOFA（声明不是 SOFA 官方软件）、USNO/IERS ΔT、Hipparcos、CelesTrak、SGP4、OpenStreetMap。依赖变化后要重新运行脚本。
- CelesTrak 使用政策（celestrak.org/usage-policy.php）：每份数据每次更新只下载一次（GP 数据约 2 小时更新），收到任何非 200 响应立即停止请求，否则 IP 会被封。现有实现符合。用户共用一个出口 IP（NAT）时可能一起被限，用户量大时考虑自建缓存。
- 错误提示：Rust 的 `anyhow` 错误到 Dart 是 `AnyhowException`，`describeError` 只保留第一段（去掉原因链和调用栈）；网络错误、超时单独说明。搜索前按星历覆盖范围检查年份（1900–2100），超出时直接提示，不再进入 Rust。
- 中英文界面：Flutter `gen-l10n`（`lib/l10n/app_zh.arb` 为模板，`app_en.arb` 为英文），跟随系统语言，既不是中文也不是英文时用英文。事件标题、详情等由 Rust 桥接层生成，`SearchRequest.lang`、`satellite_transits(lang)`、`body_names(lang)`、`sun_safety_notice(lang)` 按语言输出；有中文名的 18 颗恒星在桥接层另有英文名（单元测试保证一一对应）。core 内部的错误信息目前只有中文。CelesTrak 刷新结果、年份校验改为返回状态，由界面按语言生成文字（后台任务没有界面上下文）。单元测试检查中英文 ARB 的键一致。
- 恒星中文名更正：“氐宿一”原误标在 HIP 76333（γ Lib）上，改为 HIP 72622（α² Lib）；“毕宿四”原误标在 HIP 20889（ε Tau）上，改为 HIP 20205（γ Tau）；“毕宿六”（HIP 20894，θ² Tau）未能核实，暂去掉名字，显示为 HIP 编号。其余 16 个名字与西名一致。以后增加星名时应对照权威的中西星名对照表。
- OSM 瓦片政策（operations.osmfoundation.org/policies/tiles）：用本应用自己的 User-Agent（与 CelesTrak 请求相同）；每块瓦片至少缓存 7 天（flutter_map 内置缓存，上限 200 MB）；地图右下角显示来源；不做离线或批量下载。瓦片地址集中在 `sat_transit_page.dart` 的 `tileUrlTemplate`，用量大时换自建或商业瓦片。

**验收：** 三个平台的安装包都在干净环境中完成安装和完整流程测试。

### 看板“今晚”：日月出没、晨昏、月相

**记录：**

- 定义与 USNO、Skyfield `almanac` 相同：日月出没是上边缘与地平线相切，用站心几何高度判断，阈值为 −(34′ + 视半径)（太阳半径 695 700 km、月球 1 737.4 km，月球用站心距离，即含视差）；民用、航海、天文晨昏是太阳中心几何高度 −6°、−12°、−18°。每 10 分钟取样，Brent 法精修到 0.1 秒；10 分钟内先升后落（高纬度擦过地平线）的情形会漏掉。
- 对照（`tools/skyfield/gen_almanac.py`，Skyfield 1.55，同一份 de440s，按相同定义用 `find_discrete` 求解，ΔT 取 Skyfield 的值）：北京、悉尼、基多（海拔 2850 m）、雷克雅未克、特罗姆瑟（北极圈内，有极昼极夜）5 地，2026 年每月 1 日和 15 日各 24 小时，共 1045 个事件。每个窗口的事件数完全一致（包括极昼、极夜时整天没有某类晨昏），时刻差最大 0.026 秒，主要是精修容差。
- 应用里用内置 ΔT 模型，2026 年与 Skyfield 的 ΔT 相差不到 0.15 秒，出没时刻随之相差同样的量。
- 月相：照亮比例 k = (1 + cos i)/2，相位角 i 由地心视位置的日月角距和距离求出（Meeus 48.2、48.3）；盈亏看真黄道视黄经差。与 Skyfield `fraction_illuminated`、`moon_phase` 比较（2026 年 48 个时刻）：照亮比例差 0.00006，黄经差 0.0001″。下次朔、望用已有的合冲搜索（月球与太阳的合、冲）。
- 应用里，“今晚”取本地中午到次日中午（凌晨 6 点前取前一天中午起），日落、天文晨昏结束、天文晨光开始、日出，以及这段时间里的月出月落；整晚都没有某类晨昏时显示“—”，并说明极昼或白夜。

### 日月食示意图

- 月食（`lunar_eclipse::diagram`）：地心视方向下，月心相对影轴（视太阳反方向）的切平面坐标（度，x 向东、y 向北），每 5 分钟一个点，覆盖 P1 前 30 分钟到 P4 后 30 分钟；地影半径用 Danjon 模型，与搜索一致。界面北在上、东在左（抬头所见），与 NASA 星表的月食图相同。自洽检查：各接触时刻月心到影轴的距离等于影半径 ± 月球半径，差 < 0.002°；2025-09-07 本影半径 0.736°（NASA 0.7357°）。
- 日食（`SolarEclipse::diagram`）：贝塞尔根数的 x、y（影轴在基本面上，地球赤道半径），从半影接触地球到离开地球，每 5 分钟一个点；食甚时的 l1、l2 画半影圈和本影点，影轴赤纬 d 用来画赤道和地轴。自洽检查：食甚时 √(x²+y²) 与 |γ| 相差 < 0.001（2026-08-12 γ = 0.8977，与 NASA 一致）。
- 只在详情页显示（需要 `Engine`），后台任务的报告页不显示。

### 月食详情页

- 桥接 `lunar_eclipse_detail`：按时间排列的食相（含月下点）、三段持续时间、沙罗序列；给出观测地时再算各食相的月亮高度（含折射）和方位、太阳高度、沿示意图轨迹每 5 分钟的月亮高度、P1 前 1 小时到 P4 后 1 小时的月出月落，以及可见情况（按 U1–U4，半影月食按 P1–P4：全程可见、月出带食、月落带食、看不到）。观测地用手动位置或缓存的定位，详情页不主动定位。
- 沙罗序列（`events::saros`）：按朔望月序号（与 NASA Luna Num 相同）查表，表由 `tools/nasa/gen_saros_table.py` 从 NASA 沙罗目录生成，只收 1899–2101 年间有月食的 47 个序列。21 世纪 228 次月食的序列号与 NASA 全部一致；第几次也与 NASA 序列页一致（2025-09-07 为沙罗 128 第 41 次，共 71 次）。
- 持续时间由接触时刻相减，与 NASA 星表相比：半影食 ≤ 0.19 分钟、本影食 ≤ 0.14 分钟、全食 ≤ 0.33 分钟（全食很短时接触角度掠射，对模型差异更敏感）。
- 月下点（`astrometry::sub_body_point`）：地心视方向的 CIRS 赤纬，经度 = CIRS 赤经 − ERA，地球按球体处理、忽略极移；与 Skyfield（ITRS 球面经纬度）相差纬度 ≤ 0.0001″、经度 ≤ 0.005″。sofars 0.6.2 的 `anpm` 对负角度归一化有误，改用自己的 `wrap_pi`。
- 全球可见区域图：底图是 Natural Earth 1:110m 陆地（公有领域，`tools/geo/gen_land.py`），等距圆柱投影，以食甚月下点经度为中心；按 2° 网格用初亏、复圆时的月下点算地心高度分区，各接触时刻的地平线是与月下点相距 90° 的大圆。没有计入折射和视差，边界附近约差 1°。
- 月面模拟：以地影中心为圆心的径向渐变（本影古铜红、半影由暗到亮），只是示意；全食的实际亮度和颜色无法预报（丹戎等级）。

### 日食详情页

- 桥接 `solar_eclipse_detail`：示意图、沙罗序列、中心线（每分钟）和食带宽度、全球最大食分栅格；给出观测地时再算本地类型、食分、食面积、C1–C4 的太阳高度和方位、全食或环食时长、到中心线的距离和方向、可见情况（全程可见、带食日出、带食日落、看不到、这里不食），以及太阳面模拟轨迹。页首始终显示 ISO 12312-2 安全提示。
- 沙罗序列：日食表同样由 NASA 沙罗目录生成（48 个序列，目录里每张分表首行重复上一个序列，已去重）；21 世纪 224 次日食的序列号与 NASA 全部一致，2027-08-02 为沙罗 136 第 38 次（共 71 次），与 NASA 序列页一致。
- 最大食分栅格（`SolarEclipse::max_magnitude_grid`）：半影与地球相交期间每 2 分钟取一次贝塞尔根数，逐格（2°）求观测点的 (ξ, η, ζ)，只取太阳在地平线以上（椭球法向与影轴夹角 < 90°）的时刻，食分 = (L1′ − Δ)/(L1′ + L2′)。与站心计算的本地食分（`local_solar`，独立算法）比较，2027-08-02 马德里、伦敦、开罗、雅典、内罗毕相差 ≤ 0.0005（取样 20 秒）。桌面调试版算一张 2° 栅格约 0.2 秒。
- 太阳面模拟（`local_eclipse::solar_disk_views`）：站心视方向转到 CIRS，在太阳处的切平面上求月心偏移，日月视半径与 `local_solar` 相同（月球用 k₁），食面积用 `overlap_fraction`；画面按太阳处的天顶位置角旋转成天顶朝上。自洽检查：C1、C4 时两圆外切差 < 0.05″，食甚食面积与 `local_solar` 一致。轨迹每 30 秒一个点，全食或环食阶段每 2 秒一个点。
- 全球食况图：复用月食的离线世界地图，栅格按 0.1 分档填色，等值线用 marching squares 求食分 0、0.2、0.5、0.8；食带由中心线两侧各偏移半个食带宽围成。没有计入折射，边界附近约差 1°。

### 分享图

- 日月食详情页顶栏的分享按钮打开预览页，生成分享图：事件名、本地日期时刻、倒计时，月食画食甚时的月面（1080 × 1350，4:5）；日食画本地食甚时的太阳面（这里不食或没有观测地时按全球类型示意），下面加一张左右贴边的全球食况地图（与详情页共用 `SolarPathMap`），宽 1080、高度按内容撑开（约 1650～1800，打开观测地或英文折行时更高，不会溢出）；三项关键数字，沙罗序列，右下角是官网二维码（`qr_flutter`，纠错等级 L，图缩到 40% 仍能用 OpenCV 识别）。日食图上始终有 ISO 12312-2 安全提示。
- 观测地默认不上图；预览页里打开“显示观测地”后，只写取整到 1° 的经纬度。
- 分享图始终用深空主题，与应用当前主题无关。Android、Windows 调起系统分享（`share_plus`），Windows、Linux 可以另存为 PNG（`file_selector`）；Linux 的 share_plus 不支持分享文件。

**v0.1.0（2026-11-06）**：只发布 Android（arm64-v8a、x86_64 两个 APK），附在 GitLab Release `v0.1.0`，文件存放在项目的 Generic Package Registry（`guanxiang/0.1.0/`）。已在 Android 15（16 KB 页）模拟器上验证；真机尚未测试。

### Web 应用（规划中）

目标：把 guanxiang-core 编成 WebAssembly，做浏览器版（`app.guanx.huxulm.dev`），首版做日月食的搜索、详情和可交互动画（替代 Manim 的离线视频流程）。前端用 TS + Vite + Svelte 5 + Tailwind 4，3D 地球用 three.js，wasm 跑在 Web Worker 里。分阶段：P0 技术验证 → P1 新建 `guanxiang-view`（从 CLI `scene` 和桥接层抽出纯计算）和完整的 wasm 接口 → P2 `webapp/` 骨架 → P3 动画与视频导出 → P4 CI 和部署。

**P0 技术验证记录（2026-11-10）：**

- `guanxiang-core` 不改代码就能 `cargo check --target wasm32-unknown-unknown`：anise 关掉默认 feature 后，memmap2 在 wasm 上只编进 stub（只要不调 `from_path`）；hifitime 自带 `web-time`。
- 星历加载：浏览器里没有文件系统，字节由 JS 传入。core 新增 `AniseEphemeris::from_vec`，用 `Vec → Bytes → BytesMut` 接管内存，比 `from_bytes` 少复制一份（22 MB）。
- `crates/guanxiang-wasm`：wasm-bindgen 封装 `Engine`（构造时传入星历字节）和 `lunarEclipses(from, to)`（返回 JSON 字符串）。计算部分是普通 Rust 函数，本机 `cargo test` 直接测。
- 体积：`wasm-pack build --release`（含 wasm-opt）后 508 KB，gzip 226 KB。星历 `de440s_1900_2100.bsp` 22 MB，gzip 后还有 20.8 MB，是首次加载的主要开销。
- 速度（Node 24，V8，与浏览器相近）：模块初始化 3.5 ms，加载星历 19 ms，搜索 1 年月食 25 ms，10 年（2025–2034，23 次）66 ms。本机 release 加载加 10 年搜索共约 0.06 s，同一量级。加载星历后进程内存约增加 43 MB。
- 与本机 Rust 结果逐项比对（同一份裁剪星历，2025–2034 共 23 次月食）：类型、条数全部一致；接触时刻差 ≤ 1.2×10⁻⁷ s（TT 秒数的末位舍入）；γ、食分差 ≤ 7×10⁻¹⁰；食甚时刻差 ≤ 8.6 ms。食甚由求极小值得到，极小值附近函数平坦，wasm 与本机数学库（sin、asin 等）末位舍入不同，迭代就停在略有不同的位置；这一差别远小于与 NASA 的对照基准（≤ 2.3 s）。

**P1 Rust 层记录（2026-11-10）：**

- 新建 `crates/guanxiang-view`（展示数据层，CLI 和 wasm 共用，不含 frb、clap、wasm-bindgen）：
  - `scene`：CLI `scene` 的三个构建函数原样搬过来，拆成“按日期找最近一次食”和“由选定的食生成场景”两步。CLI 只保留参数和输出。重构前后用 5 组参数（月食有无观测地、两次日食、行星轨迹）导出的 JSON 逐字节一致，`tools/manim` 不受影响。
  - `list`：按年份搜索日月食，每条带沙罗序列；日食带食甚点、食带宽度。
  - `state`：逐帧求值。月食给出月心在地影切平面上的位置、该时刻的影半径和瞬时食分、月亮高度；日食给出贝塞尔根数（含 μ）、日下点、影轴地面点、观测地日面。时间用相对食甚的 TT 秒数，与场景序列的 `t_rel_s` 一致。
- core 只新增公开接口，算法不变：`lunar_eclipse::shadow_state`、`SolarEclipse::elements_at`、`SolarEclipse::central_point_at`、`BesselianElements::hour_angle`（μ = GAST − a）。
- 自洽检查（`guanxiang-view` 单元测试）：
  - 逐帧求值的食甚点与示意图完全相同；
  - 月食 U1、U2 时月心到影轴距离 = 本影半径 ± 月球半径，差 < 0.002°；
  - 2027-08-02 中心线上每个点，逐帧求值与中心线完全相同；用 x、y、d、μ 按 Explanatory Supplement 公式（WGS84）换算的地面点与之相差 < 1×10⁻⁶°；
  - 卢克索本地食甚的食面积与 `local_solar` 差 < 1×10⁻⁶。
- wasm 接口：`Engine`（`lunarEclipses`、`solarEclipses`、`lunarEclipse(date)`、`solarEclipse(date)`），选定的食返回句柄，提供 `scene(...)` 和 `stateAt(t_rel_s, ...)`，逐帧求值不用重新搜索。结果仍是 JSON 字符串，字段统一用 snake_case，与场景一致。原计划用 tsify 生成 TS 类型，现改为在 P2 手写 TS 类型声明，这样 JSON 格式只在 Rust 一处定义，Manim 和网页读同一种格式。
- 与本机逐项比对（Node，同一份裁剪星历）：列表、场景、逐帧状态的结构全部一致。场景和逐帧状态的数值差 ≤ 5×10⁻¹³（日食带宽 km）。列表里食甚时刻差：月食 ≤ 8.6 ms，日食 ≤ 21 ms；日食食甚点位置随之差 ≤ 5×10⁻⁵°，都来自求极小值。
- 耗时（Node 24，冷启动后第一次调用）：10 年月食列表 154 ms、日食列表 132 ms；月食场景（60 s 步长、带观测地）116 ms，日食场景 313 ms。逐帧求值：月食 0.44 ms，日食 0.66 ms（不带观测地）、1.03 ms（带观测地），满足 60 fps。wasm 体积 669 KB，gzip 287 KB。

**P2 Web 应用骨架记录（2026-11-10）：**

- `webapp/`：Vite 8 + Svelte 5 + TypeScript + Tailwind 4，依赖只有 Comlink。计算在 Web Worker 里：加载 wasm、下载星历、搜索和生成场景都不占主线程。
- 星历：Worker 用 `fetch` 流式下载并显示进度，SHA-256 与 CI 的 `TRIMMED_SHA256` 一致才加载，存进 Cache Storage（缓存键带 SHA-256，换星历自动重新下载）。第二次打开直接读缓存。本地开发和 `vite preview` 由 Vite 中间件在 `/ephem/` 下提供；线上地址用 `VITE_EPHEM_URL` 指定（R2，部署时再配）。
- 首屏不依赖星历：`npm run data` 在构建时用同一个 wasm（Node）算出去年到 20 年后的日月食，生成 `public/data/eclipses.json`（2025–2045 年月食 47 次、日食 46 次，约 38 KB，用时 0.4 s）。按年份搜索才需要星历，按年分块、可取消。
- 页面：首页（近期日月食，按类型筛选，可包括已过去的；按年份搜索）、月食详情、日食详情（`/lunar/YYYY-MM-DD`、`/solar/YYYY-MM-DD`，可带 `?lat=&lon=&h=` 指定观测地）。详情页有全球情况、各食相时刻（带观测地时加上高度和可见情况，分类与 App 相同）和静态示意图（地影切平面、贝塞尔基本面），交互动画留给 P3。日食页始终显示 ISO 12312-2 安全提示。
- 主题与文案：三套主题的色值取自 `theme.dart`，写成 CSS 变量；`npm run check` 检查红光主题每个颜色 R 分量最大。文案优先复用 App 的 ARB（Vite 虚拟模块直接读取），App 里没有的放在 `web-strings.ts`，中英文键由 TypeScript 类型保证一致。观测地可选常用城市、浏览器定位或手动输入，只存 localStorage。
- 核对（Playwright，390×844 和 1280×860，浅色、深空、红光，中英文）：2025-09-07 月食（北京）本影食分 1.3619、全食 82 分钟、食甚 18:11:48 UT，与 NASA 一致；2027-08-02 日食（卢克索）全食 6 分 21 秒，食带宽 258 km。页面没有横向溢出，控制台没有错误或警告。在浏览器里按年份搜索 2026–2036 年（50 次）用时 0.32 s。
- 体积：JS 133 KB（gzip 48 KB，含两种语言的全部 ARB 文案），CSS 29 KB（gzip 5 KB），wasm gzip 297 KB；星历 21 MB 只在第一次需要计算时下载。
- 已知问题：时间按浏览器所在时区（或 UTC）显示，不按观测地时区；“未找到”靠匹配 Rust 返回的中文错误信息判断，以后改成错误码。GitLab runner 没有外网，webapp 只在 GitHub CI 构建。

**P4 部署记录（2026-11-10，部分）：**

- 星历上传到 R2 存储桶 `huxulm-asia`：`guanxiang/ephem/de440s_1900_2100-1b7ff150.bsp`（文件名带 SHA-256 前 8 位，`Cache-Control: immutable`），从公开地址 `s2.huxulm.dev` 下载回来 SHA-256 一致。
- 存储桶原来没有 CORS 配置，新设一条：只允许 `https://app.guanx.huxulm.dev` 和 `http://localhost:4173` 以 GET、HEAD 读取，暴露 `Content-Length`、`ETag`；其他来源拿不到 CORS 头。
- `webapp/.env.production` 写入线上星历地址；`vite preview` 本地验证生产包能跨域下载并校验星历。
- `npx wrangler deploy` 发布到 https://app.guanx.huxulm.dev （Workers 静态资源，单页应用回退）。线上核对：各路由 200，wasm 为 `application/wasm`，2027-08-02 卢克索的接触时刻与本地一致，控制台没有错误。
- 还没做：GitHub Actions 自动部署（目前手动发布）、发版流程里同步更新 webapp。

**P3 交互动画记录（2026-11-10）：**

- 共用时间轴：播放、暂停、拖动、×60/×300/×1200 倍速（默认约 30 秒放完）、一键跳到各接触时刻；当前时刻和所处食相随时显示。每一帧都由 Worker 调 wasm `stateAt` 精确求值，不在前端插值；同一时间只有一个请求在途，拖动时只算最新的时刻。播放实测 60 fps，画面每秒更新约 60 次（Playwright，桌面 Chromium）。
- 月食：地影总览（地影切平面，北上东左，按此刻的本影、半影半径）和月面特写（把本影、半影圆裁剪到月面上，按真实几何画出影子边缘；颜色只是示意），以及本影/半影食分曲线和月亮高度曲线。
- 日食：
  - 从太阳看地球：直接用贝塞尔基本面做正射投影，没有用 three.js。这个视角下半影、本影正好是圆，地球是 y 半轴为 ρ₁ 的椭圆，陆地、赤道、中心线、观测地按此刻的 d、μ 投影，只画朝向太阳的一面。
  - 观测地看到的太阳：天顶朝上（按天顶位置角旋转），临边昏暗；太阳在视野内接近地平线时画出地面。只有月面在几何上完全盖住日面时才画日冕：食既前几秒还剩一线日面，这时画日冕会让人误以为可以摘下滤光片。
  - 世界地图：半影边界（基本面上半径 l1 的圆逐点沿影轴投到地面）、影轴地面点、中心线、晨昏线和夜晚、日下点、观测地。
  - 食面积和太阳高度曲线。有观测地时可以在“本地全过程”和“全球全过程”两种时间范围之间切换。
- 前端几何核对（`npm run test:geometry`，CI 也跑）：6 次日食（含环食，影轴赤纬正负）共 479 帧，JS 由 x、y、d、μ 反算的影轴地面点与 Rust 的 `shadow_center` 最大差 3.5×10⁻¹⁰°，地面点正向投影回基本面与 (x, y) 最大差 8.8×10⁻¹³ 地球半径。
- 陆地轮廓（与 App 共用 `land_110m.json`）单独打包，只在日食页加载（gzip 19 KB）；主包 gzip 57 KB。
- 截图核对：浅色、深空、红光，390 和 1280 宽度；2025-09-07 月食（北京）食甚和偏食阶段，2027-08-02 日食（卢克索）全食，2026-08-12 日食（马德里，日落前的偏食）。
- 已发布到 https://app.guanx.huxulm.dev （2026-11-10，手动 `wrangler deploy`）。线上核对：卢克索食甚时显示日冕、食分 1.035，播放时“从太阳看地球”视图每秒更新约 60 次，陆地轮廓按需加载，月食页正常，控制台没有错误。
- 还没做：视频导出（WebCodecs）和 9:16 竖屏演示模式；太阳很低时，日面特写的视野（约 ±0.7°）要到最后几分钟才能看到地平线。

## 6. 验证方法

| 对象 | 对照来源 |
|---|---|
| 天体位置 | JPL Horizons、Skyfield |
| 视位置（IAU 2006/2000A） | Skyfield（同一份 de440s） |
| 坐标和时间尺度 | SOFA 官方测试值，`../SuperNOVAS` 可作为另一份参考 |
| 事件完整性 | NASA 日月食和凌日星表 |
| 月掩星 | Skyfield（同一星表参数，独立求解） |
| 日月出没、晨昏、月相 | Skyfield（相同定义，独立求解） |
| 沙罗序列、月食持续时间 | NASA 五千年日月食星表和沙罗目录 |
| 日食最大食分栅格 | 本地日食情况（站心计算，独立算法） |
| 月下点 | Skyfield（ITRS 球面经纬度） |
| 卫星凌月 | transit-finder、实际观测 |

- 对照数据固定保存在测试夹具中，CI 不依赖外部网络。de440s 存放在本项目的 Generic Package Registry（`ephemeris/de440/de440s.bsp`），CI 用 job token 下载并校验 SHA-256；CI 中星历测试不允许被跳过。
- 与 NASA 星表比较时要注意它用的是 VSOP87 + ELP 和自己的 ΔT，秒级差异不一定是错误。
- 每个事件类型至少有一份“数量不漏”和一份“时刻精度”测试。

## 7. 主要风险

| 风险 | 影响 | 应对 |
|---|---|---|
| anise 在 Android 上带来编译或依赖问题 | 阻塞 M0 | 已解决：关闭默认 feature 后可交叉编译 |
| anise 仍是 1.0.0-beta，API 可能变 | 升级时要改代码 | anise 只在 `ephemeris.rs` 中使用（D9），影响范围小 |
| 手机性能或内存不足 | 影响体验 | 预计算、裁剪星历、粗搜阶段用低精度模型 |
| ΔT 的不确定性 | 远年代和未来结果不准 | 界面标明精度随年代下降，只开放有依据的范围；ΔT 表每次发布前更新 |
| anise 查询速度不够 | 手机上月球类搜索可能超过 1 秒 | 已做：粗搜用几何位置、割线法精修、共享状态。待真机实测后再决定：并行精修、自写 SPK Type 2 读取器、或改为桌面预计算 |
| 月面地形影响日食接触时刻 | 秒级误差 | 第一版不做地形修正，后续再评估 |
| 卫星变轨或根数过期 | 预报失效 | 显示龄期、临近再次刷新、比较新旧结果 |
| CelesTrak 限流或政策变化 | 卫星功能中断 | 严格缓存，只请求少量目标，必要时自建缓存 |
| 第三方许可 | 发布受限 | 发布前核对 SOFA、MPL-2.0 和数据来源条款 |

## 8. 待定事项

| 事项 | 需要决定的时间 | 当前倾向 |
|---|---|---|
| 项目许可证 | 公开仓库前 | 未定 |
| 产品覆盖年代 | M4 前 | 1900–2100（de440s 覆盖 1849–2150；ΔT 表 1800 起，1900 年前的结果未与星表核对） |
| 星历打包方式 | M3 → M7 | **已决定**：内置 de440s 裁剪到 1900–2100 年的版本（22 MB）；产品只开放这个范围，暂不提供完整版下载 |
| 预计算星表格式 | M2 | **已决定**：自定义定长二进制格式（D14） |
| 默认卫星列表 | M6 | 空间站、天宫，后续评估哈勃 |
| 是否上架 Google Play | M7 前 | 未定 |

## 9. 第一批任务

1. [x] 在本目录建立 Git 仓库，并接入 GitLab CI。
2. [x] 把 anise、sofars、sgp4 加入工作区，确认最新版本。
3. [x] 运行 `cargo tree -e normal --target aarch64-linux-android`，检查原生依赖。
4. [x] 分别编译到 Android、Windows 和 Linux。
5. [x] 下载 de440s，实现 `Ephemeris`，打印 J2000 时刻的地月距离作为第一个端到端测试。

下一步：Android 真机测试；下一版补 Windows、Linux 安装包（需先开启开发者模式和安装 Linux 工具链）；M6 与 transit-finder 对比、实测核对。M6 与 transit-finder 的逐条对比、实测核对待补做。M3 的 Windows（开启开发者模式）、Linux 桌面和 Android 真机验收待条件具备后补做。
