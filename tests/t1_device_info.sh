#!/bin/bash
# T1 — eMMC 设备信息与寿命评估
# 读取 EXT_CSD 寄存器, 评估 eMMC 健康状态

TEST_ID="t1"
TEST_NAME="eMMC 设备信息与寿命评估"
TEST_DESC="读取 EXT_CSD, 检查 PRE_EOL / 磨损等级 / 固件版本"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"

    # ─── sysfs 基础信息 ───
    step "sysfs 设备信息"
    local dev_name="${EMMC_DEV#/dev/}"
    for attr in name manfid hwrev fwrev date serial; do
        local val=$(cat "/sys/block/${dev_name}/device/${attr}" 2>/dev/null || echo "N/A")
        info "${attr} = ${val}"
    done

    # ─── mmc-utils EXT_CSD ───
    if [ "${HAS_MMC_UTILS}" = false ]; then
        warn "mmc-utils 未安装, 跳过 EXT_CSD 深度读取"
        info "安装: sudo apt install mmc-utils"
        return
    fi

    step "CID 寄存器"
    mmc cid read "${EMMC_DEV}" 2>&1 | while IFS= read -r line; do info "CID: ${line}"; done

    step "EXT_CSD 关键字段"
    local extcsd_raw
    extcsd_raw=$(mmc extcsd read "${EMMC_DEV}" 2>&1)
    echo "${extcsd_raw}" > "${LOGDIR}/ext_csd.txt"

    declare -A fields=(
        ["DEVICE_VERSION"]="eMMC协议版本"
        ["FIRMWARE_VERSION"]="内部固件版本"
        ["PRE_EOL_INFO"]="预寿命耗尽 (0=正常, 3=耗尽)"
        ["LIFE_TIME_EST_TYP_A"]="寿命 A (SLC, 0-10)"
        ["LIFE_TIME_EST_TYP_B"]="寿命 B (MLC/TLC, 0-10)"
        ["RPMB_SIZE"]="RPMB 分区大小"
        ["CACHE_SIZE"]="内部Cache大小"
        ["BKOPS_EN"]="BKOPS 状态 (1=手动, 2=自动)"
        ["BOOT_SIZE_MULT"]="Boot分区大小"
    )
    for key in "${!fields[@]}"; do
        local val=$(echo "${extcsd_raw}" | grep -i "${key}" | head -1)
        [ -n "${val}" ] && info "${fields[$key]}: ${val}"
    done

    # ─── 健康分析 ───
    step "健康状态"
    local pre_eol=$(echo "${extcsd_raw}" | grep -i "PRE_EOL_INFO" | awk '{print $NF}' | tr -d ' ')
    case "${pre_eol}" in
        "0x0"|"0") pass "PRE_EOL: 正常" ;;
        "0x1")     warn "PRE_EOL: 已消耗 ~90% 寿命";;
        "0x2")     warn "PRE_EOL: 已消耗 ~90% 寿命(变体)";;
        "0x3")     fail "PRE_EOL: 寿命已超 — 应更换!" ;;
        *)         info "PRE_EOL: ${pre_eol}" ;;
    esac

    local lt_a=$(echo "${extcsd_raw}" | grep -i "LIFE_TIME_EST_TYP_A" | awk '{print $NF}' | tr -d ' ')
    local lt_b=$(echo "${extcsd_raw}" | grep -i "LIFE_TIME_EST_TYP_B" | awk '{print $NF}' | tr -d ' ')
    info "磨损: Type A=${lt_a} Type B=${lt_b}"

    local lt_a_num=$((lt_a)); local lt_b_num=$((lt_b))
    [ "${lt_a_num}" -ge 9 ] 2>/dev/null && fail "Type A ≥9, 接近寿命终点" || \
    [ "${lt_a_num}" -ge 7 ] 2>/dev/null && warn "Type A ≥7, 显著磨损"
    [ "${lt_b_num}" -ge 9 ] 2>/dev/null && fail "Type B ≥9, 接近寿命终点" || \
    [ "${lt_b_num}" -ge 7 ] 2>/dev/null && warn "Type B ≥7, 显著磨损"

    pass "eMMC 信息采集完成"
}
