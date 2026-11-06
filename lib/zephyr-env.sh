#!/usr/bin/env bash

_fw_windows_shell() {
	case "${FW_NATIVE_PATH_MODE:-auto}:${MSYSTEM:-}:${OSTYPE:-}" in
	1:*|auto:MSYS*:*|auto:MINGW*:*|auto:*:msys*|auto:*:cygwin*)
		return 0
		;;
	esac
	return 1
}

_fw_native_path() {
	case "${1:-}" in
	/*|./*|../*|[A-Za-z]:/*)
		if _fw_windows_shell && command -v cygpath >/dev/null 2>&1; then
			cygpath -w -- "$1"
		else
			printf '%s\n' "$1"
		fi
		;;
	*)
		printf '%s\n' "${1:-}"
		;;
	esac
}

_fw_apply_profile() {
	local profile="${1:-debug}" model="${2:-${FW_DEFAULT_MODEL:-}}"
	case "${profile}" in
	debug) FW_BUILD_DIR="${FW_BUILD_ROOT}" ;;
	release) FW_BUILD_DIR="${FW_BUILD_ROOT}_release" ;;
	*) echo "Unknown build profile: ${profile} (use debug or release)." >&2; return 2 ;;
	esac
	FW_PROFILE="${profile}"
	FW_MODEL="${model}"
	FW_MODEL_CONF_FILES=()
	FW_MODEL_OVERLAY_FILES=()
	if [ -n "${model}" ]; then
		if [[ ! "${model}" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
			echo "Invalid model name: ${model}." >&2
			return 2
		fi
		if [ -n "${FW_DEBUG_BUILD_DIR:-}" ] || [ -n "${FW_RELEASE_BUILD_DIR:-}" ]; then
			echo "Model selection cannot be combined with FW_DEBUG_BUILD_DIR or FW_RELEASE_BUILD_DIR." >&2
			return 2
		fi
		if ! declare -F fw_project_model >/dev/null 2>&1; then
			echo "This project does not support model selection." >&2
			return 2
		fi
		fw_project_model "${model}" || return
		FW_BUILD_DIR="${FW_BUILD_ROOT}_${model}"
		[ "${profile}" = release ] && FW_BUILD_DIR+="_release"
	else
		if [ "${profile}" = debug ]; then
			FW_BUILD_DIR="${FW_DEBUG_BUILD_DIR:-${FW_BUILD_ROOT}}"
		else
			FW_BUILD_DIR="${FW_RELEASE_BUILD_DIR:-${FW_BUILD_ROOT}_release}"
		fi
	fi
	FW_CONF_FILES=("${FW_BASE_CONF_FILE:-${FW_SOURCE_DIR}/prj.conf}")
	FW_OVERLAY_FILES=("${FW_BASE_DTC_OVERLAY_FILE:-${FW_SOURCE_DIR}/app.overlay}")
	FW_EXTRA_CONF_FILES=()
	FW_EXTRA_OVERLAY_FILES=()
	if [ "${profile}" = release ]; then
		local release_conf="${FW_RELEASE_CONF_FILE:-${FW_SOURCE_DIR}/prj_release.conf}"
		local release_overlay="${FW_RELEASE_DTC_OVERLAY_FILE:-${FW_SOURCE_DIR}/app_release.overlay}"
		[ ! -f "${release_conf}" ] || FW_EXTRA_CONF_FILES+=("${release_conf}")
		[ ! -f "${release_overlay}" ] || FW_EXTRA_OVERLAY_FILES+=("${release_overlay}")
	fi
	FW_CONF_FILES+=("${FW_EXTRA_CONF_FILES[@]}" "${FW_MODEL_CONF_FILES[@]}")
	FW_OVERLAY_FILES+=("${FW_EXTRA_OVERLAY_FILES[@]}" "${FW_MODEL_OVERLAY_FILES[@]}")
	FW_CONF_FILE="${FW_CONF_FILES[0]}"
	FW_DTC_OVERLAY_FILE="${FW_OVERLAY_FILES[0]}"
	FW_EXTRA_CONF_FILE=""
	FW_EXTRA_DTC_OVERLAY_FILE=""
	[ "${#FW_CONF_FILES[@]}" -le 1 ] || FW_EXTRA_CONF_FILE="$(IFS=';'; printf '%s' "${FW_CONF_FILES[*]:1}")"
	[ "${#FW_OVERLAY_FILES[@]}" -le 1 ] || FW_EXTRA_DTC_OVERLAY_FILE="$(IFS=';'; printf '%s' "${FW_OVERLAY_FILES[*]:1}")"
	FW_PROFILE="${profile}"
	FW_CMAKE_ARGS=("${FW_COMMON_CMAKE_ARGS[@]}")
	if declare -F fw_project_profile >/dev/null 2>&1; then
		fw_project_profile "${profile}" || return
	fi
	export FW_PROFILE FW_MODEL FW_BUILD_DIR FW_CONF_FILE FW_DTC_OVERLAY_FILE
	export FW_EXTRA_CONF_FILE FW_EXTRA_DTC_OVERLAY_FILE BUILD_DIR
	BUILD_DIR="${FW_BUILD_DIR}"
}

_fw_validate_profile() {
	[ -d "${FW_SOURCE_DIR}" ] || { echo "Source directory not found: ${FW_SOURCE_DIR}" >&2; return 1; }
	local file
	for file in "${FW_CONF_FILES[@]}" "${FW_OVERLAY_FILES[@]}"; do
		[ -f "${file}" ] || { echo "Configuration file not found: ${file}" >&2; return 1; }
	done
}

_fw_config_inputs() {
	printf '%s\0' "PROFILE=${FW_PROFILE}" "MODEL=${FW_MODEL:-}" "SOURCE_DIR=${FW_SOURCE_DIR}" \
		"BUILD_DIR=${FW_BUILD_DIR}" "BOARD=${FW_BOARD}" "BOARD_ROOT=${FW_BOARD_ROOT:-}" \
		"CONF_FILES=${FW_CONF_FILES[*]}" "OVERLAY_FILES=${FW_OVERLAY_FILES[*]}" \
		"NCS_BASE=${NCS_BASE}" "ZEPHYR_SDK_INSTALL_DIR=${ZEPHYR_SDK_INSTALL_DIR}" \
		"EXTRA_ZEPHYR_MODULES=${EXTRA_ZEPHYR_MODULES:-}" "CMAKE_ARGS=${FW_CMAKE_ARGS[*]}" \
		"EXTRA_ARGS=${FW_WEST_EXTRA_ARGS[*]}"
	local file
	for file in "${FW_CONF_FILES[@]}" "${FW_OVERLAY_FILES[@]}" \
		"${FW_SOURCE_DIR}/sysbuild.conf" "${FW_SOURCE_DIR}/sysbuild_${FW_PROFILE}.conf" "${FW_SOURCE_DIR}/sysbuild.cmake" \
		"${FW_SOURCE_DIR}/sysbuild/mcuboot.conf" "${FW_SOURCE_DIR}/sysbuild/mcuboot_${FW_PROFILE}.conf" \
		"${FW_SOURCE_DIR}/sysbuild/mcuboot.overlay" "${FW_SOURCE_DIR}/sysbuild/mcuboot_${FW_PROFILE}.overlay" \
		"${FW_EXTRA_CONFIG_FILES[@]}"; do
		[ -n "${file}" ] && [ -f "${file}" ] && printf 'FILE_HASH=%s:%s\0' "${file}" "$(sha256sum "${file}")"
	done
}


wbuild() {
	local profile=debug verbose=0 pristine=auto parsing=1 arg model="" model_seen=0
	local -a args=()
	while [ "$#" -gt 0 ]; do
		arg="$1"; shift
		if [ "${parsing}" -eq 0 ]; then args+=("${arg}"); continue; fi
		case "${arg}" in
		--) parsing=0 ;;
		-r|--release) profile=release ;;
		-v|--verbose) verbose=1 ;;
		-p|--pristine) pristine=always ;;
		--pristine=always|--pristine=auto|--pristine=never) pristine="${arg#*=}" ;;
		--pristine=*) echo "Invalid --pristine value: ${arg#*=}." >&2; return 2 ;;
		-m)
			[ "${model_seen}" -eq 0 ] && [ "$#" -gt 0 ] && [ -n "$1" ] && [[ "$1" != -* ]] || { echo "Option -m requires one model." >&2; return 2; }
			model="$1"; model_seen=1; shift ;;
		*) args+=("${arg}") ;;
		esac
	done
	_fw_apply_profile "${profile}" "${model}" || return
	_fw_validate_profile || return
	FW_WEST_EXTRA_ARGS=("${args[@]}")
	local -a cmake_args=("-DCONF_FILE=${FW_CONF_FILE}" "-DDTC_OVERLAY_FILE=${FW_DTC_OVERLAY_FILE}" "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON")
	[ -n "${FW_EXTRA_CONF_FILE}" ] && cmake_args+=("-DEXTRA_CONF_FILE=${FW_EXTRA_CONF_FILE}")
	[ -n "${FW_EXTRA_DTC_OVERLAY_FILE}" ] && cmake_args+=("-DEXTRA_DTC_OVERLAY_FILE=${FW_EXTRA_DTC_OVERLAY_FILE}")
	[ -n "${FW_BOARD_ROOT:-}" ] && cmake_args+=("-DBOARD_ROOT=${FW_BOARD_ROOT}")
	cmake_args+=("${FW_CMAKE_ARGS[@]}" "${args[@]}")
	local key stamp="${FW_BUILD_DIR}/.wbuild-config" stored="" needs=0 rc
	key=$(_fw_config_inputs | sha256sum); key="${key%% *}"
	[ -f "${stamp}" ] && IFS= read -r stored < "${stamp}"
	[ "${pristine}" = always ] || [ ! -f "${FW_BUILD_DIR}/CMakeCache.txt" ] || [ "${stored}" != "${key}" ] && needs=1
	local -a west_args=(--build-dir "${FW_BUILD_DIR}" "${FW_SOURCE_DIR}" "--pristine=${pristine}" --board "${FW_BOARD}")
	[ "${needs}" -eq 1 ] && west_args+=(-- "${cmake_args[@]}")
	if [ "${verbose}" -eq 1 ]; then
		env -u CONF_FILE -u DTC_OVERLAY_FILE -u EXTRA_CONF_FILE -u EXTRA_DTC_OVERLAY_FILE west build "${west_args[@]}"; rc=$?
	else
		local tmp; tmp=$(mktemp)
		env -u CONF_FILE -u DTC_OVERLAY_FILE -u EXTRA_CONF_FILE -u EXTRA_DTC_OVERLAY_FILE west build "${west_args[@]}" >"${tmp}" 2>&1; rc=$?
		if [ "${rc}" -eq 0 ]; then rm -f "${tmp}"; echo "Build OK [${FW_PROFILE}]"; else mkdir -p "${FW_BUILD_DIR}"; mv "${tmp}" "${FW_BUILD_DIR}/build.log"; echo "Build FAILED [${FW_PROFILE}] (exit ${rc}) - log: ${FW_BUILD_DIR}/build.log"; fi
	fi
	if [ "${rc}" -eq 0 ]; then mkdir -p "${FW_BUILD_DIR}" || return 1; printf '%s\n' "${key}" >"${stamp}" || return 1; fi
	return "${rc}"
}

_fw_flash_error_regex='Error[[:space:]]+occurred:|Failed[[:space:]]+to[[:space:]]+attach|Could[[:space:]]+not[[:space:]]+connect|Cannot[[:space:]]+connect|Failed[[:space:]]+to[[:space:]]+(load|program)|Programming[[:space:]]+failed|Verification[[:space:]]+failed|Verify[[:space:]]+failed|ERROR:'

wflash() {
	local profile=debug backend="${FW_FLASH_BACKEND:-jlink}" verbose=0 hex_file="" model="" model_seen=0 arg
	while [ "$#" -gt 0 ]; do
		arg="$1"; shift
		case "${arg}" in
		-r|--release) profile=release ;;
		-v|--verbose) verbose=1 ;;
		-b|--backend) [ "$#" -gt 0 ] && [ -n "$1" ] || { echo "Option ${arg} requires a backend." >&2; return 2; }; backend="$1"; shift ;;
		-p) [ "$#" -gt 0 ] && [ -n "$1" ] || { echo "Option -p requires a hex file." >&2; return 2; }; hex_file="$1"; shift ;;
		-m)
			[ "${model_seen}" -eq 0 ] && [ "$#" -gt 0 ] && [ -n "$1" ] && [[ "$1" != -* ]] || { echo "Option -m requires one model." >&2; return 2; }
			model="$1"; model_seen=1; shift ;;
		*) echo "Usage: wflash [-m model] [-r|--release] [-v] [-b|--backend backend] [-p hex_file]" >&2; return 2 ;;
		esac
	done
	case "${backend}" in jlink|pyocd|probe-rs|openocd) ;; *) echo "Unsupported flash backend: ${backend}." >&2; return 2 ;; esac
	_fw_apply_profile "${profile}" "${model}" || return
	if [ -z "${hex_file}" ]; then
		local candidate
		local -a candidates=("${FW_BUILD_DIR}/merged.hex" "${FW_BUILD_DIR}"/merged_*.hex)
		if [ -z "${FW_MODEL}" ]; then
			candidates+=("${FW_BUILD_DIR}"/../merged_*.hex "${FW_BUILD_ROOT:-${FW_BUILD_DIR}}"/merged_*.hex)
		fi
		for candidate in "${candidates[@]}"; do
			if [ -f "${candidate}" ]; then hex_file="${candidate}"; break; fi
		done
	fi
	if [ -z "${hex_file}" ] && [ "${FW_ALLOW_APP_ONLY_FLASH:-0}" = 1 ]; then
		local candidate
		for candidate in "${FW_BUILD_DIR}/${FW_APP_NAME:-}/zephyr/zephyr.hex" "${FW_BUILD_DIR}/zephyr/zephyr.hex"; do
			if [ -f "${candidate}" ]; then hex_file="${candidate}"; break; fi
		done
	fi
	echo "Flash image: ${hex_file}"
	[ -n "${hex_file}" ] && [ -f "${hex_file}" ] || {
		echo "Merged HEX not found; run wbuild --pristine first." >&2
		return 1
	}
	local device="${FW_FLASH_DEVICE:-NRF54L15_M33}" interface="${FW_FLASH_INTERFACE:-SWD}" speed="${FW_FLASH_SPEED:-4000}" program_command
	local -a command=()
	case "${backend}" in
	jlink) command=("$(_fw_native_path "${FW_JLINK_EXE:-JLinkExe}")" -device "${device}" -if "${interface}" -speed "${speed}") ;;
	pyocd) command=("$(_fw_native_path "${FW_PYOCD_EXE:-pyocd}")" flash --target "${FW_PYOCD_TARGET:-${device}}" --frequency "${FW_PYOCD_FREQUENCY:-${speed}}"); [ -n "${FW_PYOCD_UID:-}" ] && command+=(-u "${FW_PYOCD_UID}"); command+=("$(_fw_native_path "${hex_file}")") ;;
	probe-rs) command=("$(_fw_native_path "${FW_PROBE_RS_EXE:-probe-rs}")" download --chip "${FW_PROBE_RS_CHIP:-${device}}" "$(_fw_native_path "${hex_file}")") ;;
	openocd) command=("$(_fw_native_path "${FW_OPENOCD_EXE:-openocd}")"); [ -n "${FW_OPENOCD_INTERFACE_CFG:-}" ] && command+=(-f "$(_fw_native_path "${FW_OPENOCD_INTERFACE_CFG}")"); [ -n "${FW_OPENOCD_TARGET_CFG:-}" ] && command+=(-f "$(_fw_native_path "${FW_OPENOCD_TARGET_CFG}")"); command+=("${FW_OPENOCD_ARGS[@]}"); printf -v program_command 'program "%s" verify reset exit' "$(_fw_native_path "${hex_file}")"; command+=(-c "${program_command}") ;;
	esac
	local tmp rc; tmp=$(mktemp)
	if [ "${backend}" = jlink ]; then
		if [ "${verbose}" -eq 1 ]; then "${command[@]}" <<EOF 2>&1 | tee "${tmp}"
connect
r
h
loadfile "${hex_file}"
r
g
exit
EOF
			rc=${PIPESTATUS[0]}; else "${command[@]}" <<EOF >"${tmp}" 2>&1
connect
r
h
loadfile "${hex_file}"
r
g
exit
EOF
			rc=$?; fi
	elif [ "${verbose}" -eq 1 ]; then "${command[@]}" 2>&1 | tee "${tmp}"; rc=${PIPESTATUS[0]}
	else "${command[@]}" >"${tmp}" 2>&1; rc=$?; fi
	local output; output=$(<"${tmp}")
	if [ "${rc}" -eq 0 ] && [[ ! "${output}" =~ ${_fw_flash_error_regex} ]]; then rm -f "${tmp}"; echo "Flash OK [${profile}/${backend}]"; return 0; fi
	mkdir -p "${FW_BUILD_DIR}"; mv "${tmp}" "${FW_BUILD_DIR}/flash.log"; echo "Flash FAILED [${profile}/${backend}] (exit ${rc}) - log: ${FW_BUILD_DIR}/flash.log" >&2; [ "${rc}" -eq 0 ] && rc=1; return "${rc}"
}

wconfig() {
	local profile=debug model="" model_seen=0 arg
	while [ "$#" -gt 0 ]; do
		arg="$1"; shift
		case "${arg}" in
		-r|--release) profile=release ;;
		-m)
			[ "${model_seen}" -eq 0 ] && [ "$#" -gt 0 ] && [ -n "$1" ] && [[ "$1" != -* ]] || { echo "Option -m requires one model." >&2; return 2; }
			model="$1"; model_seen=1; shift ;;
		*) echo "Usage: wconfig [-m model] [-r|--release]" >&2; return 2 ;;
		esac
	done
	_fw_apply_profile "${profile}" "${model}" || return
	_fw_validate_profile || return
	printf '%s\n' "SOURCE_DIR: ${FW_SOURCE_DIR}" "BUILD_DIR: ${FW_BUILD_DIR}" "PROFILE: ${FW_PROFILE}" "MODEL: ${FW_MODEL:-<unset>}" "BOARD: ${FW_BOARD}" "BOARD_ROOT: ${FW_BOARD_ROOT:-<unset>}" "CONF_FILES: ${FW_CONF_FILES[*]}" "OVERLAY_FILES: ${FW_OVERLAY_FILES[*]}" "EXTRA_CONF: ${FW_EXTRA_CONF_FILE:-<unset>}" "FLASH_BACKEND: ${FW_FLASH_BACKEND:-pyocd}" "DEVTOOLS_ROOT: ${FW_DEVTOOLS_ROOT}" "JLINK_EXE: ${FW_JLINK_EXE:-JLinkExe}" "PYOCD_EXE: ${FW_PYOCD_EXE:-pyocd}" "PROBE_RS_EXE: ${FW_PROBE_RS_EXE:-probe-rs}" "OPENOCD_EXE: ${FW_OPENOCD_EXE:-openocd}"
}


# 优先使用系统 Git；NCS Git 缺少 git-submodule 等辅助程序
if [ -x /usr/bin/git ]; then
   git() {
      /usr/bin/git "$@"
   }
fi
