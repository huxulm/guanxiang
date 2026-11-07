# 观象 Flutter 应用

界面在 `lib/`，Rust 桥接层在 `rust/`（属于仓库根目录的 Cargo 工作区），由 flutter_rust_bridge 2.13 生成绑定，Cargokit（`rust_builder/`）在 Flutter 构建时编译 Rust。

## 准备

```sh
# 星历随应用打包，但不进 Git：de440s 裁剪到 1900–2100 年（22 MB），
# 范围内的位置与原文件逐位一致，SHA-256 应为 1b7ff150cbc00d364f584ad65dad651129fde4ab2e7aa23f9551dc9b9674afaa
cargo run --release -p guanxiang-core --example trim_spk -- ../data/de440s.bsp assets/de440s_1900_2100.bsp 1899-12-01 2101-02-01

# 修改 rust/src/api/ 后重新生成绑定
flutter_rust_bridge_codegen generate
```

- Windows 上构建需要打开“开发者模式”（插件需要符号链接）：`start ms-settings:developers`。
- Android 需要 NDK 30.0.16248370（`android/app/build.gradle.kts` 中固定），以及 Rust 目标 `x86_64-linux-android`（模拟器）、`aarch64-linux-android`（真机）。部分插件模块还会让 Gradle 自动安装 NDK 28.2 和 CMake 3.22.1。
- `android/gradle.properties` 关闭了 Kotlin 增量编译：pub 缓存和工程不在同一盘符时，增量编译会报 “this and base files have different roots”。
- 本机有 HTTP 代理时：Gradle 需要 `JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=… -Dhttps.proxyPort=…"`；运行 `flutter test integration_test` 前要去掉 `HTTP_PROXY`/`HTTPS_PROXY`，否则连不上设备上的 VM service。

## 运行

```sh
flutter run -d <设备>
flutter test integration_test -d <设备>   # 设备上的集成测试：凌日、合冲耗时、日月食、月掩星、卫星、取消
flutter test                              # 主机上的单元测试（CelesTrak 缓存与频率限制，用模拟的 HTTP）
```

本机模拟器 `guanxiang_api35_16k_hi`：Android 15、16 KB 页、6 GB 内存、6 核、主机 GPU。原来 2 GB 内存的模拟器上，测试工具连接 VM service 时 adb 会掉线（“device offline”），换成这台后正常。

debug 包请用 `flutter run` 启动；直接在设备上点开 debug 包会停在启动画面。

## Android 发布

