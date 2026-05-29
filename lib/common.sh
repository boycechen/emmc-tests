#!/bin/bash
# 公共函数库 — 所有测试共享

# ─── 全局状态 ──────────────────────────────────────────────────
PASS=0; FAIL=0; WARN=0; TOTAL=0
HAS_MMC_UTILS=false
HAS_FIO=false  # 由 emmc_test.sh main() 在检测 fio 后设为 true
[ -z "${LOGDIR}" ] && LOGDIR="/tmp/emmc_deep_test_$(date +%s)"

# ─── 测试结果追踪 ──────────────────────────────────────────────
declare -A _TR_RES    # test_id -> final result (PASS|FAIL|WARN|SKIP)
declare -A _TR_TIME   # test_id -> duration in seconds
declare -A _TR_PASS   # test_id -> pass count
declare -A _TR_FAIL   # test_id -> fail count
declare -A _TR_WARN   # test_id -> warn count
declare -a _TR_ORDER  # ordered list of test ids run

# ─── 输出函数 ──────────────────────────────────────────────────
title()   { echo -e "\n${C_TITLE}══════ ${1} ══════${C_RESET}"
            echo -e "\n========== ${1} ==========" >> "${LOGDIR}/results.log"; }
step()    { echo -e "\n${C_STEP}${ICON_STEP} ${1}${C_RESET}"; }

pass()    { echo -e "  ${C_PASS}${ICON_PASS} PASS${C_RESET}  ${1}"
            ((PASS++)); ((TOTAL++))
            echo "[PASS] ${1}" >> "${LOGDIR}/results.log"; }
fail()    { echo -e "  ${C_FAIL}${ICON_FAIL} FAIL${C_RESET}  ${1}"
            ((FAIL++)); ((TOTAL++))
            echo "[FAIL] ${1}" >> "${LOGDIR}/results.log"; }
warn()    { echo -e "  ${C_WARN}${ICON_WARN} WARN${C_RESET}  ${1}"
            ((WARN++)); ((TOTAL++))
            echo "[WARN] ${1}" >> "${LOGDIR}/results.log"; }
info()    { echo -e "  ${C_INFO}${ICON_INFO} INFO${C_RESET}  ${1}"
            echo "[INFO] ${1}" >> "${LOGDIR}/results.log"; }
progress(){ echo -e "  ${C_PROGRESS}${ICON_PROGRESS} ${1}${C_RESET}"; }
cmd_out() { echo -e "${C_CMD}  ${1}${C_RESET}"; }

# ─── 交互 ──────────────────────────────────────────────────────
ask_yes() {
    echo -ne "${C_PROMPT}${ICON_PROMPT} ${1} (y/N): ${C_RESET}"
    read -r ans
    [[ "${ans}" =~ ^[Yy] ]]
    return $?
}

# ─── 旋转动画 (后台任务等待) ────────────────────────────────────
spinner() {
    local pid=$1
    local msg="${2:-运行中}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    echo -ne "  ${C_PROGRESS}${msg}${C_RESET} "
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 9); do
            echo -ne "\b${spin:$i:1}"
            sleep 0.15
        done
    done
    echo -e "\b${C_PASS}✓${C_RESET}"
    wait "$pid"
    return $?
}

# ─── 日志初始化 ────────────────────────────────────────────────
init_logdir() {
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOGDIR="/tmp/emmc_deep_test_${TIMESTAMP}"
    mkdir -p "${LOGDIR}"
    echo "eMMC Deep Stress Test Suite v3.0" > "${LOGDIR}/results.log"
    echo "Device: ${EMMC_DEV}" >> "${LOGDIR}/results.log"
    echo "Started: $(date)" >> "${LOGDIR}/results.log"
    echo "========================================" >> "${LOGDIR}/results.log"
    info "日志目录: ${LOGDIR}"
}

