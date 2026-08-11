#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_file() {
	[ -f "$1" ] || fail "missing file: $1"
}

APP_DIR="${TMP_DIR}/app"
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${APP_DIR}" "${FAKE_BIN}"
printf '%s\n' '# test config' >"${APP_DIR}/prj.conf"
printf '%s\n' '/ { };' >"${APP_DIR}/app.overlay"
printf 'hex\n' >"${APP_DIR}/image.hex"

cat >"${FAKE_BIN}/tool" <<'EOF'
#!/usr/bin/env bash
case "$(basename "$0")" in
west)
	printf 'west %s\n' "$*" >>"${FAKE_LOG}"
	;;
*)
	printf '%s %s\n' "$(basename "$0")" "$*" >>"${FAKE_LOG}"
	if [ "${FAKE_FLASH_ERROR:-0}" = 1 ]; then
		printf '%s\n' 'Error occurred: Could not connect to the target device.'
	fi
	;;
esac
exit "${FAKE_RC:-0}"
EOF
chmod +x "${FAKE_BIN}/tool"
for name in west JLinkExe pyocd probe-rs openocd; do
	ln -s tool "${FAKE_BIN}/${name}"
done
export NCS_BASE="test-ncs"
export ZEPHYR_SDK_INSTALL_DIR="test-sdk"
export FAKE_LOG="${TMP_DIR}/commands.log"
export PATH="${FAKE_BIN}:${PATH}"
export FW_SOURCE_DIR="${APP_DIR}"
export FW_BUILD_ROOT="${APP_DIR}/build"
export FW_BOARD="test_board"
export FW_BASE_CONF_FILE="${APP_DIR}/prj.conf"
export FW_BASE_DTC_OVERLAY_FILE="${APP_DIR}/app.overlay"
export FW_FLASH_DEVICE="test_device"
export FW_FLASH_INTERFACE="SWD"
export FW_FLASH_SPEED="4000"
export FW_COMMON_CMAKE_ARGS=()
export FW_JLINK_EXE="${FAKE_BIN}/JLinkExe"
export FW_PYOCD_EXE="${FAKE_BIN}/pyocd"
export FW_PROBE_RS_EXE="${FAKE_BIN}/probe-rs"
export FW_OPENOCD_EXE="${FAKE_BIN}/openocd"

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/zephyr-env.sh"

wbuild
wbuild -r
assert_file "${APP_DIR}/build/.wbuild-config"
assert_file "${APP_DIR}/build_release/.wbuild-config"

for backend in jlink pyocd probe-rs openocd; do
	wflash --backend "${backend}" -p "${APP_DIR}/image.hex" || fail "backend failed: ${backend}"
done
wflash -r --backend pyocd -p "${APP_DIR}/image.hex" || fail "release flash failed"

FAKE_FLASH_ERROR=1 FAKE_RC=0 wflash --backend pyocd -p "${APP_DIR}/image.hex" &&
	fail "J-Link-style output error was accepted"

FAKE_FLASH_ERROR=0 FAKE_RC=9 wflash --backend openocd -p "${APP_DIR}/image.hex" &&
	fail "non-zero backend exit was accepted"

assert_file "${APP_DIR}/build/flash.log"
grep -q 'west' "${FAKE_LOG}" || fail 'west was not invoked'
grep -q 'pyocd' "${FAKE_LOG}" || fail 'pyocd was not invoked'
grep -q 'probe-rs' "${FAKE_LOG}" || fail 'probe-rs was not invoked'
grep -q 'openocd' "${FAKE_LOG}" || fail 'openocd was not invoked'

echo 'smoke: OK'
