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

```sh
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64
```

- 签名配置在 `android/key.properties`（不进 Git），指向仓库外的上传密钥 `~/.android/guanxiang-upload.jks`（别名 `upload`，RSA 4096，有效期 10000 天）。**密钥文件和 key.properties 里的密码务必另行备份**，丢失后无法再发布同一应用的更新。
- 没有 key.properties 时 release 包退回调试签名，只能自己测试。
- 版本号在 `pubspec.yaml` 的 `version`；分 ABI 打包时 versionCode 自动加 1000 × ABI 序号。
- 校验：`apksigner verify --print-certs <apk>`、`zipalign -c -P 16 4 <apk>`（16 KB 页对齐）。

## 卫星

- 根数从 CelesTrak 下载（`lib/src/celestrak.dart`），缓存在应用支持目录的 `omm/` 下。同一颗卫星 2 小时内只请求一次；任何非 200 响应后本次运行不再请求，并暂停 2 小时。
- 搜索起始时间默认是现在，可以在卫星页选择其他日期时间（本地时间，传给 Rust 前转成 UTC）。离根数历元越远越不准，龄期超过 3 天的结果会提醒。
- Android 上用 WorkManager 每 6 小时在后台刷新一次（仅联网时），同样遵守上面的限制。
- 地图底图是 OpenStreetMap 瓦片，需要联网；离线时底图空白，数据照常显示。