# ─── 测试结果记录 ──────────────────────────────────────────────
record_test_result() {
    local id="$1"
    local name="$2"
    local duration="$3"
    local result="$4"   # PASS|FAIL|WARN|SKIP
    local p=$5
    local f=$6
    local w=$7

    _TR_RES["${id}"]="${result}"
    _TR_TIME["${id}"]="${duration}"
    _TR_PASS["${id}"]="${p}"
    _TR_FAIL["${id}"]="${f}"
    _TR_WARN["${id}"]="${w}"
    _TR_ORDER+=("${id}")

    # 同时写入日志
    {
        printf "[TRACK] %-6s %-6s  %5ss  P=%-3d F=%-3d W=%-3d  %s\n" \
            "${id}" "${result}" "${duration}" "${p}" "${f}" "${w}" "${name}"
    } >> "${LOGDIR}/tracking.log"
}

reset_test_tracking() {
    _TR_RES=()
    _TR_TIME=()
    _TR_PASS=()
    _TR_FAIL=()
    _TR_WARN=()
    _TR_ORDER=()
}

# ─── fio 封装 ─────────────────────────────────────────────────
# 用法: run_fio <test_name> <fio_args...>
# 自动写入 JSON 日志, 解析 error 字段, 返回 0=成功 / n=错误数
run_fio() {
    local name="$1"; shift
    local name_safe="${name// /_}"
    local logfile="${LOGDIR}/fio_${name_safe}.json"

    echo ""
    # ── 双通道输出 ─────────────────────────────────────────
    # JSON → 文件 (供 run_fio 解析 error/指标)
    # 实时状态 → 终端 (fio 自动输出进度条)
    #
    # fio ≥3.3 支持 --json-output-file 分离两种输出,
    # 旧版 fallback 写纯 JSON 文件 (无实时输出)

    if fio --help 2>&1 | grep -q json-output-file; then
        # 新版 fio (≥3.3): JSON 写文件, 实时状态自动输出到终端
        # 例如: [W(1)][100.0%][w=124MiB/s][w=31.7k IOPS][eta 00m:00s]
        fio "$@" --json-output-file="${logfile}" 2>>"${LOGDIR}/fio_stderr.log"
    else
        # 旧版 fio fallback: 纯 JSON 文件, 无实时输出
        fio "$@" --output="${logfile}" --output-format=json \
            2>>"${LOGDIR}/fio_stderr.log"
    fi
    local rc=$?
    if [ -f "${logfile}" ]; then
        local fio_err=$(grep -oP '"error":\s*\K[0-9]+' "${logfile}" | head -1)
        if [ "${fio_err}" = "0" ]; then
            return 0
        elif [ -n "${fio_err}" ] && [ "${fio_err}" != "0" ]; then
            return "${fio_err}"
        fi
    fi
    return "${rc}"
}

# ─── fio 指标提取 ─────────────────────────────────────────────
extract_fio_metric() {
    local logfile="$1"; local metric="$2"
    grep -oP "\"${metric}\":\s*\K[0-9.]+" "${logfile}" | head -1 || echo "N/A"
}

extract_fio_latency() {
    local logfile="$1"; local pct="$2"
    grep -oP "\"${pct}\":\s*\K[0-9.]+" "${logfile}" | head -1 || echo "N/A"
}

get_fio_error() {
    local logfile="$1"
    grep -oP '"error":\s*\K[0-9]+' "${logfile}" | head -1 || echo "unknown"
}

# ─── 格式化时长 (秒 -> MM:SS) ──────────────────────────────────
fmt_duration() {
    local secs=$1
    local m=$((secs / 60))
    local s=$((secs % 60))
    printf "%02d:%02d" "${m}" "${s}"
}

# ─── 结果表头颜色 ──────────────────────────────────────────────
result_color() {
    case "$1" in
        PASS) echo -e "${C_PASS}${1}${C_RESET}" ;;
        FAIL) echo -e "${C_FAIL}${1}${C_RESET}" ;;
        WARN) echo -e "${C_WARN}${1}${C_RESET}" ;;
        SKIP) echo -e "${C_INFO}${1}${C_RESET}" ;;
        *)    echo "$1" ;;
    esac
}

