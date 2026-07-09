# 交付总览：ALVR 奇遇 Dream 客户端（路径 B 实现）

## 目标
把最新 **ALVR v20.14.1** 的串流核心，改写成可直接在**爱奇艺奇遇 Dream** 头显运行的客户端，
保留 hallychou 旧 fork 的核心桥接思路（奇遇原生 SDK → ALVR 串流核心），并适配新 C ABI、提升可维护性。

## 做了什么
1. **重写 `app/src/main/cpp/cpp_main.cpp`** —— 对齐 ALVR v20.14.1 的 C ABI：
   - 用 `alvr_initialize_android_context()` + `alvr_initialize(AlvrClientCapabilities)` 初始化；
   - 用 `qiyu_PredictDisplayTime()` 替代已移除的 `alvr_get_prediction_offset_ns()`；
   - `alvr_send_view_params()` / `alvr_report_compositor_start()` / `alvr_start_stream_opengl()` /
     `alvr_render_stream_opengl()` / `alvr_render_lobby_opengl()` / `alvr_get_frame()` 等全部按新签名调用；
   - 解码器在 `DecoderConfig` 事件时经 `alvr_create_decoder()` 创建；
   - 上报交互 Profile（`oculus/touch_controller` 布局）。
2. **修正 cbindgen 命名**（v20.14.1 用 `QualifiedScreamingSnakeCase`）：
   事件/枚举标签改为全大写带前缀（`ALVR_EVENT_STREAMING_STARTED`、`ALVR_BUTTON_VALUE_BINARY`、
   `ALVR_LOG_LEVEL_ERROR`…），union body 字段为不带前缀的 SCREAMING_SNAKE（`HAPTICS`、`BINARY`…）；
   修正 `AlvrLobbyViewParams` 展平结构、补齐 `config_buffer_size` 与 `AlvrClientCapabilities` 字段、
   移除不存在的 `max_view_*` 字段。
3. **工程化改造**：补 `settings.gradle` / 根 `build.gradle` / `gradle.properties` / wrapper 配置；
   移除 Oculus 依赖与清单项，改声明奇遇（Wave 系）VR 模式；单 flavor 出单个 APK。
4. **一键构建**：`build.sh` + `.github/workflows/build.yml` —— 自动克隆 ALVR v20.14.1、
   用 `cargo ndk` 编 `alvr_client_core`(aarch64)、cbindgen 生成头、复制产物、`gradle assembleRelease` 出 APK。
5. **傻瓜化 README**（中文）：GitHub Actions 一键出 APK、adb 安装、配官方 ALVR v20.14.1 PC、按键与排错。

## 关键约束
- **电脑端必须用官方 ALVR v20.14.1**（协议锁：两端大版本必须一致），否则连不上。
- 沙箱无 Rust/NDK/JDK17 且 curl 被拦 → **未做本地编译**；正确性靠对照 v20.14.1 参考源码
  （`reference/` 下 `c_api_v20.14.1.rs` 等）逐函数静态核对保证。最终以 CI 构建 + 真机联调为准。

## 文件清单
- `README.md` —— 用户使用指南（重点）
- `app/src/main/cpp/cpp_main.cpp` —— 核心桥接层（重点）
- `app/build.gradle` `app/CMakeLists.txt` `app/src/main/AndroidManifest.xml`
- `build.gradle` `settings.gradle` `gradle.properties` `gradle/wrapper/gradle-wrapper.properties`
- `build.sh` —— 本地构建脚本
- `.github/workflows/build.yml` —— CI 自动出 APK
- `reference/` —— ALVR v20.14.1 C ABI 参考（技术核对）
