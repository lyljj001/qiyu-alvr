# 本地编译环境搭建（ALVR × Qiyu Dream 客户端）

> 适用：不想等 GitHub Actions、或 CI 反复报错时，在本地一次性把 APK 编出来。
> 目标产物：可安装的 `app/build/outputs/apk/release/app-release.apk`

---

## 0. 硬件 / 系统建议

- 磁盘：**至少 25 GB 空闲**（Rust 依赖 + NDK + 构建中间产物很占空间）
- 内存：8 GB 以上
- 系统：**WSL2 / Ubuntu 22.04**（推荐）或原生 Linux；macOS 也可（Android 交叉编译没问题）

> Windows 原生 CMD/PowerShell 也能跑，但本仓库的 `build.sh` 是 bash 脚本，
> 用 **WSL2 / Git Bash** 最省心。下面以 WSL2/Ubuntu 为例。

---

## 1. 安装 Rust 工具链

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# 装完按提示 source 一下环境变量，或新开一个终端
source "$HOME/.cargo/env"

# 添加 Android 交叉编译目标
rustup target add aarch64-linux-android
```

## 2. 安装 cargo-ndk + cbindgen

```bash
cargo install cargo-ndk --version 4.1.2
cargo install cbindgen  --version 0.26.0
# 注意：这两个会从源码编译，首次安装约 3~8 分钟，耐心等
```

## 3. 安装 Android SDK + NDK r25 + CMake

方式 A（推荐，用 sdkmanager）：

```bash
# 下载 commandlinetools
cd ~
mkdir -p Android/Sdk/cmdline-tools
cd Android/Sdk/cmdline-tools
curl -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip cmdline-tools.zip
mv cmdline-tools latest
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --licenses
sdkmanager "platforms;android-33" "build-tools;33.0.0" "ndk;25.1.8937393" "cmake;3.22.1"
```

方式 B（只装 NDK，不用 sdkmanager）：

```bash
cd /tmp
curl -o ndk.zip https://dl.google.com/android/repository/android-ndk-r25b-linux.zip
unzip ndk.zip -d "$HOME/Android/"
export ANDROID_NDK="$HOME/Android/android-ndk-r25b"
```

设置环境变量（建议写进 `~/.bashrc`）：

```bash
export ANDROID_HOME="$HOME/Android/Sdk"          # 方式 A
# export ANDROID_NDK="$HOME/Android/android-ndk-r25b"  # 方式 B 用这个
export ANDROID_NDK_HOME="$ANDROID_NDK"
export ANDROID_NDK_ROOT="$ANDROID_NDK"
```

## 4. 安装 JDK 17

```bash
sudo apt update && sudo apt install -y openjdk-17-jdk
# 或：brew install openjdk@17 (macOS)
```

## 5. 安装 Gradle（仓库自带 gradlew 则跳过）

```bash
# 如果仓库根目录有 gradlew，直接用它即可：./gradlew assembleRelease
wget -q https://services.gradle.org/distributions/gradle-7.6.1-all.zip -O /tmp/gradle.zip
unzip -q /tmp/gradle.zip -d "$HOME/gradle"
export PATH="$HOME/gradle/gradle-7.6.1/bin:$PATH"
```

## 6. 开始构建

```bash
cd qiyu-port
bash build.sh            # 1) 克隆 ALVR v20.14.1 + 拉子模块  2) 编译 alvr_client_core
                         #    3) cbindgen 生成头文件  4) 把 .so + 头文件放进 build/
gradle assembleRelease   # 或 ./gradlew assembleRelease  —— 生成最终 APK
```

产物：

```
app/build/outputs/apk/release/app-release.apk
```

> `build.sh` 已经自动处理了两件最容易踩坑的事：
> 1. **Git 子模块**：`alvr_session` 的 `build.rs` 需要 `openvr/headers/openvr_driver.h`，
>    这个文件在 `openvr` 子模块里，脚本已经 `submodule update --init --recursive` 拉取。
> 2. **NDK 路径**：自动探测并锁定到 r25，避免 `ANDROID_HOME` 指向 NDK 目录导致的
>    路径重复（`.../ndk/25/ndk/25`）和 cargo-ndk 的 platform 标志误用。

---

## 7. 常见报错速查

| 报错 | 原因 | 解决 |
|---|---|---|
| `Missing openvr header files, did you clone the submodule?` | 没拉子模块 | 确保 `build.sh` 里的 `submodule update` 跑到了；或手动 `git submodule update --init --recursive` |
| `cargo-ndk panicked: unknown package: 26` | 4.x 把 `-p 26` 当成 cargo 包名 | 不要用 `-p 26`，改用环境变量 `CARGO_NDK_PLATFORM=26`（脚本已处理） |
| NDK 路径出现 `.../ndk/25/ndk/25` | `ANDROID_HOME` 被设成 NDK 目录 | 设 `ANDROID_HOME` 为 SDK 根目录，`ANDROID_NDK` 单独指 NDK |
| `failed to run custom build command for alvr_session` | 子模块 / 头文件缺失 | 见上 |
| CMake 找不到 NDK | `ANDROID_NDK` 未导出 | `export ANDROID_NDK=...` 后再 `gradle assembleRelease` |

---

## 8. 完全离线复现（CI 等价）

GitHub Actions 的 `.github/workflows/build.yml` 就是本流程的自动化版本。
本地照着第 1~6 步走，等价于一次成功的 CI 构建。
