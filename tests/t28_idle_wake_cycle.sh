#!/bin/bash
# T28 — 设备空闲/唤醒状态切换压力
# 反复让 eMMC 在活跃和空闲之间切换, 检测 BKOPS 和 GC 调度策略
# 某些 eMMC 在长时间空闲后重新唤醒时会出现响应卡顿

TEST_ID="t28"
TEST_NAME="空闲/唤醒切换压力"
TEST_DESC="重复短时读写 + 长时间空闲, 检测BKOPS/GC调度"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 短时密集写入 → 长时间空闲(设备BKOPS/GC).${C_RESET}"
    echo -e "${C_INFO}  如果 BKOPS 有 bug, 唤醒后首次读写会超时.${C_RESET}"

    local cycles=10

    step "空闲/唤醒循环 (${cycles} 次)"
    for ((c=1; c<=cycles; c++)); do
        progress "[${c}/${cycles}] 写入 256MB..."
        run_fio "t28_cycle_${c}" \
            --name=t28_c${c} --filename="${EMMC_DEV}" --offset=$((48 + c))G --size=256M \
            --direct=1 --ioengine=libaio --iodepth=32 --rw=write --bs=4k \
            --verify=crc32c --verify_state_save=0 --output=/dev/null 2>/dev/null || {
            fail "周期 ${c} 写入失败!"
            continue
        }

        progress "空闲 30s (等待 BKOPS/GC)..."
        sync
        sleep 30

        progress "唤醒后回读校验..."
        run_fio "t28_cycle_${c}_vfy" \
            --name=t28_v${c} --filename="${EMMC_DEV}" --offset=$((48 + c))G --size=256M \
            --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
            --verify=crc32c --verify_only --verify_state_save=0 --output=/dev/null 2>/dev/null || {
            fail "周期 ${c} 唤醒后回读错误! — BKOPS/GC 可能异常!"
            info "检查 dmesg 是否有 mmc 超时信息"
            continue
        }
        info "周期 ${c}: 唤醒后读写正常"
    done

    pass "空闲/唤醒循环完成"

    step "dmesg 检查"
    if command -v dmesg &>/dev/null; then
        local mmc_errors=$(dmesg | grep -i "mmc\|emmc" | grep -i "error\|timeout\|fail\|abort\|reset" | tail -5 2>/dev/null || true)
        if [ -n "${mmc_errors}" ]; then
            warn "dmesg 中发现 MMC 相关错误:"
            echo "${mmc_errors}" | while IFS= read -r line; do warn "  ${line}"; done
        else
            info "dmesg 中无 MMC 错误"
        fi
    fi
}
