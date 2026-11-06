# 配置说明

`lib/zephyr-env.sh` 由项目 `envsetup.sh` source。项目层声明路径和项目差异，共享脚本负责构建、profile、烧录和结果处理。

## 最小配置

```bash
export FW_SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FW_BUILD_ROOT="${FW_SOURCE_DIR}/build"
export FW_BOARD="your_board"
export FW_BASE_CONF_FILE="${FW_SOURCE_DIR}/prj.conf"
export FW_BASE_DTC_OVERLAY_FILE="${FW_SOURCE_DIR}/app.overlay"
export FW_RELEASE_CONF_FILE="${FW_SOURCE_DIR}/prj_release.conf"
export FW_RELEASE_DTC_OVERLAY_FILE="${FW_SOURCE_DIR}/app_release.overlay"

export FW_FLASH_BACKEND="jlink"
export FW_FLASH_DEVICE="your_device"
export FW_FLASH_INTERFACE="SWD"
export FW_FLASH_SPEED="4000"

export FW_DEVTOOLS_ROOT="${PROJECT_ROOT}/tools/zephyr-env"
source "${FW_DEVTOOLS_ROOT}/lib/zephyr-env.sh"
```

## 构建变量

| 变量 | 用途 |
| --- | --- |
| `FW_SOURCE_DIR` | Zephyr application source directory |
| `FW_BUILD_ROOT` | debug 构建根目录，默认 `${FW_SOURCE_DIR}/build` |
| `FW_DEBUG_BUILD_DIR` | debug 目录覆盖值 |
| `FW_RELEASE_BUILD_DIR` | release 目录覆盖值，默认 `${FW_BUILD_ROOT}_release` |
| `FW_APP_NAME` | 查找 `${build}/${FW_APP_NAME}/zephyr/zephyr.hex` |
| `FW_BOARD` | board 名称 |
| `FW_BOARD_ROOT` | `BOARD_ROOT` CMake 参数 |
| `FW_DEFAULT_MODEL` | 默认型号；型号目录、配置及烧录选择 |
| `FW_MODEL_CONF_FILES` | `fw_project_model` 设置的型号 Kconfig 文件数组 |
| `FW_MODEL_OVERLAY_FILES` | `fw_project_model` 设置的型号 overlay 文件数组 |
| `FW_COMMON_CMAKE_ARGS` | 所有 profile 的 CMake 参数数组 |
| `FW_EXTRA_CONFIG_FILES` | 参与 fingerprint 的额外文件数组 |

## 型号

项目可选设置默认型号，并实现型号 hook。每次调用都会先清空型号文件数组，再由 hook 填充；不支持型号的项目无需 hook，传入 `-m` 会被拒绝。

```bash
export FW_DEFAULT_MODEL=a

fw_project_model() {
    case "$1" in
    a) ;;
    b)
        FW_MODEL_CONF_FILES=("${FW_SOURCE_DIR}/prj_b.conf")
        FW_MODEL_OVERLAY_FILES=("${FW_SOURCE_DIR}/app_b.overlay")
        ;;
    *) echo "Unknown model: $1" >&2; return 2 ;;
    esac
}
```

`wbuild -m b`、`wconfig -m b`、`wflash -m b` 显式选择型号；无 `-m` 时使用 `FW_DEFAULT_MODEL`（未设置则维持旧的无型号行为）。release 配置排在型号配置之前；多个文件作为 CMake 分号列表传入，并逐个校验及 fingerprint。型号构建目录为 `${FW_BUILD_ROOT}_b`，release 为 `${FW_BUILD_ROOT}_b_release`。型号选择与 `FW_DEBUG_BUILD_DIR`、`FW_RELEASE_BUILD_DIR` 覆盖值冲突时拒绝执行。型号烧录只从所选型号目录找 HEX；不会回退到父目录或其他型号。`-p` 可显式指定 HEX 文件。

`wbuild -m b -- <args...>` 会将 `--` 后参数原样传给 west/CMake。

## Windows Git Bash

Git Bash 支持运行共享 Bash 脚本。需要预先安装 Windows 版本的 NCS 工具链，并让以下命令可用：

```bash
west --version
cmake --version
ninja --version
python --version
```

烧录工具可以使用命令名：

```bash
export FW_JLINK_EXE="JLink.exe"
export FW_PYOCD_EXE="pyocd.exe"
export FW_PROBE_RS_EXE="probe-rs.exe"
export FW_OPENOCD_EXE="openocd.exe"
```