发布用的 APK 由 GitHub Actions 的 `release.yml` 构建和签名（见 `AGENTS.md` 的“发版”）。本机构建：

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
```

- 本机的签名配置在 `android/key.properties`（不进 Git），指向仓库外的上传密钥 `~/.android/guanxiang-upload.jks`（别名 `upload`，RSA 4096，有效期 10000 天）。CI 用的是同一把密钥，存在 GitHub 仓库的 Actions Secrets 里（`ANDROID_KEYSTORE_BASE64` 等四项）。**密钥文件和 key.properties 里的密码务必另行备份**，丢失后无法再发布同一应用的更新。
- 没有 key.properties 时 release 包退回调试签名，只能自己测试；CI 缺少签名 Secrets 时直接失败，不会发出调试签名的包。
- 包名（applicationId）是 `dev.huxulm.guanxiang`（0.1.4 及以前是 `cn.ac.xao.guanxiang`，两者在系统里是不同的应用，不能互相覆盖升级）。高德等地图 SDK 的 Key 按包名和签名证书 SHA1 绑定，发布证书 SHA1 为 `29:D5:27:97:04:24:E8:FC:FF:9D:E5:ED:E2:0F:E0:EE:F6:A4:09:F3`。
- 版本号在 `pubspec.yaml` 的 `version`；分 ABI 打包时 versionCode 自动加 1000 × ABI 序号。
- 校验：`apksigner verify --print-certs <apk>`、`zipalign -c -P 16 4 <apk>`（16 KB 页对齐）。

## Windows 发布

发布用的安装包由 GitHub Actions 的 `release.yml` 在 windows-latest 上构建（Inno Setup 7.1.1）。本机构建：

```sh
flutter build windows --release
"C:\Program Files\Inno Setup 7\ISCC.exe" windows\installer.iss
# 安装程序：build\windows\installer\guanxiang-<版本>-windows-x64-setup.exe
# 免安装包（在仓库根目录）：python tools/package_windows.py app/build/windows/x64/runner/Release guanxiang-<版本>-windows-x64.zip
```

- 本机需要 Visual Studio 的“使用 C++ 的桌面开发”和 Inno Setup 7。
- 安装程序默认装到当前用户目录（`%LOCALAPPDATA%\Programs\Guanxiang`），不需要管理员权限，向导里可改为所有用户。版本号取自 exe 的 ProductVersion（即 `pubspec.yaml`），`installer.iss` 里不用改；`AppId` 固定，升级时覆盖安装。
- 卸载时询问是否删除用户数据（`%APPDATA%\cn.ac.xao\guanxiang` 等，路径由 Runner.rc 的 CompanyName/ProductName 决定，改这两项会换数据目录）。
- `windows/runner/*.cpp`、`*.rc` 只能用 ASCII：MSVC 按系统代码页读没有 BOM 的源文件，中文会让编译失败或变成乱码。窗口标题“观象”用 `\u` 转义写在 `main.cpp`。
- 程序未签名，SmartScreen 会提示“未知发布者”。
- 应用图标由 `tools/icons/gen_icons.py` 按官网的 `website/public/favicon.svg` 生成（Windows `.ico` 和 Android 自适应图标）。

## 卫星

- 根数从 CelesTrak 下载（`lib/src/celestrak.dart`），缓存在应用支持目录的 `omm/` 下。同一颗卫星 2 小时内只请求一次；任何非 200 响应后本次运行不再请求，并暂停 2 小时。
- 搜索起始时间默认是现在，可以在卫星页选择其他日期时间（本地时间，传给 Rust 前转成 UTC）。离根数历元越远越不准，龄期超过 3 天的结果会提醒。
- Android 上用 WorkManager 每 6 小时在后台刷新一次（仅联网时），同样遵守上面的限制。
- 地图：arm64 Android 上，用户在首次打开地图时同意隐私说明后用高德地图（`lib/src/amap_view.dart`），否则用 OpenStreetMap 瓦片；两者都需要联网，离线时底图空白，数据照常显示。

## 后台任务（卫星凌日）

- 两种任务（`lib/src/tasks.dart`）：**长跨度搜索**用当前根数一次搜完最多 120 天，按 7 天一段计算，可中断续算，有最长计算时间；**持续监视**到截止时间为止每 4 小时刷新根数、重搜接下来 14 天。两种都可设范围半径（中心线在半径内经过也算命中）和“找到就停”。
- 单次搜索仍限 14 天，因为根数只在两周内可靠；长跨度搜索两周以后的结果在报告里标“仅供参考”。
- 任务保存在应用支持目录的 `tasks.json`。后台 isolate 和界面会同时读写，`TaskStore.update` 每次重读文件、只改一个任务再原子写回；已取消的任务不会被后台覆盖。
- Android：提交时安排 WorkManager 一次性任务 `guanxiang.runTasks`（一次最多 8 分钟，没算完再排一次）；周期任务（每 6 小时）刷新根数后也跑一遍到期任务。后台 isolate 里重新 `RustLib.init()` 并加载星历。
- 其他平台：`ForegroundTaskScheduler` 在应用打开期间每 10 分钟检查一次。
- 通知用 `flutter_local_notifications`（Android 需要核心库脱糖，通知小图标是 `res/drawable/ic_stat_notify.xml`）。持续监视逐个通知新命中；长跨度搜索只在结束时发一条汇总。

## 高德地图

- 插件是社区维护的 `amap_map`（官方 `amap_flutter_map` 不支持 Dart 3）。Key 在 `lib/src/amap_support.dart`，按包名和签名证书 SHA1 绑定。
- `android/build.gradle.kts` 做了两件事：把插件的 compileSdk 提到 36（`flutter_plugin_android_lifecycle` 要求）；把高德 SDK 强制换成 `3dmap-location-search:11.3.100_loc11.3.101_sea9.8.1`，因为插件自带的 10.1.200 原生库只按 4 KB 对齐，在 16 KB 页设备上加载不了。升级插件时检查这两处是否还需要。
- 高德原生库只有 arm64-v8a，没有 x86_64：模拟器、桌面一律用 OSM（`amapSupported`），所以高德地图只能在真机上验证。arm64 APK 因此大了约 40 MB。
- 隐私合规：同意前不初始化高德 SDK（`AMapPrivacyStatement` 三项都要为 true 才能显示地图）；选择保存在设置里，设置页可以关闭。应用隐私政策在官网 `website/privacy.html`。
- 高德底图是 GCJ-02 坐标，中心线、测站在国内先用 `lib/src/gcj02.dart` 从 WGS-84 转换再画；境外不变换。
- release 包开了 R8，高德的保留规则在 `android/app/proguard-rules.pro`。
