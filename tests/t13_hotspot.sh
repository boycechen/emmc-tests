#!/bin/bash
# T13 — 热区写压力 (Hot Spot Write)
# 反复对同一小范围 LBA 写入, 迫使 eMMC 磨损均衡和坏块重映射介入
# 如果重映射失败或保留块耗尽, 会出现写错误

TEST_ID="t13"
TEST_NAME="热区写压力 (Hot Spot)"
TEST_DESC="反复覆盖同一 LBA 区域, 测试重映射和磨损均衡"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 持续对同一 128MB 范围写入, 迫使 eMMC 内部反复重映射.${C_RESET}"
    echo -e "${C_INFO}  正常 eMMC 应能承受数百万次编程而无外部可见错误.${C_RESET}"

    local hot_offset=$(pct_offset 50)
    local hot_size="128M"
    local total_writes_mb=$((4 * 1024))    # 总写入 4GB (实际映射到同一小块物理区域)
    local bs="4k"

    pct_check "T13" 52 || { warn "设备空间不足, 跳过 T13"; return; }

    step "热区写入压力 (目标: ${hot_size} 区域, 总写入 ~4GB)"
    progress "预计运行时间: 约 3-5 分钟 (取决于 eMMC 速度)..."

    # 使用 --loops 计算写入次数: 4GB / 128MB = 32 次全区域覆盖
    local num_loops=32

    if run_fio "t13_hotspot" \
        --name=t13_hot --filename="${EMMC_DEV}" --offset="${hot_offset}" --size="${hot_size}" \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=write --bs="${bs}" \
        --loops="${num_loops}" --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --group_reporting; then
        pass "热区写入完成: 无错误 — 重映射/磨损均衡正常"
    else
        local log="${LOGDIR}/fio_t13_hotspot.json"
        local err=$(get_fio_error "${log}")
        fail "热区写入错误 (error=${err}) — 保留块可能已耗尽!"
        grep -i 'error\|EIO\|media' "${log}" 2>/dev/null | head -5 | while IFS= read -r line; do
            info "  错误详情: ${line}"
        done
    fi

    step "热区最终校验"
    progress "全量回读 CRC 验证..."
    if run_fio "t13_verify" \
        --name=t13_hotvfy --filename="${EMMC_DEV}" --offset="${hot_offset}" --size="${hot_size}" \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 --group_reporting; then
        pass "热区 CRC 校验通过"
    else
        fail "热区校验出现 CRC 错误!"
    fi

    # 提取总写入量
    local log="${LOGDIR}/fio_t13_hotspot.json"
    local wb=$(extract_fio_metric "${log}" "write_bw")
    local wi=$(extract_fio_metric "${log}" "write_iops")
    info "热区写入性能: ${wi} IOPS / ${wb} KB/s"
}
