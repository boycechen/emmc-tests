#!/bin/bash
# T8 — ECC / 坏块重映射压力
# 同步模式(iodepth=1) + 4K 小粒度随机写, 迫使频繁 ECC/坏块替换

TEST_ID="t8"
TEST_NAME="ECC / 坏块重映射压力"
TEST_DESC="同步 4K 随机写 600s, 耗尽保留块池"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    step "4K 同步随机写 (600s, iodepth=1)"
    progress "运行中 (约 10 分钟)... 检查重映射/ECC边界"
    if run_fio "t8_ecc_stress" \
        --name=t8_ecc --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 4) \
        --direct=1 --ioengine=sync --iodepth=1 --rw=randwrite --bs=4k \
        --runtime=600 --time_based; then
        local log="${LOGDIR}/fio_t8_ecc_stress.json"
        local wi=$(extract_fio_metric "${log}" "write_iops")
        local wb=$(extract_fio_metric "${log}" "write_bw")
        info "IOPS=${wi} BW=${wb}KB/s"
        pass "4K 同步写 600s: 无错误 — ECC/重映射正常"
    else
        local log="${LOGDIR}/fio_t8_ecc_stress.json"
        fail "ECC 压力测试错误 (error=$(get_fio_error "${log}"))"
        info "这是最严重的测试! I/O 错误说明坏块保留池已耗尽或 ECC 失效"
    fi

    step "回读验证"
    run_fio "t8_ecc_verify" \
        --name=t8_verify --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 4) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --runtime=120 --time_based --group_reporting || true

    local log="${LOGDIR}/fio_t8_ecc_verify.json"
    local err=$(get_fio_error "${log}")
    [ "${err}" = "0" ] && pass "ECC 区域回读通过" || fail "ECC 区域回读 error=${err}"
}
