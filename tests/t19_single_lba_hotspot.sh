#!/bin/bash
# T19 — 单 LBA 热点测试
# 对同一 LBA 反复写入数千次, 迫使 eMMC 内部磨损均衡介入
# 检测重映射逻辑、写计数器的准确性、保留块管理

TEST_ID="t19"
TEST_NAME="单 LBA 热点 (磨损均衡)"
TEST_DESC="同一 LBA 上万次重复写入, 验证重映射和磨损均衡"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 同一逻辑地址反复写入, eMMC 内部应重映射到不同物理块.${C_RESET}"
    echo -e "${C_INFO}  固件 bug 会导致重复写入同一物理块而快速磨损.${C_RESET}"

    local hot_lba="${EMMC_DEV}"
    pct_check "T19" 51 || { warn "设备空间不足, 跳过 T19"; return; }
    local offset=$(pct_offset 50)
    local iterations=20000

    step "单 LBA 反复写入 (${iterations} 次)"
    progress "对同一 4K 地址循环写入 ${iterations} 次..."
    info "使用 fio --size=4k --bs=4k --rw=write --loops=${iterations}"
    info "说明: 写入不应失败, 性能不应逐渐恶化"

    if run_fio "t19_single_lba" \
        --name=t19_hot --filename="${EMMC_DEV}" --offset="${offset}" --size=4k \
        --direct=1 --ioengine=sync --rw=write --bs=4k \
        --loops="${iterations}" \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --group_reporting; then
        pass "单 LBA ${iterations} 次重复写入: 全部通过"
    else
        local log="${LOGDIR}/fio_t19_single_lba.json"
        local err=$(get_fio_error "${log}")
        # 检查实际写完多少
        local wk_bytes=$(grep -oP '"io_bytes":\s*\K[0-9]+' "${log}" | head -2 | tail -1 2>/dev/null || echo "N/A")
        fail "单 LBA 写入出错! (error=${err}, 已写入字节=${wk_bytes})"
        info "如果错误出现在接近 ${iterations} 次时, 说明保留块可能不足"
        info "如果错误出现在早期, 说明固件重映射逻辑异常"
    fi

    step "单 LBA 写入后的回读验证"
    progress "多次重复读取同一 LBA..."
    if run_fio "t19_lba_readverify" \
        --name=t19_rdvfy --filename="${EMMC_DEV}" --offset="${offset}" --size=4k \
        --direct=1 --ioengine=sync --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 \
        --loops=100 --group_reporting; then
        pass "单 LBA 100 次反复读取 + CRC 验证通过"
    else
        local log="${LOGDIR}/fio_t19_lba_readverify.json"
        fail "单 LBA 回读 CRC 错误! (error=$(get_fio_error "${log}"))"
    fi
}
