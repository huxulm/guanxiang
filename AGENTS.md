# AGENTS.md

观象（Guanxiang）：跨平台天文事件搜索。Rust 计算核心 + Flutter 界面（Android、Windows、Linux），另有一个静态官网。计划与进度见 `docs/PLAN.md`，各子目录的细节见对应的 README。

本项目以 MIT 或 Apache-2.0 双许可开源（`LICENSE-MIT`、`LICENSE-APACHE`），版权人 Huxulm；新增的 crate 用 `license.workspace = true`。

## 目录

| 路径 | 内容 |
|---|---|
| `crates/guanxiang-core/` | 计算核心：时间尺度、ΔT、星历（anise）、视位置（sofars）、事件搜索（`src/events/`）、卫星（sgp4） |
| `crates/guanxiang-view/` | 展示数据（CLI 和 wasm 共用）：日月食列表、动画场景 JSON（`scene`，`tools/manim` 读取）、逐帧状态 |
| `crates/guanxiang-cli/` | 命令行：`info`、`distance`、`position`、`search`、`eclipse`、`occultation`、`satellite`、`scene` |
| `crates/guanxiang-wasm/` | WebAssembly 接口（Web 应用，规划见 `docs/PLAN.md`“Web 应用”）：`wasm-pack build crates/guanxiang-wasm --release --target web` |
| `app/` | Flutter 应用；`app/rust/` 是 flutter_rust_bridge 2.13 桥接层（工作区成员），`app/lib/src/rust/` 是生成的绑定 |
| `webapp/` | Web 应用（Vite + Svelte 5 + TypeScript + Tailwind 4），浏览器里用 wasm 计算日月食，见 `webapp/README.md`；线上 https://app.guanx.huxulm.dev （手动 `npx wrangler deploy`，星历在 R2，见该 README） |
| `website/` | 官网（Vite + TypeScript + Tailwind 4），Cloudflare Workers 静态资源托管，https://guanx.huxulm.dev |
| `tools/` | 脚本：Release 说明（`release_notes.py`）、Linux 打包和冒烟测试，以及生成对照数据（Skyfield、Horizons、NASA 星表）、沙罗序列表、ΔT 表、恒星表、地图陆地轮廓、许可证清单、应用图标 |
| `data/` | 星历（不进 Git），获取方法见 `data/README.md` |

## 常用命令

```sh
# Rust（CI 跑的就是这几条，提交前都要过）
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked        # 需要 data/de440s.bsp，否则星历测试会跳过

# Flutter（在 app/ 下）
flutter analyze
flutter test                            # 主机单元测试
flutter test integration_test/app_test.dart -d <设备>  # 设备上的集成测试（只跑这个文件：整个目录会把截图脚本也启动一遍）
flutter_rust_bridge_codegen generate    # 改了 app/rust/src/api/ 之后

# 官网（在 website/ 下）
npm ci && npm run build                 # tsc 类型检查 + vite 构建
```

## 调试与验证

### 改了什么，就验证什么

| 改动 | 至少要做 |
|---|---|
| 计算逻辑（`crates/guanxiang-core`） | `cargo test`；用 `tools/` 下的独立来源重新对照，差别写进 `docs/PLAN.md`；可用 CLI 快速核对单个事件（见下） |
| 桥接（`app/rust/src/api/`） | `flutter_rust_bridge_codegen generate`，生成的文件一起提交；`cargo clippy`、`flutter analyze` |
| 界面（`app/lib/`） | `flutter analyze`、`flutter test`；**截图**看三套主题（浅色、深空、红光）和窄屏、宽屏；新文案中英文都要有 |
| 平台相关（权限、通知、定位、高德地图、后台任务） | 在 Android 模拟器上跑 `flutter test integration_test/app_test.dart`，看 logcat |
| 构建、依赖、打包（Gradle、installer.iss、`tools/package_*`） | 手动运行 release.yml 并勾选试运行（见“发版”第 2 步） |
| Web 应用（`webapp/`、`crates/guanxiang-view`、`crates/guanxiang-wasm`） | `npm run wasm && npm run build`（含 svelte-check 和红光主题检查）；改了动画几何（`src/lib/anim/bessel.ts`）跑 `npm run test:geometry`；`npm run dev` 后用浏览器截三套主题、390 和 1280 宽度、中英文，控制台没有报错 |
| 官网（`website/`） | `npm run build`；本地预览后用浏览器截窄屏和宽屏 |

