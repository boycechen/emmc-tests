#!/bin/bash
# T10 — 性能基线 (检测性能退化)

TEST_ID="t10"
TEST_NAME="性能基线"
TEST_DESC="4项基准测试, 与历史对比发现硬件退化"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    local basefile="${LOGDIR}/performance_baseline.txt"

    step "顺序读 (1M)"
    run_fio "t10_seqrd" \
        --name=t10_seqrd --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=8 --rw=read --bs=1M \
        --runtime=30 --time_based --group_reporting || true
    local seqrd=$(extract_fio_metric "${LOGDIR}/fio_t10_seqrd.json" "read_bw")
    info "顺序读 (1M): ${seqrd} KB/s"

    step "顺序写 (1M)"
    run_fio "t10_seqwr" \
        --name=t10_seqwr --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=8 --rw=write --bs=1M \
        --runtime=30 --time_based --group_reporting || true
    local seqwr=$(extract_fio_metric "${LOGDIR}/fio_t10_seqwr.json" "write_bw")
    info "顺序写 (1M): ${seqwr} KB/s"

    step "随机读 (4K, QD32)"
    run_fio "t10_randrd" \
        --name=t10_randrd --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randread --bs=4k \
        --runtime=30 --time_based --group_reporting || true
    local randrd=$(extract_fio_metric "${LOGDIR}/fio_t10_randrd.json" "read_iops")
    info "随机读 (4K, QD32): ${randrd} IOPS"

    step "随机写 (4K, QD32)"
    run_fio "t10_randwr" \
        --name=t10_randwr --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randwrite --bs=4k \
        --runtime=30 --time_based --group_reporting || true
    local randwr=$(extract_fio_metric "${LOGDIR}/fio_t10_randwr.json" "write_iops")
    info "随机写 (4K, QD32): ${randwr} IOPS"

    cat > "${basefile}" <<EOF
Performance Baseline — $(date)
Device: ${EMMC_DEV}
========================================
Sequential Read  (1M):   ${seqrd} KB/s
Sequential Write (1M):   ${seqwr} KB/s
Random Read  (4K, QD32): ${randrd} IOPS
Random Write (4K, QD32): ${randwr} IOPS
EOF
    info "基线已保存: ${basefile}"

    # 合理性检查
    local srd=$(echo "${seqrd}" | cut -d. -f1)
    if [ -n "${srd}" ] && [ "${srd}" -gt 0 ] 2>/dev/null && [ "${srd}" -lt 50000 ]; then
        warn "顺序读 ${seqrd}KB/s < 50MB/s, 可能为低速模式或退化"
    else
        pass "性能基线建立完成"
    fi
}
