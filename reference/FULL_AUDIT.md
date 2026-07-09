# Qiyu-Port 项目全面审计：hallychou/ALVR-QIYU vs alvr-org/ALVR vs 本项目

> 审计时间：2026-07-10
> 审计方法：GitHub API 拉取完整项目树 + Python 解析 ELF 二进制 + AAR 反编译

## 一、三方项目关系

| 项目 | ALVR 版本 | 客户端形态 | Qiyu SDK 引入方式 |
|------|-----------|-----------|------------------|
| **hallychou/ALVR-QIYU** | 19.1.1 | ALVR 自家 client_openxr + Qiyu 补丁 | QiyuNativeSDK 子模块（AAR 依赖） |
| **alvr-org/ALVR** (最新) | 20.14.1 | client_openxr (OpenXR) | 无 Qiyu 支持 |
| **本项目 qiyu-port** | 20.14.1 (核心) | 自写 app/ + cpp_main.cpp | ❌ 最初只提取了 .so，缺 Java 侧 |

## 二、已发现并修复的遗漏项（按发现顺序）

### 1. openvr 子模块缺失 ✅
- ALVR 的 alvr_session crate 依赖 openvr 头文件
- 修复：build.sh 加 `git submodule update --init --recursive`

### 2. Gradle 仓库配置冲突 ✅
- 根 build.gradle 的 allprojects{repositories} 与 settings.gradle 的 FAIL_ON_PROJECT_REPOS 冲突
- 修复：删除根 build.gradle 的 allprojects 块

### 3. CMake 头文件路径错误 ✅
- `../../build` 应为 `../build`（相对 app/ 目录）
- 修复：CMakeLists.txt 和 jniLibs.srcDirs 路径修正

### 4. C ABI 字段对齐错误 ✅
- AlvrButtonValue：误用 `.body` → `BINARY._0` → 最终正确为 `binary`/`scalar`（cbindgen 命名规则）
- AlvrEvent：成员名大写（HAPTICS/STREAMING_STARTED/DECODER_CONFIG）
- 修复：逐字段对照 v20.14.1 c_api.rs 源码

### 5. Native 库加载顺序错误 ✅
- libqiyivrsdkcore.so DT_NEEDED libashreader.so，但 ashreader 排在它后面
- 修复：ELF 依赖分析 → 正确拓扑序 `vrapi→ashreader→sxrapi→qiyivrsdkcore→qiyuapi→alvr_client_core→native_lib`

### 6. libc++_shared.so 假阳性 ✅
- 最初以为 Qiyu .so 缺 libc++_shared.so，实际 ELF 分析证明它们用 libstdc++.so（系统自带）
- 修复：libc++_shared 改为 optional try/catch（不阻断加载）

### 7. **Qiyu SDK Java 类完全缺失** ✅ ← 根因
- libqiyivrsdkcore.so 的 JNI_OnLoad 调用 `FindClass("com/qiyi/qiyivrsdkcore/AndroidPlugin")` → 类不存在 → System.load 抛异常
- **缺失的 Java 类**（从 .so 二进制提取）：
  - `com.qiyi.qiyivrsdkcore.AndroidPlugin`（+ 8 个 Java 方法 + 5 个 native 方法 + EAppType 内部枚举）
  - `com.qiyi.qiyivrsdkcore.Vector3f`
  - `com.qiyi.qiyivrsdkcore.BoundaryHelper`（+ BoundaryData, ServiceContentObserver）
  - `com.qiyi.qiyivrsdkcore.ArchiveManager`
  - `com.qiyi.qiyivrsdkcore.BoundaryTestResult`
  - `com.qiyi.qiyivrsdkcore.SdkReceiver`
  - `com.qualcomm.sxrapi.SxrApi`（+ 30+ 内部类：SxrResult, sxrBeginParams, sxrDeviceInfo, sxrFrameParams, sxrHeadPose, etc.）
  - `com.qualcomm.sxrapi.SvrServiceClient`（+ State, SvrServiceEventListener, SvrServiceResponseHandler）
  - `com.qualcomm.svrapi.controllers.ControllerManager`（+ ControllerContext, ControllerConnection, etc.）
  - `com.qualcomm.sxrapi.xrcasting.SxrPresentationManager`（+ SxrPresentation）
  - `com.qiyi.presentation.QiyiPresentation` / `QiyiProjection` / `QiyiScreenShot`
  - `com.qualcomm.snapdragonvrservice.ISvrServiceInterface`（AIDL stub）
  - 共 **85 个 Java 类**
- **修复**：从 hallychou/QiyuNativeSDK 仓库下载 3 个 release AAR，提取 classes.jar 放入 `app/libs/`

### 8. Qiyu SDK Asset 缺失 ✅
- `assets/qiyu_recenter.png`（10KB）—— SDK 通过 AssetManager 加载
- 缺失会导致 recenter 功能崩溃
- 修复：从 AAR 提取到 `app/src/main/assets/qiyu_recenter.png`

### 9. AndroidManifest 权限缺失 ✅
- AAR manifest 声明了我们缺的权限：
  - `android.permission.READ_EXTERNAL_STORAGE`
  - `android.permission.WRITE_EXTERNAL_STORAGE`
  - `android:requestLegacyExternalStorage="true"`
- 修复：补入 AndroidManifest.xml

### 10. build.sh CI 自动化 ✅
- CI 环境没有 app/libs/ 里的 JAR 文件
- 修复：build.sh 新增 AAR 下载 + JAR/asset 提取步骤（curl + python3/unzip）

## 三、Java 类来源对照

