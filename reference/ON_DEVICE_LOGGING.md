# 无 USB 取日志指南（奇遇 Dream 一体机）

你做无线串流，说明头显和电脑在同一个 Wi-Fi 下。取日志有两条路，按推荐顺序：

---

## 方法一：无线 ADB（最干净，推荐）

不需要任何线缆。前提：头显系统版本支持无线调试。

### 1. 在头显上开启无线调试
- **Android 11+**：设置 → 系统 → 开发者选项 → **无线调试** → 打开。
  - 点进去会显示「配对码」和 `IP:端口`。
- **奇遇/旧版 Android（9/10）**：部分国产 ROM 在 开发者选项 里直接有「**无线 ADB** / **网络调试**」开关；打开即可。
  - 如果找不到这个开关，说明该固件只能靠 USB 开启 `adb tcpip`，那就走方法二（文件法），不依赖 ADB。

### 2. 在电脑上连接
```bat
:: 先配对（仅 Android 11+ 无线调试需要，按头显上显示的配对码）
adb pair 头显IP:配对端口

:: 再连接（用一个长期监听端口，一般 5555；无线调试显示的是另一个连接端口，以头显提示为准）
adb connect 头显IP:端口
adb devices
```
看到设备状态 `device` 即连上。

### 3. 抓日志（头显上打开 app 等闪退，电脑端）
```bat
:: 实时看，崩溃时 Ctrl+C 停下，复制终端内容发我
adb logcat -v threadtime | findstr /i "VRActivity ALVR libnative libalvr libc DEBUG tombstone SIGSEGV SIGABRT FATAL AndroidRuntime session start trace"

:: 或者先清空再录制到文件
adb logcat -c
adb logcat -v threadtime > alvr_crash.log
:: （打开 app → 闪退 → Ctrl+C）
```

> 注意：用无线调试时，`adb connect` 的端口和 `adb pair` 的端口不同，以头显界面提示为准。

---

## 方法二：一体机本地文件（100% 不需要电脑/USB）

已在新版 `cpp_main.cpp` 的 `log()` 里挂了文件镜像：**每一次日志（含 ALVR Rust 的 panic 文本）都会实时 `fflush` 写进头显存储**，崩溃前最后一行必然落盘。文件位置（任一处存在即可）：

```
/sdcard/Android/data/alvr.client/files/alvr_runtime.log   ← 应用私有目录，必定可写
/data/local/tmp/alvr_runtime.log                          ← shell 可读，adb pull 方便
/sdcard/Download/alvr_runtime.log                         ← 公共目录（无权限时可能为空）
```

### 怎么把文件弄出来（任选）
1. **无线 ADB pull**（若方法一可用）：
   ```bat
   adb pull /sdcard/Android/data/alvr.client/files/alvr_runtime.log .
   adb pull /data/local/tmp/alvr_runtime.log .
   ```
2. **头显自带文件管理器**：用头显里的「文件管理 / 我的文件」应用打开上面路径，找到 `alvr_runtime.log`，**截图最后 ~30 行**发我（或长按分享/发送到微信之类的）。
3. **局域网共享**：若头显有「文件共享 / SMB / FTP」开关，开起来从电脑访问拷贝。

### 我需要你看什么
打开文件，找 `================ ALVR session start ================` 这一行（每次启动一条），
往下看**最后成功打印的 `[trace]` 是哪一句**，以及它之后**有没有对应的 `done` / `after`**。例如：

- 停在 `lobby: before alvr_render_lobby_opengl` 且没 `after` → 崩在 lobby 渲染（假设 A）。
- `alvr_initialize` 之后没有 `done`，且文件里有 `panicked at ...` → ALVR 初始化 panic（假设 B）。
- 停在 `before qiyu_SubmitFrame` 没 `after` → 帧提交时提交了无效 texture（假设 C）。

把这几行原文发我即可，不用发整个文件。**panic 文本如果在文件里出现，是最直接的定位证据。**

---

## 关键提醒
- **不要反复点开 app 直到拿到日志**：之前黑屏无响应是 GPU 驱动 hang。新版本已加 `qiyu_StartVR` 失败即释放的 guard，二次进入最多回 launcher，不再死锁，但拿日志前仍尽量少折腾。
- 若头显卡死：长按电源键 10 秒强制重启。
- 文件是**追加模式**，会越攒越大。定位完后可删掉这三个文件，或重装 app 清空应用私有目录。

---

## 一句话流程
1. 重编译并安装带文件日志的 APK。
2. 头显上打开 app 一次（闪退）。
3. 用「无线 ADB pull」或「头显文件管理器截图」取出 `alvr_runtime.log` 最后 30 行。
4. 发我，我据此精确定位并修复。
