# 无 USB / 无无线调试 取崩溃日志（奇遇 Dream）

系统设置没有「无线调试」开关，也不用 USB。新方案让 app **自己把崩溃原因显示在屏幕上**。

---

## 为什么上一版「三个地方都没日志」

上一版把日志写到 `/sdcard/Download`、`/data/local/tmp` 等路径，在 **release 包（API 33）** 下全部写不进去（scoped storage 限制 + 目录没 mkdir），所以日志器其实是死的——崩溃早发生在我们能打印之前，文件自然全空。这反而说明：**崩溃极可能发生在 native 库加载 / 初始化阶段**，比渲染还早。

---

## 新版怎么做（已改 `VRActivity.java` + `cpp_main.cpp`）

1. **库加载移出 `static` 块、改在 `onCreate` 里 try/catch**
   - 如果 `libalvr_client_core.so` / `libnative_lib.so` 加载失败（缺符号、ABI 不匹配、Rust 静态初始化 panic），会**直接弹出对话框显示确切错误**，而不是静默闪退。
2. **C++ 日志写到 app 私有目录** `/data/data/alvr.client.qiyu/files/alvr_runtime.log`
   - 由 Java 用 `setLogFilePath()` 指定，必定可写、无需任何权限、自动 mkdir。
3. **每次启动检测上一次是否「干净退出」**：`destroyNative` 正常退出会写 `=== ALVR session clean exit ===`；若上次没有这个标记（即任何位置崩溃），**下次打开 app 就弹窗显示上次日志尾部**。
4. **弹窗内容同时备份到** `/sdcard/Download/alvr_crash.txt`（尽力而为），以防 VR 合成器盖住 Android 对话框。

---

## 你需要做的（两步）

1. 重编译并安装这个新版本（已含上述改动）。
2. 打开 app：
   - **情况 A（库加载失败）**：立刻弹出「ALVR Qiyu - debug info」对话框，里面是确切错误（例如 `dlopen failed: cannot locate symbol "alvr_xxx"`、`library "libalvr_client_core.so" not found`、`has bad ELF magic` 等）。**截图发我**。
   - **情况 B（库加载成功但后续崩溃）**：第一次可能仍闪退（日志已落盘）；**再打开一次**，这次会弹出上次崩溃的日志尾部。**截图发我**。
   - 若弹窗被 VR 画面盖住看不到：用头显自带的「文件管理」应用打开 `内部存储/Download/alvr_crash.txt`，**截图最后 ~40 行**发我。

---

## 我需要你发的内容

- 情况 A：对话框里的**完整错误文本**（最关键，直接定位 .so 问题）。
- 情况 B：日志尾部，重点看最后一次成功的 `[trace]` 是哪句、有没有对应的 `done`/`after`，以及是否出现 `panicked at ...`。
  - 停在 `calling eglInit` 没 `eglInit done` → 崩在 eglInit（我们自己的 GL 初始化）。
  - 停在 `lobby: before alvr_render_lobby_opengl` 没 `after` → 崩在 lobby 渲染。
  - `alvr_initialize` 后无 `done` 且出现 `panicked at` → ALVR 初始化 panic。

把截图或文本发我，即可精确定位并修复，无需 USB、无需无线调试。

---

## 备注
- 崩溃日志文件是追加模式，会越来越大。定位完可删 `/data/data/alvr.client.qiyu/files/alvr_runtime.log` 与 `Download/alvr_crash.txt`，或重装 app 清空。
- 若头显卡死：长按电源键 10 秒强制重启。
