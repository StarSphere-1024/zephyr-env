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

APP_DIR="${TMP_DIR}/app dir"
FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${APP_DIR}" "${FAKE_BIN}"
printf '%s\n' '# test config' >"${APP_DIR}/prj.conf"
printf '%s\n' '/ { };' >"${APP_DIR}/app.overlay"
printf '%s\n' '# release' >"${APP_DIR}/prj_release.conf"
printf '%s\n' '/ { };' >"${APP_DIR}/app_release.overlay"
printf '%s\n' '# model b' >"${APP_DIR}/prj_b.conf"
printf '%s\n' '/ { };' >"${APP_DIR}/app_b.overlay"
printf 'hex\n' >"${APP_DIR}/image.hex"

cat >"${FAKE_BIN}/tool" <<'EOF'
#!/usr/bin/env bash
case "$(basename "$0")" in
west)
	printf 'west-arg=<%s>\n' "$@" >>"${FAKE_LOG}"
	build_dir=""
	while [ "$#" -gt 0 ]; do
		[ "$1" = --build-dir ] && { shift; build_dir="${1:-}"; break; }
		shift
	done
	[ -z "${build_dir}" ] || { mkdir -p "${build_dir}"; : >"${build_dir}/CMakeCache.txt"; }
	;;
*)
	printf '%s %s\n' "$(basename "$0")" "$*" >>"${FAKE_LOG}"
	if [ "$(basename "$0")" = JLinkExe ]; then
		printf '%s\n' 'Target connection not established yet but required for command.'
	fi
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
export MSYSTEM=""
export OSTYPE="linux-gnu"
export FAKE_LOG="${TMP_DIR}/commands.log"
export PATH="${FAKE_BIN}:${PATH}"
export FW_SOURCE_DIR="${APP_DIR}"
export FW_DEVTOOLS_ROOT="${ROOT_DIR}"
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

fw_project_model() {
	case "$1" in
	a) ;;
	b) FW_MODEL_CONF_FILES=("${FW_SOURCE_DIR}/prj_b.conf"); FW_MODEL_OVERLAY_FILES=("${FW_SOURCE_DIR}/app_b.overlay") ;;
	*) echo "unknown test model: $1" >&2; return 2 ;;
	esac
}

wbuild -m b -- --sentinel "space value" || fail 'model build failed'
assert_file "${APP_DIR}/build_b/.wbuild-config"
grep -Fq -- '-DEXTRA_CONF_FILE=' "${FAKE_LOG}" || fail 'model config was not passed'
grep -Fq -- "--sentinel" "${FAKE_LOG}" || fail '-- arguments were not preserved'
grep -Fq -- "west-arg=<space value>" "${FAKE_LOG}" || fail 'spaced -- argument was not preserved'
wbuild -m b || fail 'model fingerprint baseline failed'
key_before="$(<"${APP_DIR}/build_b/.wbuild-config")"
printf '%s\n' '# changed' >>"${APP_DIR}/prj_b.conf"
wbuild -m b || fail 'changed model config build failed'
key_after="$(<"${APP_DIR}/build_b/.wbuild-config")"
[ "${key_before}" != "${key_after}" ] || fail 'model config change did not change fingerprint'
wbuild -r -m b || fail 'model release build failed'
grep -Eq 'prj_release.conf;.*prj_b.conf' "${FAKE_LOG}" || fail 'release/model config order is wrong'
cfg="$(wconfig -m b -r)" || fail 'model config display failed'
[[ "${cfg}" == *"MODEL: b"* && "${cfg}" == *"prj_release.conf"* && "${cfg}" == *"prj_b.conf"* ]] || fail 'wconfig omitted model config'
assert_file "${APP_DIR}/build_b_release/.wbuild-config"
wbuild -m a || fail 'model a build failed'
assert_file "${APP_DIR}/build_a/.wbuild-config"
wbuild || fail 'default build after model failed'
[ "${FW_MODEL}" = "" ] || fail 'model selection stuck in shell'
FW_DEFAULT_MODEL=a
wconfig -m b >/dev/null || fail 'explicit model with default failed'
wbuild || fail 'default model build failed'
[ "${FW_MODEL}" = a ] && [ "${FW_BUILD_DIR}" = "${APP_DIR}/build_a" ] || fail 'explicit model replaced project default'
unset FW_DEFAULT_MODEL
mv "${APP_DIR}/prj_b.conf" "${APP_DIR}/prj_b.saved"
if wconfig -m b >/dev/null 2>&1; then fail 'missing model config accepted'; fi
mv "${APP_DIR}/prj_b.saved" "${APP_DIR}/prj_b.conf"

if wbuild -m >/dev/null 2>&1; then fail 'missing model value accepted'; fi
if wbuild -m a -m b >/dev/null 2>&1; then fail 'duplicate model accepted'; fi
if wbuild -m unknown >/dev/null 2>&1; then fail 'unknown model accepted'; fi
printf 'hex b\n' >"${APP_DIR}/build_b/merged.hex"
printf 'wrong parent hex\n' >"${APP_DIR}/build/merged.hex"
wflash -m b -b pyocd >/dev/null || fail 'selected model flash failed'
grep -Fq -- "${APP_DIR}/build_b/merged.hex" "${FAKE_LOG}" || fail 'selected model HEX not used'
rm -f "${APP_DIR}/build_b/merged.hex"
if wflash -m b -b pyocd >/dev/null 2>&1; then fail 'missing model HEX fell back to parent'; fi
wflash -m b -b pyocd -p "${APP_DIR}/image.hex" >"${TMP_DIR}/flash-path.log" || fail 'explicit model HEX failed'
grep -Fq -- "${APP_DIR}/image.hex" "${TMP_DIR}/flash-path.log" || fail 'explicit HEX path not displayed'
wflash -b pyocd >/dev/null || fail 'legacy parent HEX fallback failed'

if wconfig -m >/dev/null 2>&1; then fail 'wconfig accepted missing model'; fi
if wconfig -m unknown >/dev/null 2>&1; then fail 'wconfig accepted unknown model'; fi
if wconfig -m a -m b >/dev/null 2>&1; then fail 'wconfig accepted duplicate model'; fi
if wflash -m >/dev/null 2>&1; then fail 'wflash accepted missing model'; fi
if wflash -m unknown -p "${APP_DIR}/image.hex" >/dev/null 2>&1; then fail 'wflash accepted unknown model'; fi
if wflash -m a -m b -p "${APP_DIR}/image.hex" >/dev/null 2>&1; then fail 'wflash accepted duplicate model'; fi
export FW_DEBUG_BUILD_DIR="${APP_DIR}/legacy custom build"
if wbuild -m a >/dev/null 2>&1; then fail 'model accepted conflicting legacy directory override'; fi
unset FW_DEBUG_BUILD_DIR
unset -f fw_project_model
if wconfig -m a >/dev/null 2>&1; then fail 'model accepted without project hook'; fi
export FW_DEBUG_BUILD_DIR="${APP_DIR}/legacy custom build"

wbuild || fail 'legacy build-dir override failed'
assert_file "${FW_DEBUG_BUILD_DIR}/.wbuild-config"
unset FW_DEBUG_BUILD_DIR

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
