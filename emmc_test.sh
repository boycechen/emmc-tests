#!/bin/bash
# ================================================================
# eMMC Deep Stress Test Suite — 模块化入口脚本
# 用法:
#   sudo ./emmc_test.sh --list              # 列出所有测试
#   sudo ./emmc_test.sh --run-all           # 全自动运行
#   sudo ./emmc_test.sh --run t1,t3,t7      # 选择指定测试
#   sudo ./emmc_test.sh --interactive       # 交互菜单模式
#   sudo ./emmc_test.sh --run t7 --device /dev/mmcblk0
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
TESTS_DIR="${SCRIPT_DIR}/tests"
LOGDIR=""
EMMC_DEV=""
TIMESTAMP=""

# ─── 初始化加载 ──────────────────────────────────────────────
source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/devices.sh"

# ─── 全局变量 ──────────────────────────────────────────────────
_START_TIME=0

# ─── 自动发现测试 ────────────────────────────────────────────
declare -A TEST_MAP    # id -> name
declare -A TEST_DESC_MAP # id -> description
declare -A TEST_FILE_MAP # id -> file path
declare -a TEST_IDS

discover_tests() {
    TEST_IDS=()
    if [ ! -d "${TESTS_DIR}" ]; then
        fail "tests 目录不存在: ${TESTS_DIR}"
        exit 1
    fi

    for f in "${TESTS_DIR}"/*.sh; do
        [ -f "${f}" ] || continue
        # 重置当前文件的元数据
        TEST_ID=""
        TEST_NAME=""
        TEST_DESC=""
        # 临时 source 只提取元数据
        source "${f}"
        if [ -n "${TEST_ID}" ]; then
            TEST_MAP["${TEST_ID}"]="${TEST_NAME}"
            TEST_DESC_MAP["${TEST_ID}"]="${TEST_DESC}"
            TEST_FILE_MAP["${TEST_ID}"]="${f}"
            TEST_IDS+=("${TEST_ID}")
        fi
    done
}

# ─── 列出测试 ────────────────────────────────────────────────
list_tests() {
    echo -e "\n${C_TITLE}可用测试项目:${C_RESET}"
    echo -e "${C_INFO}────────────────────────────────────────────────${C_RESET}"
    for id in "${TEST_IDS[@]}"; do
        printf "  ${C_STEP}%-6s${C_RESET} %-30s ${C_INFO}%s${C_RESET}\n" \
            "${id}" "${TEST_MAP[$id]}" "${TEST_DESC_MAP[$id]}"
    done
    echo -e "${C_INFO}────────────────────────────────────────────────${C_RESET}"
    echo -e "  ${C_STEP}--run-all${C_RESET}  运行全部测试"
    echo -e "  ${C_STEP}--interactive${C_RESET}  交互菜单模式"
}

# ─── 运行单测试 (带计时和结果追踪) ────────────────────────────
run_single_test() {
    local id="$1"
    local file="${TEST_FILE_MAP[$id]}"

    if [ -z "${file}" ]; then
        fail "未知测试: ${id} (可用: ${TEST_IDS[*]})"
        return 1
    fi

    # 快照计数器
    local b_pass=$PASS b_fail=$FAIL b_warn=$WARN

    # 开始计时
    local t_start
    t_start=$(date +%s)

    # 重新加载并执行测试
    unset run_test 2>/dev/null || true
    source "${file}"

    if declare -f run_test > /dev/null; then
        run_test
    else
        fail "测试 ${id} 未定义 run_test 函数"
        return 1
    fi

    # 结束计时
    local t_end
    t_end=$(date +%s)
    local duration=$((t_end - t_start))

    # 计算增量
    local d_pass=$((PASS - b_pass))
    local d_fail=$((FAIL - b_fail))
    local d_warn=$((WARN - b_warn))

    # 确定结果
    local result="PASS"
    [ "${d_fail}" -gt 0 ] && result="FAIL"
    [ "${d_fail}" -eq 0 ] && [ "${d_warn}" -gt 0 ] && result="WARN"

    local name="${TEST_MAP[$id]:-${id}}"
    record_test_result "${id}" "${name}" "${duration}" "${result}" "${d_pass}" "${d_fail}" "${d_warn}"
}

# ─── 运行多个测试 ────────────────────────────────────────────
run_tests() {
    local ids_str="$1"
    IFS=',' read -ra ids <<< "${ids_str}"
    reset_test_tracking

    for id in "${ids[@]}"; do
        id=$(echo "${id}" | xargs)  # trim
        echo -e "\n${C_TITLE}═══════ 运行: ${id} — ${TEST_MAP[$id]} ═══════${C_RESET}"
        run_single_test "${id}"
    done
    summary
}

# ─── 运行全部 ────────────────────────────────────────────────
run_all() {
    echo -e "\n${C_TITLE}═══════ 全自动运行模式 ═══════${C_RESET}"
    echo -e "${C_WARN}所有测试将按顺序运行, 预计耗时: 60-90 分钟${C_RESET}"
    echo -e "${C_WARN}(设置 DURATION_LONG=600 可缩短长时间测试时长)${C_RESET}"

    if ! ask_yes "开始全自动测试?"; then
        return
    fi
    reset_test_tracking

    for id in "${TEST_IDS[@]}"; do
        echo -e "\n${C_TITLE}═══════ [${id}] ${TEST_MAP[$id]} ═══════${C_RESET}"
        run_single_test "${id}"
    done
    summary
}

# ─── 交互菜单 ────────────────────────────────────────────────
interactive_menu() {
    while true; do
        clear
        echo -e "${C_TITLE}"
        echo "╔═════════════════════════════════════════════════╗"
        echo "║    eMMC Deep Stress Test Suite v3.0            ║"
        echo "║    模块化 · 可扩展 · fio 驱动                  ║"
        echo "╠═════════════════════════════════════════════════╣"
        echo "║  设备: ${EMMC_DEV:-未选择}           ║"
        echo "╚═════════════════════════════════════════════════╝"
        echo -e "${C_RESET}"
        echo "  ${C_PROMPT}测试项目:${C_RESET}"
        echo ""

        local idx=0
        for id in "${TEST_IDS[@]}"; do
            printf "  ${C_STEP}[%2d]${C_RESET} %-6s %-30s %s\n" \
                "$((idx+1))" "${id}" "${TEST_MAP[$id]}" "${C_INFO}${TEST_DESC_MAP[$id]}${C_RESET}"
            ((idx++))
        done

        echo ""
        echo "  ${C_PROMPT}[A]${C_RESET} 运行全部"
        echo "  ${C_PROMPT}[D]${C_RESET} 选择设备"
        echo "  ${C_PROMPT}[Q]${C_RESET} 退出"
        echo ""
        echo -n "请选择 [1-${#TEST_IDS[@]}/A/D/Q]: "
        read -r choice

        case "${choice^^}" in
            A)
                run_all
                echo -e "\n${C_PROMPT}按回车返回菜单...${C_RESET}"
                read -r
                ;;
            D)
                select_device
                ;;
            Q)
                echo -e "${C_WARN}退出.${C_RESET}"
                exit 0
                ;;
            *)
                if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#TEST_IDS[@]}" ]; then
                    local id="${TEST_IDS[$((choice-1))]}"
                    echo -e "\n${C_TITLE}═══════ 运行: ${id} — ${TEST_MAP[$id]} ═══════${C_RESET}"
                    run_single_test "${id}"
                    summary
                    echo -e "\n${C_PROMPT}按回车返回菜单...${C_RESET}"
                    read -r
                else
                    echo -e "${C_FAIL}无效选项${C_RESET}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# ─── 用法 ────────────────────────────────────────────────────
usage() {
    echo "用法: sudo $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --list             列出所有可用测试"
    echo "  --run <id1,id2..>  运行指定测试 (逗号分隔)"
    echo "  --run-all          运行全部测试"
    echo "  --interactive      交互菜单模式"
    echo "  --device <dev>     指定测试设备 (如 /dev/mmcblk0)"
    echo "  --help             显示此帮助"
    echo ""
    echo "示例:"
    echo "  sudo $0 --list"
    echo "  sudo $0 --run t1,t3,t7 --device /dev/mmcblk0"
    echo "  sudo $0 --run-all"
    echo "  sudo $0 --interactive"
}

# ─── 入口 ────────────────────────────────────────────────────
main() {
    # 先解析 --help / --list (不需要 root)
    for arg in "$@"; do
        case "${arg}" in
            --help|-h) usage; exit 0 ;;
            --list)    discover_tests; list_tests; exit 0 ;;
        esac
    done

    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${C_FAIL}错误: 需要 root 权限${C_RESET}"
        echo "请使用: sudo $0"
        exit 1
    fi

    # 全局工具检测
    command -v fio &>/dev/null || { echo -e "${C_FAIL}错误: 未找到 fio, 请安装: sudo apt install fio${C_RESET}"; exit 1; }
    command -v mmc &>/dev/null && HAS_MMC_UTILS=true
    command -v bc &>/dev/null || echo -e "${C_WARN}提示: bc 未安装, 建议: sudo apt install bc${C_RESET}"

    # 自动发现测试
    discover_tests
    if [ ${#TEST_IDS[@]} -eq 0 ]; then
        echo -e "${C_FAIL}错误: 未发现任何测试 (tests/ 目录为空?)${C_RESET}"
        exit 1
    fi

    # 无参数 → 交互模式
    if [ $# -eq 0 ]; then
        select_device
        init_logdir
        interactive_menu
        return
    fi

    # 解析参数
    local mode=""
    local run_ids=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --list)       mode="list" ;;   # already handled above
            --run)        shift; mode="run"; run_ids="$1" ;;
            --run-all)    mode="run_all" ;;
            --interactive|--menu|--tui)
                          mode="interactive" ;;
            --device)     shift; EMMC_DEV="$1" ;;
            --help|-h)    usage; exit 0 ;;
            *)            echo -e "${C_FAIL}未知选项: $1${C_RESET}"; usage; exit 1 ;;
        esac
        shift
    done

    case "${mode}" in
        list)
            list_tests
            ;;
        run)
            if [ -z "${EMMC_DEV}" ]; then
                select_device
            else
                detect_device_size
            fi
            init_logdir
            run_tests "${run_ids}"
            ;;
        run_all)
            if [ -z "${EMMC_DEV}" ]; then
                select_device
            else
                detect_device_size
            fi
            init_logdir
            run_all
            ;;
        interactive)
            if [ -z "${EMMC_DEV}" ]; then
                select_device
            else
                detect_device_size
            fi
            init_logdir
            interactive_menu
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