推送后用 `gh run list -R huxulm/guanxiang -L 3`、`gh run watch <id> -R huxulm/guanxiang --exit-status` 确认 GitHub CI 通过（含 Linux）；官网改动再用 `curl -s https://guanx.huxulm.dev/ | grep …` 确认线上已更新。

### 选哪台设备

- **Windows 桌面（`-d windows`）**：最快，纯界面和布局问题首选，截图脚本也在这上面跑。拖动窗口宽度可以看窄屏和宽屏两种布局（分界 600）。
- **Android 模拟器 `guanxiang_api35_16k_hi`**（Android 15、16 KB 页，配置见 `app/README.md`）：权限、通知、高德地图、16 KB 对齐、性能。
- **Linux**：本机不编译，只看 GitHub Actions 的 `linux`、`linux-smoke` 任务。

### 截图

`app/integration_test/screenshots_test.dart` 把首页、月食详情（2025-09-07，北京）、日食详情（2027-08-02，卢克索）、分享页按三套主题 × 窄屏（412×915）、宽屏（1280×860）截下来，长页面一屏一张往下滚。没给 `SHOT_DIR` 时整个文件跳过，所以 CI 不受影响。

```sh
cd app
rm -rf build/screenshots            # 每次先清空，免得混进上次的图
flutter test integration_test/screenshots_test.dart -d windows \
  --dart-define=SHOT_DIR="$(cygpath -w "$PWD/build/screenshots")"   # Git Bash；PowerShell 写 "$PWD\build\screenshots"
#   --dart-define=SHOT_FILTER=solar-red    只截名字里含这个字符串的图
#   --dart-define=SHOT_LOCALE=en           英文界面
```

输出 `app/build/screenshots/<页面>-<主题>-<尺寸>-<序号>.png`（不进 Git），全部约 60 张、2 分钟。要截新页面，在文件里的 `_pages` 加一项。智能体可以直接读这些 PNG 检查效果。

Android 上截真实画面：`adb -s emulator-5554 exec-out screencap -p > shot.png`。

### 运行与日志

```sh
# Windows 桌面上跑应用（热重载：终端里按 r）
cd app && flutter run -d windows

# Android 模拟器
emulator -avd guanxiang_api35_16k_hi -no-snapshot-load -no-boot-anim &
flutter run -d emulator-5554             # debug 包要用 flutter run 启动，直接点开会停在启动画面
adb -s emulator-5554 logcat -d -v brief | grep -iE "flutter|guanxiang|AndroidRuntime"

# 集成测试（Android 上前要去掉 HTTP_PROXY/HTTPS_PROXY）
flutter test integration_test/app_test.dart -d windows
flutter test integration_test/app_test.dart -d emulator-5554 --plain-name "月食"   # 只跑名字匹配的
```

### 不开界面核对计算

CLI 和 App 用同一个核心，查单个事件比开界面快（在仓库根目录，需要 `data/de440s.bsp`）：

```sh
cargo run -q -p guanxiang-cli -- eclipse --from 2027 --to 2028 --kind solar --details
cargo run -q -p guanxiang-cli -- eclipse --from 2025-09-01 --to 2025-09-30 --kind lunar --at 39.9,116.4
cargo run -q -p guanxiang-cli -- search --help        # 合、冲、凌日；其余子命令见 --help
```

### 官网

```sh
cd website && npm run dev                # http://localhost:5173 ，改动即时刷新
```

用 Playwright（或 Chrome DevTools）打开本地地址，分别在 390 和 1280 宽度下截图，并检查控制台没有报错；页面右上角可切换中英文。

## 约定

