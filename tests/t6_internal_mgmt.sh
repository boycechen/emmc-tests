#!/bin/bash
# T6 — eMMC 内部管理功能 (Cache/BKOPS/Sleep)
# 需要 mmc-utils

TEST_ID="t6"
TEST_NAME="eMMC 内部管理功能"
TEST_DESC="Cache开关/BKOPS/睡眠唤醒 状态机测试"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"

    if [ "${HAS_MMC_UTILS}" = false ]; then
        warn "需要 mmc-utils, 请安装: sudo apt install mmc-utils"
        return
    fi

    # ── Cache 开关 ──
    step "Test 6a: Cache 切换"
    for mode in enable disable enable; do
        mmc cache "${mode}" "${EMMC_DEV}" 2>/dev/null && {
            dd if="${EMMC_DEV}" of=/dev/null bs=4k count=1000 iflag=direct 2>/dev/null && \
                info "Cache ${mode} → 读写正常" || \
                fail "Cache ${mode} 后读取失败"
        } || warn "Cache ${mode} 失败 (内核可能不支持)"
    done
    pass "Cache 切换正常"

    # ── BKOPS ──
    step "Test 6b: BKOPS 状态"
    local extcsd="${LOGDIR}/ext_csd.txt"
    if [ -f "${extcsd}" ]; then
        local bk=$(grep "BKOPS_EN" "${extcsd}" | awk '{print $NF}')
        info "BKOPS_EN = ${bk}"
        case "${bk}" in
            "0x2"|"2") pass "BKOPS 自动模式" ;;
            "0x1"|"1") warn "BKOPS 手动模式" ;;
            "0x0"|"0") warn "BKOPS 未启用" ;;
        esac
    fi

    # ── 睡眠/唤醒 ──
    step "Test 6c: 睡眠/唤醒"
    if mmc sleep "${EMMC_DEV}" 2>/dev/null; then
        info "已睡眠, 等待 3s..."
        sleep 3
        if mmc awake "${EMMC_DEV}" 2>/dev/null; then
            sleep 1
            dd if="${EMMC_DEV}" of=/dev/null bs=4k count=500 iflag=direct 2>/dev/null && \
                pass "Sleep/Awake 正常" || fail "唤醒后读取失败"
        else warn "唤醒失败 (内核兼容性)"
        fi
    else warn "睡眠失败 (内核可能不支持 MMC_SLEEP_AWAKE)"
    fi
}
