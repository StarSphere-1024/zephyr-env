#!/usr/bin/env bash
# Copy to a Zephyr app subdirectory as envsetup.sh.
# Adjust WORKSPACE_ROOT when the app is nested deeper than apps/<name>.

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${APP_ROOT}/../.." && pwd)"

export FW_SOURCE_DIR="${APP_ROOT}"
export FW_BUILD_ROOT="${FW_SOURCE_DIR}/build"
export FW_BOARD="your_board"
export FW_BOARD_ROOT="${WORKSPACE_ROOT}/modules/your_bsp"
export FW_BASE_CONF_FILE="${FW_SOURCE_DIR}/prj.conf"
export FW_BASE_DTC_OVERLAY_FILE="${FW_SOURCE_DIR}/app.overlay"
export FW_RELEASE_CONF_FILE="${FW_SOURCE_DIR}/prj_release.conf"
export FW_RELEASE_DTC_OVERLAY_FILE="${FW_SOURCE_DIR}/app_release.overlay"

export FW_FLASH_BACKEND="jlink"
export FW_FLASH_DEVICE="your_device"
export FW_FLASH_INTERFACE="SWD"
export FW_FLASH_SPEED="4000"

export FW_DEVTOOLS_ROOT="${WORKSPACE_ROOT}/tools/zephyr-env"
source "${FW_DEVTOOLS_ROOT}/lib/zephyr-env.sh"
