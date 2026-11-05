# 观象 Flutter 应用

界面在 `lib/`，Rust 桥接层在 `rust/`（属于仓库根目录的 Cargo 工作区），由 flutter_rust_bridge 2.13 生成绑定，Cargokit（`rust_builder/`）在 Flutter 构建时编译 Rust。

## 准备

```sh
# 星历随应用打包，但不进 Git
cp ../data/de440s.bsp assets/

# 修改 rust/src/api/ 后重新生成绑定
flutter_rust_bridge_codegen generate
```

- Windows 上构建需要打开“开发者模式”（插件需要符号链接）：`start ms-settings:developers`。
- Android 需要 NDK 30.0.16248370（`android/app/build.gradle.kts` 中固定），以及 Rust 目标 `x86_64-linux-android`（模拟器）、`aarch64-linux-android`（真机）。
- 本机有 HTTP 代理时：Gradle 需要 `JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=… -Dhttps.proxyPort=…"`；运行 `flutter test integration_test` 前要去掉 `HTTP_PROXY`/`HTTPS_PROXY`，否则连不上设备上的 VM service。

## 运行

```sh
flutter run -d <设备>
flutter test integration_test -d <设备>   # 设备上的集成测试：加载星历、金星凌日、月木合耗时、取消
```

debug 包请用 `flutter run` 启动；直接在设备上点开 debug 包会停在启动画面。