- **语言**：注释、文档、提交信息、界面文案都用中文。界面文字一律走 ARB（`app/lib/l10n/app_zh.arb` 是模板，`app_en.arb` 是英文），两个文件的键必须一致（有测试检查），改完运行 `flutter gen-l10n`，生成的文件要提交。Rust 输出的文字按 `Lang { Zh, En }` 区分。
- **界面配色与布局**：不要写死颜色。通用颜色用 `Theme.of(context).colorScheme`，各类天象的强调色用 `AstroAccents.of(context)`（`app/lib/src/theme.dart`，三套主题共用一个构建函数，各自只给一组色值）。红光模式里所有颜色都必须以红色分量为主（有测试检查），实心按钮用暗红底。页面主体用 `ContentListView`（`app/lib/src/layout.dart`），宽屏时内容最宽 960、居中。
- **Rust**：edition 2024，工作区禁止 `unsafe`，clippy 警告视为错误。`guanxiang-core` 必须保持纯 Rust：不能引入 TLS、OpenSSL、`cc`、`cmake`、`bindgen`（CI 的 `android-deps` 任务会检查）。依赖统一写在根 `Cargo.toml` 的 `[workspace.dependencies]`。
- **精度**：改动计算逻辑时，要用 `tools/` 下的独立来源（Skyfield、JPL Horizons、NASA 星表）重新对照，并在 `docs/PLAN.md` 写明差别。现有基准：视位置 ≤ 0.0004″，合冲 ≤ 0.002 s，日月食 ≤ 2.3 s，月掩星 ≤ 0.003 s，卫星 ≤ 0.007 s，日月出没与晨昏 ≤ 0.03 s，月下点 ≤ 0.01″，月食持续时间与 NASA 差 ≤ 0.5 min，日月食沙罗序列号全部一致，日食食分栅格与本地计算差 ≤ 0.002。
- **星历**：App 打包的是 `de440s` 裁剪到 1899-12 至 2101-02 的版本，必须能复现（SHA-256 `1b7ff150…74afaa`，CI 会重新生成并校验）。测试里的 `GUANXIANG_EPHEM` 要用绝对路径。
- **提交**：中文摘要一行，空行后用列表写要点。小步提交，每次提交都要保证 CI 能过。

## 容易踩的坑

- `app/windows/runner/` 下的 `.cpp`、`.h`、`.rc` 只能写 ASCII：MSVC 按系统代码页（GBK）读没有 BOM 的文件，中文会导致编译失败或乱码。窗口标题用 `\u` 转义写在 `main.cpp`。`app/windows/installer.iss` 含中文，要保存成带 BOM 的 UTF-8。
- 改 `Runner.rc` 的 CompanyName/ProductName 会改变 Windows 上的数据目录（`%APPDATA%\cn.ac.xao\guanxiang`）。
- Windows 上构建 Flutter 需要打开开发者模式（插件用符号链接）。pub 缓存和工程不在同一个盘符时，Kotlin 增量编译会出错，所以 `android/gradle.properties` 里把它关掉了。
- 本机有 HTTP 代理：Gradle 要通过 `JAVA_TOOL_OPTIONS` 设代理；跑设备测试前要去掉 `HTTP_PROXY`/`HTTPS_PROXY`。
- GitLab CI 的 YAML 里，含“冒号加空格”的命令要整行加引号，否则会被解析成映射。
- 搜索结果在窄屏（宽度 < 600）上单独一页显示，宽屏时在同一页；改布局时两种都要看。

## 外部服务的规矩（不要随意改）

- **CelesTrak**（`app/lib/src/celestrak.dart`）：同一颗卫星 2 小时内只请求一次；收到任何非 200 响应就停止请求并暂停 2 小时；使用本应用自己的 User-Agent。
- **OpenStreetMap 瓦片**（`app/lib/src/sat_transit_page.dart`）：使用自己的 User-Agent，缓存至少 7 天，显示署名，不做批量或离线下载。瓦片地址只写在 `tileUrlTemplate` 这一处。
- **许可证**：Rust 依赖的许可证由 `tools/licenses/gen_rust_notices.py` 生成到 `app/assets/licenses/rust.txt`。增删依赖后要重新生成；数据来源的致谢写在 `app/lib/src/licenses.dart`。

