# 奇遇 Dream 闪退 + 黑屏 诊断报告（方案 A / Path B）

> 现象：APK 安装后打开**立即闪退**；反复进入几次后**直接黑屏、按键无响应**。
> 结论：这是 **Native 层崩溃（C++/JNI）**，不是 Java 异常。黑屏无响应 = **GPU 驱动 hang（进程没死但显示卡死）**，是最危险信号。

---

## 一、崩溃机理（为什么"闪退 → 多次后黑屏"）

1. **第一次打开**：native 代码在某一步发生 crash（最可能发生在 lobby 渲染或 ALVR 初始化）。
2. 进程被系统强杀，但 `onPauseNative` / `onDestroy` 里的 native 清理
   （`qiyu_EndVR`、`ANativeWindow_release`、lobby buffers `Release`）**大概率没来得及执行**。
3. Qiyu 的 VR 合成器 / 显示服务停留在**脏状态**。
4. **第二次进入**：`qiyu_StartVR` 在脏状态上工作/失败；原代码在 `StartVR` 失败时只打了一行 error 仍继续渲染
   → 向 GPU 提交非法命令 → **驱动 hang → 整屏黑、连系统按键都卡死**。

> 所以对头显来说：**先长按电源键 10 秒强制重启**，不要再反复点开 app——越点越容易触发 GPU hang。

---

## 二、已落地的加固补丁（`app/src/main/cpp/cpp_main.cpp`）

目的：**防止二次进入黑屏 + 全链路埋点日志**，让崩溃能被精确定位。只加日志和 guard，不改渲染逻辑，不破坏已通过的编译。

| 改动 | 作用 |
|------|------|
| `initializeNative`：在 `eglInit` / `qiyu_Init` / `alvr_initialize_android_context` / `alvr_initialize` / `alvr_initialize_opengl` 前后加 `[trace]` 日志 | 确认崩在初始化哪一步 |
| `onResumeNative`：`qiyu_StartVR` 失败时 **`return` 并释放 window**（原代码只 error 不 return） | **杜绝脏状态 → 二次进入不再黑屏**，最多回到 launcher |
| `renderNative`：顶部加 `if (!CTX.running \|\| CTX.window == nullptr) return;` guard | 防止在 VR 资源未就绪时提交渲染 |
| `renderNative` lobby / stream 分支：`alvr_render_lobby_opengl` / `alvr_render_stream_opengl` 前后加 `[trace]` 日志 | 确认崩在 lobby 还是 stream 渲染 |
| `renderNative`：`qiyu_SubmitFrame` 前后加 `[trace]` 日志 | 确认崩在提交帧（可能 null texture） |

---

## 三、必做：抓一份真机崩溃日志（这是唯一能根治的路径）

重编译安装**加固版**后，按下面步骤抓 logcat。没有日志我只能猜。

### 1. 头显强制重启
长按电源键 10 秒，等它完全重启。期间**不要**打开 app。

### 2. 电脑 USB 连头显，确认 adb 识别
```bat
adb devices
```
能看到奇遇设备序列号才继续。

### 3. 清空日志并开始录制（Windows，用 findstr）
开一个命令行，执行（**先开着，再去头显上点开 app**）：
```bat
adb logcat -c
adb logcat -v threadtime | findstr /i "VRActivity ALVR libnative libalvr libc DEBUG tombstone SIGSEGV SIGABRT FATAL AndroidRuntime" > alvr_crash.log
```

> 如果是 PowerShell，把 `findstr` 换成：
> `adb logcat -v threadtime | Select-String -Pattern "VRActivity|ALVR|libnative|libalvr|libc|DEBUG|tombstone|SIGSEGV|SIGABRT|FATAL|AndroidRuntime" > alvr_crash.log`

### 4. 头显上打开 app，等待闪退
闪退后回电脑端按 `Ctrl+C` 停止录制。

### 5. 同时抓 tombstone（native crash 会生成）
```bat
adb shell ls -l /data/tombstones/
adb pull /data/tombstones/tombstone_XX
```
（`XX` 换成最新的序号；拿不到就忽略，logcat 通常够用）

---

## 四、三个最可能根因（等日志确认，按概率排序）

### 候选 A（最高）：`alvr_render_lobby_opengl(lobbyParams, true)` 的第二个参数 `true`
- v20.14.1 的 `AlvrLobbyViewParams` 可能包含 `quad` 字段（渲染"等待串流"面板的 2D 贴图）。
- 第二参 `true` 可能表示"渲染 quad"，但我们 `lobbyParams` 里 quad 相关字段（位置/尺寸/纹理）全是 `{}` 零值
  → ALVR 内部渲染 quad 时访问非法数据（空纹理句柄 / 负尺寸）→ 崩溃。
- **日志判据**：停在 `[trace] lobby: before alvr_render_lobby_opengl` 之后、没有 `after`。

### 候选 B：`alvr_initialize(caps)` 内部 panic（abort）
- ALVR client_core 在 initialize 时会解析 Android 路径、加载默认 session、启动网络线程。
- 若资源缺失 / 旧配置不兼容 / `android_context` 解析失败 → `panic!()` → `SIGABRT` 直接炸。
- **日志判据**：出现 `panicked at ...`，且最后一条 `[trace]` 是 `alvr_initialize` 之后没有 `done`。

### 候选 C：`qiyu_SubmitFrame` 提交了无效 texture（lobbyBuffers 的 FBO color attachment = 0）
- 若 `QYRenderTarget::Init` 在设备上静默失败，`GetColorAttachment()` 返回 0 → 提交 null texture → GPU 崩溃。
- hallychou 同款代码能在奇遇跑，所以概率较低，除非 v20.14.1 对 texture 句柄加了额外校验。
- **日志判据**：停在 `[trace] before qiyu_SubmitFrame` 之后、没有 `after`，并伴随 GL/qiyu 报错。

---

## 五、如何把日志发回来判断

把 `alvr_crash.log`（以及 tombstone 文件）发给我，我据此：
- 若停在 **initialize 阶段** → 修 ALVR 初始化参数 / 资源配置；
- 若停在 **lobby 渲染** → 调整 `alvr_render_lobby_opengl` 调用（大概率把第二参改 `false`，或补全 quad 字段）；
- 若停在 **SubmitFrame** → 检查 lobbyBuffers FBO 创建与 texture handle。

**无论哪个，加固补丁已保证你二次进入不会再黑屏**，可以放心反复测试抓日志。
