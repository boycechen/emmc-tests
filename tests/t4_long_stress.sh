#!/bin/bash
# T4 — 长时间混合压力 (稳定性/热/BKOPS/GC调度)

TEST_ID="t4"
TEST_NAME="长时间混合压力"
TEST_DESC="30分钟持续混合读写, 暴露热失效/GC/BKOPS问题"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    local duration="${DURATION_LONG:-1800}"

    # ── 4K 混合读写 70/30 ──
    step "4K 混合读写 70/30 (${duration}s)"
    progress "可在另一终端查看进度: tail -f ${LOGDIR}/fio_t4_mix.json"
    if run_fio "t4_mix" \
        --name=t4_mix --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 4) \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randrw --rwmixread=70 \
        --bs=4k --verify=crc32c --verify_state_save=0 \
        --runtime="${duration}" --time_based --group_reporting; then
        pass "4K 混合读写 ${duration}s: 无错误"
    else
        local log="${LOGDIR}/fio_t4_mix.json"
        fail "混合读写错误 (error=$(get_fio_error "${log}"))"
    fi

    # ── 1M 顺序写(大块) ──
    step "1M 顺序写 (大块吞吐, 5min)"
    progress "运行中..."
    if run_fio "t4_seq" \
        --name=t4_seq --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 3) \
        --direct=1 --ioengine=libaio --iodepth=8 --rw=write --bs=1M \
        --verify=crc32c --verify_state_save=0 \
        --runtime=300 --time_based --group_reporting; then
        pass "1M 顺序写 300s: 无错误"
    else
        local log="${LOGDIR}/fio_t4_seq.json"
        fail "1M 顺序写错误 (error=$(get_fio_error "${log}"))"
    fi

    # ── 提取性能特征 ──
    step "性能特征"
    for logfile in "${LOGDIR}"/fio_t4_*.json; do
        [ ! -f "${logfile}" ] && continue
        local name=$(basename "${logfile}" .json)
        local ri=$(extract_fio_metric "${logfile}" "read_iops")
        local wi=$(extract_fio_metric "${logfile}" "write_iops")
        local rb=$(extract_fio_metric "${logfile}" "read_bw")
        local wb=$(extract_fio_metric "${logfile}" "write_bw")
        info "${name}: R_IOPS=${ri} W_IOPS=${wi} R_BW=${rb}KB/s W_BW=${wb}KB/s"
    done
}