## 发版

1. 改版本号：`app/pubspec.yaml` 的 `version`、`app/lib/src/licenses.dart` 的 `appVersion`、`website/src/main.ts` 的 `VERSION`（这三处要一致）。
2. 安装包全部由 GitHub Actions 的 `release.yml` 构建，不在本机构建。改了构建相关的东西（依赖、Gradle、installer.iss 等）时，可以先手动运行 release.yml 并勾选“试运行”（`gh workflow run release.yml -R huxulm/guanxiang -f tag=<已有标签> -f dry_run=true`），只构建、不碰 Release。
3. 写 Release 说明：`python tools/release_notes.py new <版本>` 从 `docs/releases/TEMPLATE.md` 生成 `docs/releases/v<版本>.md`（“已知限制”预填上一版），填好“更新”、核对“已知限制”后运行 `python tools/release_notes.py check <版本>`。说明和版本号一起提交，每个版本的说明都留在仓库里。
4. 提交版本号和说明，推到两边的 main：`git push origin main`、`git push github main`（GitHub 镜像 `huxulm/guanxiang`，远程名 `github`，只推 main，不推本地标签）。
5. 在 GitHub 上建 Release（不带附件）：`gh release create v<版本> -R huxulm/guanxiang --target <版本提交> --title "观象 <版本>（Android · Windows · Linux）" --notes-file docs/releases/v<版本>.md`（标签由 gh 在 GitHub 上创建）。Release 发布后，Actions 的 `release.yml`：
   - 把标签提交里的 `docs/releases/v<版本>.md` 写回 Release 正文（以仓库为准，以后改说明就改这个文件再重跑 release.yml）；
   - 从 de440s 生成并校验裁剪星历，然后并行构建：Android（ubuntu-latest，NDK 30，用 Secrets 里的发布密钥签名，并核对证书 SHA-256）、Windows（windows-latest，Inno Setup 7.1.1 安装程序和 `tools/package_windows.py` 打的 zip）、Linux（ubuntu-22.04，`tools/package_linux.sh`，冒烟测试 `tools/smoke_linux.sh`），各自上传到 Release；
   - 把 5 个包同步到 R2（`https://s2.huxulm.dev/guanxiang/<版本>/`）、生成 SHA256SUMS、校验公开地址，然后调用 `website.yml` 部署官网。
   全程约 20 分钟，这期间 Release 页面上的附件是陆续出现的。
6. 官网平时的改动推到 GitHub main 后由 `website.yml` 自动部署；如果 R2 上还没有官网 `VERSION` 对应的包，会跳过部署，避免出现失效的下载链接。
7. GitLab 上可以照旧推 `v*` 标签、建 GitLab Release（可选，GitLab CI 现在只做检查）。
8. GitHub 的 `ci.yml` 跑的检查与 GitLab CI 相同，另加 `flutter analyze`/`flutter test`。
9. Linux 版只在 GitHub Actions 上构建和测试（`ci.yml` 的 `linux`、`linux-smoke`），不在本机 WSL 里编译测试。必须在 ubuntu-22.04 上构建：在更新的系统上构建的程序会依赖新版 GLib，在 22.04 上无法启动。

## 安全

- 不要提交密钥：`app/android/key.properties`、签名密钥（`~/.android/guanxiang-upload.jks`）、各种 token 都不进 Git，也不要打印到日志里。
- 调用 GitLab API 时，`GITLAB_TOKEN` 只放在单次请求的请求头里，不要写进 `.git/config`。`CLOUDFLARE_API_TOKEN`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` 存在 GitHub 仓库的 Actions Secrets 里（GitLab 上也还留有同名的受保护变量，现在不再使用）。Android 发布签名也存在 Actions Secrets 里：`ANDROID_KEYSTORE_BASE64`（jks 的 base64）、`ANDROID_STORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；release.yml 只把它们写到本次运行的临时目录，用完删除。换密钥时要同时更新这四项。
- 涉及观测太阳的界面和文档，都要保留安全提示（ISO 12312-2 滤光膜）。
