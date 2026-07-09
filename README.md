# ALVR 奇遇 Dream（Qiyu）串流客户端

这是一个为 **爱奇艺奇遇 Dream（Qiyu Dream）VR 一体机** 定制的 ALVR 无线串流客户端。
它把你 Windows 电脑上的 SteamVR 游戏，通过 Wi-Fi 无线串流到奇遇 Dream 头显里。

> 本客户端基于 **ALVR v20.14.1**（官方最新稳定版）重写，已适配奇遇 Dream 的原生 SDK，
> 可以直接和**官方 ALVR v20.14.1** 的电脑端配合使用 —— 不需要奇遇专属的电脑端。

---

## 一、最重要的事：电脑端版本必须对上

ALVR 的电脑端和头显端**版本必须完全一致**（协议锁：两端大版本号必须相同）。
所以：

- 头显端（本客户端）：版本号 `20.14.1-qiyu`
- 电脑端：**必须安装官方 ALVR v20.14.1**

下载官方 ALVR（请认准 `v20.14.1` 这个版本）：
https://github.com/alvr-org/ALVR/releases/tag/v20.14.1

> 如果你电脑端是别的版本（比如更新的 nightly），头显端会连不上。务必都用 v20.14.1。

---

## 二、拿到 APK（最省事：一键自动构建）

你不需要自己装编译器。把本仓库推到 GitHub 后，由 GitHub 自动帮你编译出 APK：

1. 注册一个 GitHub 账号（免费）。
2. 把 `qiyu-port` 这个文件夹作为仓库推到 GitHub。
3. 打开仓库页面 → **Actions** → 找 `Build ALVR Qiyu APK` → 点 **Run workflow**（或推送代码会自动触发）。
4. 等十几分钟（首次编译 ALVR 核心较慢），完成后在 **Artifacts** 里下载 `alvr-qiyu-apk`。
5. 解压得到 `app-release.apk`。

> 这就是“傻瓜化一步到位”：你只管把代码推上去，APK 自动生成。

---

## 三、安装到头显

把头显通过 USB 连到电脑，打开电脑上的命令行（或手机助手），执行：

```bash
adb install -r app-release.apk
```

如果提示“多个设备”，先 `adb devices` 看清楚，再用 `adb -s <设备序列号> install ...`。

> 没有 `adb`？装一个 [Android Platform Tools](https://developer.android.com/tools/releases/platform-tools) 即可。
> 头显需开启“开发者模式 / USB 调试”。

---

## 四、开始串流

1. 电脑端：安装并启动官方 **ALVR v20.14.1**（Firefox/Chrome 打开它的 Web 管理页面）。
2. 头显端：在奇遇 Dream 的“应用”里找到 **ALVR**（图标是齿轮/信号），启动它。
3. 头显里会显示一组 **配对码（6 位）**。在电脑端 ALVR 的 Web 页面里输入这串码完成配对。
4. 配对成功后，在电脑上启动 SteamVR，头显里就会出现 VR 画面。
5. 在头显里按菜单键（或其他 ALVR 设定的快捷键）可呼出 ALVR 菜单 / 退出。

### 常见头显按键映射（本客户端按 Oculus Touch 布局上报）
- 左手菜单键 = 系统菜单
- A / B（右手）、X / Y（左手）= 常规按键
- 扳机 / 握把 = 对应按键
- 遥杆 = 移动 / 视角

---

## 五、常见问题

| 现象 | 可能原因 / 解决办法 |
|------|---------------------|
| 头显端连不上电脑 | 电脑端不是 v20.14.1；两端版本不一致。重装 v20.14.1。 |
| 配对码一直不出现 | 头显与电脑不在同一 Wi-Fi；或电脑防火墙挡了 ALVR 端口。 |
| 画面卡顿 / 延迟高 | 用 5GHz Wi-Fi 或 Wi-Fi 6；电脑用网线连路由器；降低码率（ALVR 设置里调）。 |
| 头显提示“不是 VR 应用” | 已声明 Wave/VR 模式；若你的奇遇固件用别的启动类别，见下文“高级”。 |
| 黑屏但有声音 | 解码器问题；本客户端默认用硬件解码（H264/HEVC），一般无需改动。 |

---

## 六、给开发者 / 进阶说明

### 项目结构
```
qiyu-port/
├── app/                      # Android 应用（Java 入口 + C++ 桥接层）
│   ├── build.gradle
│   ├── CMakeLists.txt
│   └── src/main/
│       ├── cpp/cpp_main.cpp  # ★ 核心：把奇遇 SDK 桥接到 ALVR 串流核心
│       └── jniLibs/          # 奇遇原生 SDK 的 .so（已内置）
├── build.sh                  # 本地一键构建脚本
├── build.gradle / settings.gradle / gradle.properties
├── .github/workflows/build.yml  # CI：自动编译并产出 APK
└── reference/                # ALVR v20.14.1 的 C ABI 参考（技术核对用）
```

### 它到底做了什么（原理）
- ALVR 的串流/解码核心是一个 Rust 库 `alvr_client_core`（跨平台）。
- 奇遇 Dream 有自己专用的原生 SDK（`qiyuapi`），不走标准 OpenXR。
- `cpp_main.cpp` 负责：用奇遇 SDK 取头显姿态/控制器/提交画面，
  再把这些数据翻译成 ALVR 的 C ABI（`alvr_initialize` / `alvr_send_tracking` /
  `alvr_start_stream_opengl` / `alvr_render_stream_opengl` 等），
  由 `alvr_client_core` 完成网络收发、解码、合成。

### 关键改动（相对原 hallychou 旧版 / 旧 ALVR）
1. **对齐到 ALVR v20.14.1 的 C ABI**：旧 fork 用的是多年前的 ALVR 接口，
   大量函数签名已变（如 `alvr_initialize` 改为先 `alvr_initialize_android_context` 再传
   `AlvrClientCapabilities`；`alvr_send_views_config`→`alvr_send_view_params`；
   `alvr_get_prediction_offset_ns` 已移除改用 `qiyu_PredictDisplayTime` 等）。
2. **cbindgen 命名修正**：v20.14.1 用 `QualifiedScreamingSnakeCase`，
   事件/枚举名是**全大写带前缀**（如 `ALVR_EVENT_STREAMING_STARTED`、
   `ALVR_BUTTON_VALUE_BINARY`），统一修正了旧代码里大小写混用导致的编译错误。
3. **`AlvrLobbyViewParams` 结构展平**：v20.14.1 把 `view_params` 嵌套去掉，
   直接是 `pose` / `fov`，已对应修改。
4. **补齐 `AlvrDecoderConfig.config_buffer_size`**、`AlvrClientCapabilities` 字段，避免未初始化。
5. **移除 Oculus 专属依赖/清单项**，改为声明奇遇（Wave 系）VR 模式。
6. 工程改造为独立可构建的 Gradle 项目 + CI，无需依赖旧 fork 的整套 ALVR 源码。

### 本地构建（需要会一点环境）
 prerequisites: Android SDK + NDK r25、JDK 17、Rust（含 `aarch64-linux-android` 目标）、
 `cargo-ndk`、`cbindgen`。然后：
```bash
bash build.sh          # 拉取 ALVR v20.14.1 → 编 alvr_client_core → 生成头 → 打 APK
```
产物在 `app/build/outputs/apk/release/`。

### 如果你的奇遇固件启动类别不同
`app/src/main/AndroidManifest.xml` 里声明了 `com.htc.vr.application.mode = vr_only`
和 Wave VR 的 intent category。若你的系统识别方式不同，改这一处即可，不影响串流逻辑。
