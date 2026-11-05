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
| 手机上的搜索速度 | 未验证。桌面实测见 M1 记录，按经验推算手机达不到 M1 的 100 万次/秒目标 |
| GitLab CI | gitlab.xao.ac.cn/xulingming/guanxiang，fmt、clippy、android-deps、test 全部通过。runner 无外网，de440s 由本项目 Generic Package Registry 提供 |
| Flutter 应用 | 未创建，在 M3 开始 |

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
  ├─ events（M2 起）           合冲、凌日、日月食、掩星
  └─ transit（M6）             SGP4、地面中心线、窄带判定

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
├─ app/              Flutter 应用（M3 创建）
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
- GitLab 共享 runner 42（Kubernetes）偶发在拉取代码时报 `could not lock config file //.gitconfig`，重试即可，与项目无关。
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

- [ ] 通用粗搜加精修流程（精修用的 Brent 求根、求极小值已在 `search` 中实现）
- [ ] 行星与日月的合、冲、最小角距
- [ ] 下合剪枝，以及水星、金星凌日
- [ ] 本地可见性过滤
- [ ] 预计算星表的存储方案（见第 8 节）
- [ ] CLI：`guanxiang search --kind conjunction --from 2000 --to 2100`

**验收：**

- 21 世纪水星凌日 14 次、金星凌日 2 次，一次不多，一次不少。
- 事件时刻与 Skyfield 的差 ≤ 5 秒。
- 真机上搜索 100 年一组天体对的时间 ≤ 1 秒（目标值）。

### M3 Flutter 竖切（2 周）

提前打通界面，尽早暴露三端打包问题。

- [ ] 在 `app/` 创建 Flutter 应用，接入 flutter_rust_bridge
- [ ] 把 `app/rust` 加入工作区，确认 Cargokit 在工作区内正常构建
- [ ] 打包星历，处理 Android 资源释放或 `load_from_bytes`（core 已提供 `AniseEphemeris::from_bytes`）
- [ ] 完成基础页面：搜索条件、结果列表、事件详情
- [ ] 搜索进度回传和取消
- [ ] 确认 Android 的 16 KB 页大小要求（M0 产物已是 16 KB 对齐，需在最终 APK 中复核）

**验收：** Windows、Linux 和 Android 真机都能完成一次凌日搜索，界面不卡顿。

### M4 日月食（3 周）

- [ ] 朔望剪枝和食的初筛
- [ ] 月食：半影、偏食、全食，地影放大模型可配置
- [ ] 日食：贝塞尔根数、类型判定、最大食时刻
- [ ] 本地环食、全食带和各接触时刻
- [ ] 全球事件预计算，生成 1900–2100 星表

**验收：**

- 21 世纪日食 224 次、月食 228 次，类型与 NASA 星表一致。半影月食边界如有差异，要逐条解释。
- 最大食时刻与 NASA 星表的差异可由 ΔT 和模型差异解释。

### M5 月掩星（1.5 周）

- [ ] 月掩行星（站心计算）
- [ ] 精简星表和自行修正
- [ ] 本地掩始、掩终时刻

**验收：** 随机抽取至少 20 个已知事件，时刻与权威预报或 Skyfield 的差 ≤ 5 秒。

### M6 卫星凌月（3 周）

- [ ] 用 `sgp4` 解析 OMM 并预报，确认输出坐标系
- [ ] TEME 到地固系转换，加入 UT1-UTC
- [ ] 预报 14 天内的过境，计算最小角距
- [ ] 计算地面中心线、带宽、持续时间和离带距离
- [ ] Dart 层拉取并缓存数据，遵守 CelesTrak 频率限制，非 200 响应时停止请求
- [ ] Android 用 WorkManager 后台刷新
- [ ] 显示根数龄期，并比较新旧预报，变化大时提醒
- [ ] 地图上显示中心线
- [ ] 复用同一套逻辑支持卫星凌日，并加入太阳观测安全提示

**验收：**

- 空间站和天宫至少 10 次预报与 transit-finder 对比，时刻差 ≤ 0.5 秒，中心线差 ≤ 500 米。
- 至少 1 次实际观测或公开影像核对。

### M7 发布（2 周）

- [ ] 性能优化，确定星历裁剪范围和安装包大小
- [ ] 中英文界面、错误提示、离线状态
- [ ] Windows 和 Linux 安装包，Android 发布版
- [ ] 第三方许可声明，包括 SOFA 致谢
- [ ] 确认 CelesTrak 数据使用方式，用户量较大时增加缓存服务

**验收：** 三个平台的安装包都在干净环境中完成安装和完整流程测试。

## 6. 验证方法

| 对象 | 对照来源 |
|---|---|
| 天体位置 | JPL Horizons、Skyfield |
| 视位置（IAU 2006/2000A） | Skyfield（同一份 de440s） |
| 坐标和时间尺度 | SOFA 官方测试值，`../SuperNOVAS` 可作为另一份参考 |
| 事件完整性 | NASA 日月食和凌日星表 |
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
| anise 查询速度不够 | M2 的搜索速度不达标 | 粗搜用几何位置；必要时自写 SPK Type 2 读取器 |
| 月面地形影响日食接触时刻 | 秒级误差 | 第一版不做地形修正，后续再评估 |
| 卫星变轨或根数过期 | 预报失效 | 显示龄期、临近再次刷新、比较新旧结果 |
| CelesTrak 限流或政策变化 | 卫星功能中断 | 严格缓存，只请求少量目标，必要时自建缓存 |
| 第三方许可 | 发布受限 | 发布前核对 SOFA、MPL-2.0 和数据来源条款 |

## 8. 待定事项

| 事项 | 需要决定的时间 | 当前倾向 |
|---|---|---|
| 项目许可证 | 公开仓库前 | 未定 |
| 产品覆盖年代 | M4 前 | 1900–2100（de440s 覆盖 1849–2150） |
| 星历打包方式 | M3 | 内置裁剪版，完整版按需下载 |
| 预计算星表格式 | M2 | SQLite，或者 Rust 直接读取的紧凑二进制文件 |
| 默认卫星列表 | M6 | 空间站、天宫，后续评估哈勃 |
| 是否上架 Google Play | M7 前 | 未定 |

## 9. 第一批任务

1. [x] 在本目录建立 Git 仓库，并接入 GitLab CI。
2. [x] 把 anise、sofars、sgp4 加入工作区，确认最新版本。
3. [x] 运行 `cargo tree -e normal --target aarch64-linux-android`，检查原生依赖。
4. [x] 分别编译到 Android、Windows 和 Linux。
5. [x] 下载 de440s，实现 `Ephemeris`，打印 J2000 时刻的地月距离作为第一个端到端测试。

下一步：M2 合冲与凌日。先做粗搜加精修的通用流程，并测一次 100 年搜索的耗时，再决定是否自写 SPK 读取器。
