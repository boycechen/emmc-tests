#!/bin/bash
# T9 — 多线程并发 I/O (控制器仲裁压力)

TEST_ID="t9"
TEST_NAME="多线程并发 I/O"
TEST_DESC="3线程并行 4K 随机访问, 控制器多通道仲裁"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    step "3 线程 4K 随机混合读写 (3min)"
    progress "运行中..."
    if run_fio "t9_concurrent" \
        --name=t9_conc --filename="${EMMC_DEV}" --numjobs=3 --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=randrw --rwmixread=50 \
        --bs=4k --runtime=180 --time_based --group_reporting; then
        pass "3 线程并发 I/O 正常"
    else
        local log="${LOGDIR}/fio_t9_concurrent.json"
        fail "并发 I/O 错误 (error=$(get_fio_error "${log}")) — 控制器仲裁异常!"
    fi

    local log="${LOGDIR}/fio_t9_concurrent.json"
    local ri=$(extract_fio_metric "${log}" "read_iops")
    local wi=$(extract_fio_metric "${log}" "write_iops")
    local rb=$(extract_fio_metric "${log}" "read_bw")
    local wb=$(extract_fio_metric "${log}" "write_bw")
    info "3线程: R_IOPS=${ri} W_IOPS=${wi} R_BW=${rb}KB/s W_BW=${wb}KB/s"
}
