# AGENTS.md

观象（Guanxiang）：跨平台天文事件搜索。Rust 计算核心 + Flutter 界面（Android、Windows、Linux），另有一个静态官网。计划与进度见 `docs/PLAN.md`，各子目录的细节见对应的 README。

## 目录

| 路径 | 内容 |
|---|---|
| `crates/guanxiang-core/` | 计算核心：时间尺度、ΔT、星历（anise）、视位置（sofars）、事件搜索（`src/events/`）、卫星（sgp4） |
| `crates/guanxiang-cli/` | 命令行：`info`、`distance`、`position`、`search`、`eclipse`、`occultation`、`satellite` |
| `app/` | Flutter 应用；`app/rust/` 是 flutter_rust_bridge 2.13 桥接层（工作区成员），`app/lib/src/rust/` 是生成的绑定 |
| `website/` | 官网（Vite + TypeScript + Tailwind 4），Cloudflare Workers 静态资源托管，https://guanx.huxulm.dev |
| `tools/` | Python 脚本：生成对照数据（Skyfield、Horizons、NASA 星表）、ΔT 表、恒星表、许可证清单、应用图标 |
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
flutter test integration_test -d <设备>  # 设备上的集成测试
flutter_rust_bridge_codegen generate    # 改了 app/rust/src/api/ 之后

# 官网（在 website/ 下）
npm ci && npm run build                 # tsc 类型检查 + vite 构建
```

## 约定

- **语言**：注释、文档、提交信息、界面文案都用中文。界面文字一律走 ARB（`app/lib/l10n/app_zh.arb` 是模板，`app_en.arb` 是英文），两个文件的键必须一致（有测试检查），改完运行 `flutter gen-l10n`，生成的文件要提交。Rust 输出的文字按 `Lang { Zh, En }` 区分。
- **界面配色与布局**：不要写死颜色。通用颜色用 `Theme.of(context).colorScheme`，各类天象的强调色用 `AstroAccents.of(context)`（`app/lib/src/theme.dart`，三套主题共用一个构建函数，各自只给一组色值）。红光模式里所有颜色都必须以红色分量为主（有测试检查），实心按钮用暗红底。页面主体用 `ContentListView`（`app/lib/src/layout.dart`），宽屏时内容最宽 960、居中。
- **Rust**：edition 2024，工作区禁止 `unsafe`，clippy 警告视为错误。`guanxiang-core` 必须保持纯 Rust：不能引入 TLS、OpenSSL、`cc`、`cmake`、`bindgen`（CI 的 `android-deps` 任务会检查）。依赖统一写在根 `Cargo.toml` 的 `[workspace.dependencies]`。
- **精度**：改动计算逻辑时，要用 `tools/` 下的独立来源（Skyfield、JPL Horizons、NASA 星表）重新对照，并在 `docs/PLAN.md` 写明差别。现有基准：视位置 ≤ 0.0004″，合冲 ≤ 0.002 s，日月食 ≤ 2.3 s，月掩星 ≤ 0.003 s，卫星 ≤ 0.007 s，日月出没与晨昏 ≤ 0.03 s。
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
2. 构建：`flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64`；`flutter build windows --release` 后运行 `ISCC.exe windows\installer.iss`，再把 Release 目录打成 zip。
3. 提交版本号，推到两边的 main：`git push origin main`、`git push github main`（GitHub 镜像 `huxulm/guanxiang`，远程名 `github`，只推 main，不推本地标签）。
4. 在 GitHub 上建 Release 并上传本机构建的 4 个包（Linux 包由 Actions 构建）：`gh release create v<版本> -R huxulm/guanxiang --target <版本提交> --notes-file <说明> <4 个包>`（标签由 gh 在 GitHub 上创建）。Release 发布后，Actions 的 `release.yml` 先在 ubuntu-22.04 上构建 Linux 包（`tools/package_linux.sh`，冒烟测试 `tools/smoke_linux.sh`）补传到 Release，再把 5 个包同步到 R2（`https://s2.huxulm.dev/guanxiang/<版本>/`）、生成 SHA256SUMS、校验公开地址，然后调用 `website.yml` 部署官网。
5. 官网平时的改动推到 GitHub main 后由 `website.yml` 自动部署；如果 R2 上还没有官网 `VERSION` 对应的包，会跳过部署，避免出现失效的下载链接。
6. GitLab 上可以照旧推 `v*` 标签、建 GitLab Release（可选，GitLab CI 现在只做检查）。
7. GitHub 的 `ci.yml` 跑的检查与 GitLab CI 相同，另加 `flutter analyze`/`flutter test`。
8. Linux 版只在 GitHub Actions 上构建和测试（`ci.yml` 的 `linux`、`linux-smoke`），不在本机 WSL 里编译测试。必须在 ubuntu-22.04 上构建：在更新的系统上构建的程序会依赖新版 GLib，在 22.04 上无法启动。

## 安全

- 不要提交密钥：`app/android/key.properties`、签名密钥（`~/.android/guanxiang-upload.jks`）、各种 token 都不进 Git，也不要打印到日志里。
- 调用 GitLab API 时，`GITLAB_TOKEN` 只放在单次请求的请求头里，不要写进 `.git/config`。`CLOUDFLARE_API_TOKEN`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY` 存在 GitHub 仓库的 Actions Secrets 里（GitLab 上也还留有同名的受保护变量，现在不再使用）。
- 涉及观测太阳的界面和文档，都要保留安全提示（ISO 12312-2 滤光膜）。