也可以指定绝对路径：

```bash
export FW_JLINK_EXE="C:/Program Files/SEGGER/JLink/JLink.exe"
```

Git Bash 下使用正斜杠。共享脚本只在调用原生烧录工具时使用 `cygpath -w` 转换路径；构建配置和项目路径保持当前 shell 的路径格式。

可选地强制路径模式：

```bash
export FW_NATIVE_PATH_MODE=auto    # 默认，按 MSYSTEM/OSTYPE 判断
export FW_NATIVE_PATH_MODE=1       # 强制转换
export FW_NATIVE_PATH_MODE=0       # 禁止转换
```

构建目录：

```text
${FW_SOURCE_DIR}/build/
${FW_SOURCE_DIR}/build_release/
```

## 配置文件

推荐命名：

```text
prj.conf
prj_release.conf
app.overlay
app_release.overlay
sysbuild.conf
sysbuild_release.conf
sysbuild/mcuboot.conf
sysbuild/mcuboot_release.conf
```

`prj_release.conf` 和 `app_release.overlay` 是可选的。存在时，release 构建通过 `EXTRA_CONF_FILE` 和 `EXTRA_DTC_OVERLAY_FILE` 使用；不存在时只使用基础配置和 profile CMake 参数。

共享脚本会把 profile、board、路径、CMake 参数及以下存在的文件纳入 fingerprint：

```text
prj.conf
app.overlay
prj_release.conf
app_release.overlay
sysbuild.conf
sysbuild_<profile>.conf
sysbuild.cmake
sysbuild/mcuboot.conf
sysbuild/mcuboot_<profile>.conf
sysbuild/mcuboot.overlay
sysbuild/mcuboot_<profile>.overlay
```

## Profile

```bash
wbuild
wbuild -r
wbuild --release
wconfig
wconfig -r
```

项目可定义 profile hook：

```bash
fw_project_profile() {
    case "$1" in
    debug)
        FW_CMAKE_ARGS=("-DDEBUG_THREAD_INFO=On")
        ;;
    release)
        FW_CMAKE_ARGS=("-DDEBUG_THREAD_INFO=Off")
        ;;
    esac
}
```

## 原生烧录 backend

```bash
wflash
wflash -r
wflash --backend jlink
wflash -b pyocd
wflash -r --backend probe-rs
```

支持：

| Backend | 工具 | 关键变量 |
| --- | --- | --- |
| `jlink` | `JLinkExe` | `FW_JLINK_EXE` |
| `pyocd` | `pyocd flash` | `FW_PYOCD_EXE`, `FW_PYOCD_TARGET` |
| `probe-rs` | `probe-rs download` | `FW_PROBE_RS_EXE`, `FW_PROBE_RS_CHIP` |
| `openocd` | `openocd` | `FW_OPENOCD_EXE`, cfg 变量 |

通用变量：

```bash
export FW_FLASH_BACKEND="jlink"
export FW_FLASH_DEVICE="NRF54L15_M33"
export FW_FLASH_INTERFACE="SWD"
export FW_FLASH_SPEED="4000"
```

OpenOCD：

```bash
export FW_OPENOCD_INTERFACE_CFG="/opt/openocd/scripts/interface/cmsis-dap.cfg"
export FW_OPENOCD_TARGET_CFG="/opt/openocd/scripts/target/nrf54l.cfg"
FW_OPENOCD_ARGS=()
```

## 工具版本隔离

不要让 NCS toolchain 的 `PATH` 决定烧录工具版本。推荐使用绝对路径：

```bash
export FW_JLINK_EXE="/opt/jlink/V9.46/JLinkExe"
export FW_PYOCD_EXE="/opt/pyocd/bin/pyocd"
export FW_PROBE_RS_EXE="/opt/probe-rs/bin/probe-rs"
export FW_OPENOCD_EXE="/opt/openocd/V0.12/bin/openocd"
```

NCS PATH 用于 `west`、CMake、Ninja 和编译器；各 flash backend 使用自己的可执行文件路径。

## Worktree 和 submodule

项目路径应从当前 `envsetup.sh` 派生：

```bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FW_SOURCE_DIR="${PROJECT_ROOT}"
```

推荐把本仓库作为 submodule：

```text
<project>/tools/zephyr-env/lib/zephyr-env.sh
```

没有 submodule 时可手动指定：

```bash
export FW_DEVTOOLS_ROOT="/path/to/zephyr-env"
```