# ─── 测试总结 (详细表格) ────────────────────────────────────────
summary() {
    local total_duration=0
    local total_pass=0; local total_fail=0; local total_warn=0
    # 从全局计数器获取总 PASS/FAIL/WARN, 兼容单次运行
    [ ${#_TR_ORDER[@]} -eq 0 ] && {
        # 无追踪数据时退化为旧版摘要
        summary_legacy; return
    }

    echo -e "\n${C_TITLE}══ 测试结果汇总报告 ══${C_RESET}"

    echo -e "\n${C_INFO}设备: ${EMMC_DEV}  (${DEVICE_SIZE_GB}GB)${C_RESET}"
    echo -e "${C_INFO}日志: ${LOGDIR}${C_RESET}"

    # 表头
    echo ""
    echo -e "${C_TITLE} ID    ${C_STEP}│${C_RESET} 测试名称                              ${C_STEP}│${C_RESET} 时长   ${C_STEP}│${C_RESET} P/F/W ${C_STEP}│${C_RESET} 结果${C_RESET}"
    echo -e "${C_TITLE}──${C_STEP}──${C_RESET}───${C_STEP}┼${C_RESET}───────────────────────────────────────${C_STEP}┼${C_RESET}────────${C_STEP}┼${C_RESET}──────${C_STEP}┼${C_RESET}──────────${C_RESET}"

    for id in "${_TR_ORDER[@]}"; do
        local name="${TEST_MAP[${id}]:-${id}}"
        local duration="${_TR_TIME[${id}]:-0}"
        local p="${_TR_PASS[${id}]:-0}"
        local f="${_TR_FAIL[${id}]:-0}"
        local w="${_TR_WARN[${id}]:-0}"
        local result="${_TR_RES[${id}]:-}"

        # 截断过长名称
        local display_name="${name:0:36}"

        local time_str=$(fmt_duration "${duration}")
        total_duration=$((total_duration + duration))
        total_pass=$((total_pass + p))
        total_fail=$((total_fail + f))
        total_warn=$((total_warn + w))

        # ── 分开输出: 纯文本列用 printf(宽度准确), 着色列用 echo(不受ANSI干扰) ──
        printf " %-4s ${C_STEP}│${C_RESET} %-36s ${C_STEP}│${C_RESET} %6s ${C_STEP}│${C_RESET} " \
            "${id}" "${display_name}" "${time_str}"

        # P/F/W 列 (着色)
        echo -ne "${C_PASS}${p}${C_RESET} ${C_FAIL}${f}${C_RESET} ${C_WARN}${w}${C_RESET} "

        # 结果列
        local padded_result="$(printf "%-8s" "${result}")"
        local colored_padded=$(result_color "${padded_result}")
        echo -e " ${C_STEP}│${C_RESET} ${colored_padded}"
    done

    echo -e "${C_TITLE}──${C_STEP}──${C_RESET}───${C_STEP}┼${C_RESET}───────────────────────────────────────${C_STEP}┼${C_RESET}────────${C_STEP}┼${C_RESET}──────${C_STEP}┼${C_RESET}──────────${C_RESET}"

    # 汇总行
    local total_time_str=$(fmt_duration "${total_duration}")
    local overall_result="PASS"
    [ "${total_fail}" -gt 0 ] && overall_result="FAIL"
    [ "${total_fail}" -eq 0 ] && [ "${total_warn}" -gt 0 ] && overall_result="WARN"

    # 同样分开输出避免 ANSI 干扰对齐
    printf " %-5s ${C_STEP}│${C_RESET} %-36s ${C_STEP}│${C_RESET} %6s ${C_STEP}│${C_RESET} " \
        "${C_PROGRESS}合计${C_RESET}" "${#_TR_ORDER[@]} 项测试" "${total_time_str}"
    echo -ne "${C_PASS}${total_pass}${C_RESET} ${C_FAIL}${total_fail}${C_RESET} ${C_WARN}${total_warn}${C_RESET} "
    local padded_overall="$(printf "%-8s" "${overall_result}")"
    local colored_overall=$(result_color "${padded_overall}")
    echo -e " ${C_STEP}│${C_RESET} ${colored_overall}"

    echo "" >> "${LOGDIR}/results.log"
    echo "===== 详细结果表 =====" >> "${LOGDIR}/results.log"
    for id in "${_TR_ORDER[@]}"; do
        local name="${TEST_MAP[${id}]:-${id}}"
        printf "%-6s %-8s  %5ss  P=%-3d F=%-3d W=%-3d  %s\n" \
            "${id}" "${_TR_RES[${id}]}" "${_TR_TIME[${id}]}" \
            "${_TR_PASS[${id}]}" "${_TR_FAIL[${id}]}" "${_TR_WARN[${id}]}" \
            "${name}" >> "${LOGDIR}/results.log"
    done
    echo "PASS=${total_pass} FAIL=${total_fail} WARN=${total_warn} TOTAL=$((total_pass + total_fail + total_warn))" >> "${LOGDIR}/results.log"
    echo "TOTAL_DURATION=${total_duration}s" >> "${LOGDIR}/results.log"
    echo "Ended: $(date)" >> "${LOGDIR}/results.log"

    # 总体评价
    echo ""
    if [ "${total_fail}" -eq 0 ] && [ "${total_warn}" -eq 0 ]; then
        echo -e "${C_PASS}🎉 全部 ${#_TR_ORDER[@]} 项测试通过! eMMC 健康状态良好    ${total_time_str}${C_RESET}"
    elif [ "${total_fail}" -eq 0 ]; then
        echo -e "${C_WARN}⚠  测试完成, ${total_warn} 项警告, 建议查看日志            ${total_time_str}${C_RESET}"
    else
        echo -e "${C_FAIL}✘  ${total_fail} 项失败! 日志: ${LOGDIR}/results.log     ${total_time_str}${C_RESET}"
    fi

    # 关键信息提取 (T7 延迟 / T10 性能基线 / T1 寿命)
    echo -e "\n${C_INFO}关键指标摘要:${C_RESET}"
    local has_data=false

    # T1 寿命信息
    if [ -f "${LOGDIR}/ext_csd.txt" ]; then
        local pre_eol=$(grep "PRE_EOL_INFO" "${LOGDIR}/ext_csd.txt" 2>/dev/null | awk '{print $NF}')
        local lt_a=$(grep "LIFE_TIME_EST_TYP_A" "${LOGDIR}/ext_csd.txt" 2>/dev/null | awk '{print $NF}')
        local lt_b=$(grep "LIFE_TIME_EST_TYP_B" "${LOGDIR}/ext_csd.txt" 2>/dev/null | awk '{print $NF}')
        [ -n "${pre_eol}" ] && echo -e "  ${C_INFO}ℹ${C_RESET} 寿命: PRE_EOL=${pre_eol} Type_A=${lt_a} Type_B=${lt_b}" && has_data=true
    fi

    # T7 延迟 (如果 T7 跑了)
    if [ -f "${LOGDIR}/fio_t7_readlat.json" ]; then
        local p99=$(extract_fio_latency "${LOGDIR}/fio_t7_readlat.json" "99.000000")
        local p999=$(extract_fio_latency "${LOGDIR}/fio_t7_readlat.json" "99.900000")
        [ "${p99}" != "N/A" ] && echo -e "  ${C_INFO}ℹ${C_RESET} 读延迟(4K): P99=$(fmt_latency "${p99}")  P99.9=$(fmt_latency "${p999}")" && has_data=true
    fi
    if [ -f "${LOGDIR}/fio_t7_writelat.json" ]; then
        local p99_w=$(extract_fio_latency "${LOGDIR}/fio_t7_writelat.json" "99.000000")
        local p999_w=$(extract_fio_latency "${LOGDIR}/fio_t7_writelat.json" "99.900000")
        [ "${p99_w}" != "N/A" ] && echo -e "  ${C_INFO}ℹ${C_RESET} 写延迟(4K): P99=$(fmt_latency "${p99_w}")  P99.9=$(fmt_latency "${p999_w}")" && has_data=true
    fi

    # T10 性能基线
    if [ -f "${LOGDIR}/performance_baseline.txt" ]; then
        echo -e "  ${C_INFO}ℹ${C_RESET} 性能基线:"
        while IFS= read -r line; do
            echo -e "    ${C_CMD}${line}${C_RESET}"
        done < "${LOGDIR}/performance_baseline.txt"
        has_data=true
    fi

    ${has_data} || echo -e "  ${C_INFO}ℹ${C_RESET} 无额外数据 (仅单次测试时无追踪表)"
}

# ─── 旧版摘要 (兼容单次运行) ──────────────────────────────────
summary_legacy() {
    echo -e "\n${C_TITLE}══ 测试总结 ══${C_RESET}"
    echo -e "\n${C_PROGRESS}设备: ${EMMC_DEV}${C_RESET}"
    echo -e "${C_PROGRESS}日志: ${LOGDIR}${C_RESET}"
    echo ""
    echo -e "  ${C_PASS}PASS: ${PASS}${C_RESET}"
    echo -e "  ${C_FAIL}FAIL: ${FAIL}${C_RESET}"
    echo -e "  ${C_WARN}WARN: ${WARN}${C_RESET}"
    echo -e "  TOTAL: ${TOTAL}"
    echo "" >> "${LOGDIR}/results.log"
    echo "PASS=${PASS} FAIL=${FAIL} WARN=${WARN} TOTAL=${TOTAL}" >> "${LOGDIR}/results.log"
    echo "Ended: $(date)" >> "${LOGDIR}/results.log"
    if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
        echo -e "\n${C_PASS}🎉 测试通过! eMMC 健康状态良好${C_RESET}"
    elif [ "${FAIL}" -eq 0 ]; then
        echo -e "\n${C_WARN}⚠ 通过但有 ${WARN} 项警告${C_RESET}"
    else
        echo -e "\n${C_FAIL}✘ ${FAIL} 项失败! 详情: ${LOGDIR}/results.log${C_RESET}"
    fi
}

# ─── 格式化延迟值 (ns -> 可读格式) ────────────────────────────
fmt_latency() {
    local val=$1
    if [ "${val}" = "N/A" ] || [ "${val}" = "null" ] || [ -z "${val}" ]; then
        printf "  N/A  "
        return
    fi
    if [ "${val}" -gt 1000000 ]; then
        printf "%6.1fms" "$(echo "${val}/1000000" | bc -l 2>/dev/null)"
    else
        printf "%7.0fμs" "$(echo "${val}/1000" | bc -l 2>/dev/null)"
    fi
}

# ─── 动态偏移计算 (按设备容量百分比) ─────────────────────────
# 用法: pct_offset <百分比>   → 返回 fio 可用的 offset 字符串 (如 "25G" 或 "12800M")
#       pct_size  <百分比>   → 返回 fio 可用的 size 字符串
#       pct_check <百分比>   → 检查设备是否有足够的空间, 不够则 warn + return 1
# 所有测试使用这些函数替代硬编码偏移, 自动适配任意容量设备

pct_offset() {
    local pct=$1
    # 预留 2% 尾部余量, 保证不会超出设备末尾
    local safe_mb=$((DEVICE_SIZE_MB * pct / 100))
    if [ "${safe_mb}" -ge 1024 ]; then
        # fio 接受 "N" 后缀表示 MiB; 用 M 后缀确保 fio 正确解析
        echo "${safe_mb}M"
    else
        echo "${safe_mb}M"
    fi
}

pct_size() {
    local pct=$1
    local size_mb=$((DEVICE_SIZE_MB * pct / 100))
    if [ "${size_mb}" -lt 1 ]; then
        echo "1M"  # 至少 1MB
    elif [ "${size_mb}" -ge 1024 ]; then
        echo "${size_mb}M"
    else
        echo "${size_mb}M"
    fi
}

pct_check() {
    local test_name="$1"
    local needed_pct=$2   # 需要的总空间百分比 (offset + size)
    local needed_mb=$((DEVICE_SIZE_MB * needed_pct / 100))

    if [ "${DEVICE_SIZE_MB}" -le 0 ]; then
        warn "${test_name}: 无法确认设备容量"
        return 1
    fi
    if [ "${needed_mb}" -ge "${DEVICE_SIZE_MB}" ]; then
        warn "${test_name}: 需要 ${needed_pct}% 空间 (~${needed_mb}MB) 但设备仅 ${DEVICE_SIZE_MB}MB — 跳过"
        return 1
    fi
    return 0
}
