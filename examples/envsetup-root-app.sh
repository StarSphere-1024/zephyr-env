#!/usr/bin/env bash
# Copy to a Zephyr application's repository root as envsetup.sh.

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
# Optional: use a pinned executable instead of PATH.
# export FW_JLINK_EXE="/opt/jlink/V9.46/JLinkExe"
export FW_DEVTOOLS_ROOT="${PROJECT_ROOT}/tools/zephyr-env"
source "${FW_DEVTOOLS_ROOT}/lib/zephyr-env.sh"
