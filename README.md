# zephyr-env

共享 Zephyr/NCS 固件构建与原生烧录工具。

`zephyr-env` 提供三条 Shell 命令：

- `wbuild`：构建 Zephyr/NCS application
- `wflash`：调用原生烧录工具
- `wconfig`：显示当前项目、profile、路径和工具配置

`wflash` 不使用 `west flash` 或 Zephyr runner，直接调用 J-Link、pyOCD、probe-rs、OpenOCD。

## 特性

- debug/release profile
- 每个 worktree 独立构建目录
- sysbuild/MCUboot 配置 fingerprint
- J-Link、pyOCD、probe-rs、OpenOCD 原生 backend
- 烧录工具与 NCS toolchain 版本隔离
- 支持仓库根目录 app 和 app 子目录
- 支持 `BOARD_ROOT` 和额外 Zephyr modules

## 集成

推荐将仓库作为项目 submodule：

```bash
git submodule add <zephyr-env-url> tools/zephyr-env
```

项目 `envsetup.sh` 设置项目参数：

```bash
#!/usr/bin/env bash

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export FW_SOURCE_DIR="${PROJECT_ROOT}"
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

已有项目也可以通过环境变量使用外部 checkout：

```bash
export FW_DEVTOOLS_ROOT="/path/to/zephyr-env"
source "${FW_DEVTOOLS_ROOT}/lib/zephyr-env.sh"
```

更多模板：

```text
examples/envsetup-root-app.sh
examples/envsetup-app-subdir.sh
```

## 构建

默认构建 debug：

```bash
wbuild
```

构建 release：

```bash
wbuild -r
wbuild --release
```

强制 pristine 或显示详细输出：

```bash
wbuild -p
wbuild -v
wbuild -r -p
```

构建目录：

```text
<project>/build/          # debug
<project>/build_release/  # release
```

构建目录从当前 `FW_SOURCE_DIR` 派生，不使用其他 worktree 的路径。

## 配置检查

```bash
wconfig
wconfig -r
```

`wconfig` 显示实际使用的 source、build、board、配置文件、backend 和工具路径，不执行构建或烧录。

## 原生烧录

默认烧录 debug 镜像：

```bash
wflash
```

烧录 release 镜像：

```bash
wflash -r
wflash --release
```

选择 backend：

```bash
wflash --backend jlink
wflash --backend pyocd
wflash --backend probe-rs
wflash --backend openocd
```

短参数：

```bash
wflash -b pyocd
wflash -r -b probe-rs
```

支持的原生命令：

| Backend | 原生命令 |
| --- | --- |
| `jlink` | `JLinkExe` |
| `pyocd` | `pyocd flash` |
| `probe-rs` | `probe-rs download` |
| `openocd` | `openocd -c "program ... verify reset exit"` |

指定镜像：

```bash
wflash -p /path/to/image.hex
```

J-Link 会额外检查目标连接错误文本，因为 J-Link Commander 可能在连接失败时仍返回 `0`。其他 backend 以原生命令退出码为主。

## 工具版本隔离

NCS toolchain 负责 `west`、CMake、Ninja 和编译器。烧录工具可以使用独立版本：

```bash
export FW_JLINK_EXE="/opt/jlink/V9.46/JLinkExe"
export FW_PYOCD_EXE="/opt/pyocd/bin/pyocd"
export FW_PROBE_RS_EXE="/opt/probe-rs/bin/probe-rs"
export FW_OPENOCD_EXE="/opt/openocd/V0.12/bin/openocd"
```

未设置时 fallback 到命令名：

```text
JLinkExe
pyocd
probe-rs
openocd
```

不要为了烧录工具覆盖 NCS 的全局 `PATH`。使用绝对路径可以避免 NCS 自带旧版本和系统版本互相覆盖。

## Release 配置

推荐文件名：

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

`prj_release.conf` 和 `app_release.overlay` 存在时，release 构建自动使用；不存在时使用基础配置和项目 profile CMake 参数。

## 文档

- [配置说明](docs/configuration.md)
- [根目录 app 示例](examples/envsetup-root-app.sh)
- [app 子目录示例](examples/envsetup-app-subdir.sh)

## 验证

本仓库脚本可以使用 fake `west` 和 fake flash tools 做无硬件 smoke test。

至少运行：

```bash
bash -n lib/zephyr-env.sh
bash -n examples/envsetup-root-app.sh
bash -n examples/envsetup-app-subdir.sh
```

完整 smoke test：

```bash
tests/smoke.sh
```

测试使用 fake `west`、J-Link、pyOCD、probe-rs 和 OpenOCD，不需要连接硬件。

