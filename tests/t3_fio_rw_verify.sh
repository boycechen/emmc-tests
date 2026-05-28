#!/bin/bash
# T3 — fio CRC32C 校验 (ECC/数据路径压力)

TEST_ID="t3"
TEST_NAME="fio CRC32C 校验 (ECC 压力)"
TEST_DESC="4K随机写+128K顺序写, 立即CRC32C验证"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    # ── 4K 随机写 + 验证 ──
    step "4K 随机写 + CRC32C (5min)"
    progress "运行中..."
    if run_fio "t3_randwrite" \
        --name=t3_randwrite --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 3) \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randwrite --bs=4k \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=300 --time_based --group_reporting; then
        pass "4K 随机写 + CRC32C 通过"
    else
        local log="${LOGDIR}/fio_t3_randwrite.json"
        fail "4K 随机写校验失败 (error=$(get_fio_error "${log}"))"
    fi

    # ── 128K 顺序写 + 验证 ──
    step "128K 顺序写 + CRC32C (3min)"
    progress "运行中..."
    if run_fio "t3_seqwrite" \
        --name=t3_seqwrite --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 3) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=write --bs=128k \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=180 --time_based --group_reporting; then
        pass "128K 顺序写 + CRC32C 通过"
    else
        local log="${LOGDIR}/fio_t3_seqwrite.json"
        fail "128K 顺序写校验失败 (error=$(get_fio_error "${log}"))"
    fi

    # ── 全量回读校验 ──
    step "全量回读校验"
    progress "运行中..."
    if run_fio "t3_readverify" \
        --name=t3_readverify --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 3) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 --group_reporting; then
        pass "全量回读 CRC32C 校验通过"
    else
        local log="${LOGDIR}/fio_t3_readverify.json"
        fail "回读发现校验错误 (error=$(get_fio_error "${log}"))"
    fi
}
