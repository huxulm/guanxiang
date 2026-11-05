# 观象（Guanxiang）开发计划

跨平台（Windows、Linux、Android）天文事件搜索工具。核心用 Rust 编写，界面用 Flutter。

最后更新：2026-11-05

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

- [ ] 性能优化，确定星历裁剪范围和安装包大小
- [ ] 中英文界面、错误提示、离线状态
- [ ] Windows 和 Linux 安装包，Android 发布版
- [ ] 第三方许可声明，包括 SOFA 致谢
- [ ] 确认 CelesTrak 数据使用方式，用户量较大时增加缓存服务
- [ ] 确认 OpenStreetMap 瓦片使用政策（应用内使用需标注来源、设置 User-Agent，用量大时换自建或商业瓦片）

**验收：** 三个平台的安装包都在干净环境中完成安装和完整流程测试。

## 6. 验证方法

| 对象 | 对照来源 |
|---|---|
| 天体位置 | JPL Horizons、Skyfield |
| 视位置（IAU 2006/2000A） | Skyfield（同一份 de440s） |
| 坐标和时间尺度 | SOFA 官方测试值，`../SuperNOVAS` 可作为另一份参考 |
| 事件完整性 | NASA 日月食和凌日星表 |
| 月掩星 | Skyfield（同一星表参数，独立求解） |
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
| 星历打包方式 | M3 → M7 | M3 暂时内置完整 de440s（32 MB）；M7 改为内置裁剪版，完整版按需下载 |
| 预计算星表格式 | M2 | **已决定**：自定义定长二进制格式（D14） |
| 默认卫星列表 | M6 | 空间站、天宫，后续评估哈勃 |
| 是否上架 Google Play | M7 前 | 未定 |

## 9. 第一批任务

1. [x] 在本目录建立 Git 仓库，并接入 GitLab CI。
2. [x] 把 anise、sofars、sgp4 加入工作区，确认最新版本。
3. [x] 运行 `cargo tree -e normal --target aarch64-linux-android`，检查原生依赖。
4. [x] 分别编译到 Android、Windows 和 Linux。
5. [x] 下载 de440s，实现 `Ephemeris`，打印 J2000 时刻的地月距离作为第一个端到端测试。

下一步：M7 发布准备（性能、星历裁剪、中英文界面、离线状态、安装包、许可声明）。M6 与 transit-finder 的逐条对比、实测核对待补做。M3 的 Windows（开启开发者模式）、Linux 桌面和 Android 真机验收待条件具备后补做。