| .so 文件 | 需要 Java 类的 JNI 方法 | 来源 AAR |
|----------|------------------------|---------|
| libqiyivrsdkcore.so | AndroidPlugin.onBoundaryChanged/onIPDChanged/sxrRecenter/updateBoundaryPoints/setNativeAssetManager | qiyivrsdkcore-v8a-release.aar |
| libqiyivrsdkcore.so | QiyiPresentation/QiyiProjection/QiyiScreenShot.* | qiyivrsdkcore-v8a-release.aar (实际在 sxrApi AAR) |
| libsxrapi.so | SxrApi.sxrInitialize/sxrBeginXr/sxrEndXr/sxrSubmitFrame/... (25个) | sxrApi-v8a-release.aar |
| libsxrapi.so | ControllerManager.OnControllerCallback, ControllerContext.* | sxrApi-v8a-release.aar |
| libsxrapi.so | SvrServiceClient.OnServiceCallback | sxrApi-v8a-release.aar |
| libashreader.so | AshReaderHelper.init/readKeyEvent/readPose/readState/sendCmd/uninit | ❓ 不在 3 个 AAR 中（可能由设备系统提供或 C 代码直接调用） |

## 四、最终文件清单

### app/libs/（Java 类 JAR）
- `qiyivrsdkcore-classes.jar`（19KB，11 类）—— AndroidPlugin, Vector3f, BoundaryHelper 等
- `sxrapi-classes.jar`（83KB，73 类）—— SxrApi, ControllerManager, SvrServiceClient 等
- `qiyuapi-classes.jar`（672B，1 类）—— BuildConfig

### app/src/main/assets/
- `qiyu_recenter.png`（10KB）—— SDK recenter 功能所需

### app/src/main/jniLibs/arm64-v8a/（原生 .so）
- libvrapi.so（1.5MB）—— 依赖：系统库
- libashreader.so（22KB）—— 依赖：libstdc++.so（系统）
- libsxrapi.so（2.1MB）—— 依赖：系统库
- libqiyivrsdkcore.so（3.6MB）—— 依赖：libsxrapi.so + libashreader.so
- libqiyuapi.so（244KB）—— 依赖：libqiyivrsdkcore.so + libsxrapi.so

### CI 构建产物（../build/alvr_client_core/）
- libalvr_client_core.so —— ALVR v20.14.1 Rust 串流核心
- alvr_client_core.h —— cbindgen 生成的 C ABI 头文件

### CMake 构建产物
- libnative_lib.so —— 我们的 cpp_main.cpp 桥接层

## 五、加载顺序（ELF DT_NEEDED 实证）

```
1. libc++_shared.so     (optional, try/catch)
2. libvrapi.so           → 系统库 only
3. libashreader.so       → libstdc++.so (系统)
4. libsxrapi.so          → 系统库 only
5. libqiyivrsdkcore.so   → libsxrapi.so ✓ + libashreader.so ✓
                           JNI_OnLoad: FindClass AndroidPlugin → JAR 提供 ✓
6. libqiyuapi.so         → libqiyivrsdkcore.so ✓ + libsxrapi.so ✓
7. libalvr_client_core.so → Rust 核心
8. libnative_lib.so      → 我们的桥接层
```

## 六、剩余风险（运行时，非编译期）

1. **AshReaderHelper 类缺失**：libashreader.so 的 JNI 方法引用 `com.iqiyi.vr.plugin.AshReaderHelper`，但该类不在 3 个 AAR 中。如果 qiyu_Init 内部通过 JNI 调用它，会运行时崩溃。但更可能的情况是：我们的 C++ 代码直接调用 C API，不经过 Java/JNI，所以这个类不需要。

2. **SxrApi VR 服务绑定**：SxrApi.sxrInitialize 内部会绑定 Qualcomm Snapdragon VR 服务（ISvrServiceInterface）。奇遇 Dream 设备上必须有这个系统服务，否则初始化失败。

3. **AndroidPlugin 方法签名**：VRActivity 调用 `AndroidPlugin.setNativeAssetManager(getAssets())`，如果实际方法是实例方法而非 static，会抛异常（已被 try/catch 包裹，不阻断）。

4. **渲染阶段**：加载成功后进入 initializeNative → qiyu_Init → eglInit → 渲染循环。lobby/stream 渲染可能有运行时问题（已在 cpp_main.cpp 加了 [trace] 埋点）。

5. **foveated rendering 参数**：cpp_main.cpp 里 foveation 中心/边缘参数留 0，可能需要调优。

## 七、与 hallychou 的关键差异

| 维度 | hallychou (19.1.1) | 本项目 (20.14.1) |
|------|-------------------|-----------------|
| ALVR 核心 | 19.1.1（旧） | 20.14.1（最新 release） |
| 客户端 | ALVR client_openxr + Qiyu 补丁 | 自写 app/ + cpp_main.cpp |
| Qiyu SDK | AAR 依赖（完整） | AAR JAR 提取（Java 类）+ jniLibs（.so） |
| C ABI | 19.1.1 c_api.rs | 20.14.1 c_api.rs（字段名/结构有变化） |
| OpenXR | 使用 ALVR 的 OpenXR 层 | 不使用（直接 C ABI） |
| 构建 | Gradle + Cargo | build.sh + Gradle + Cargo + CI |

本项目本质 = "hallychou 的 Qiyu 客户端方案 + ALVR 最新核心 v20.14.1"，但用自写的 cpp_main.cpp 替代了 ALVR 的 client_openxr 层，直接对接 C ABI。
