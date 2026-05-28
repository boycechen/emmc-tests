#!/bin/bash
# T27 — 系统缓存层与 eMMC 交互压力
# 测试 buffered I/O (通过 page cache) 下的大规模写入
# 此时内核会异步刷写, 可能暴露块层/驱动层的并发问题

TEST_ID="t27"
TEST_NAME="Page Cache 交互压力"
TEST_DESC="buffered I/O 大量写入, 检测内核块层与 eMMC 驱动交互"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 使用 buffered I/O (non-direct), 数据经 page cache.${C_RESET}"
    echo -e "${C_INFO}  内核异步刷写策略可能暴露驱动层的并发和顺序问题.${C_RESET}"

    step "Test 27a: buffered 随机写 (10GB, 无 verify)"
    progress "使用 buffered I/O 写入 10GB 数据 (通过 page cache)..."
    if run_fio "t27_buffered_write" \
        --name=t27_bufw --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 9) \
        --direct=0 --ioengine=libaio --iodepth=8 --rw=randwrite --bs=4k \
        --runtime=300 --time_based --group_reporting; then
        pass "buffered 随机写完成"
    else
        local log="${LOGDIR}/fio_t27_buffered_write.json"
        local err=$(get_fio_error "${log}")
        if [ "${err}" != "0" ]; then
            fail "buffered 写出错! (error=${err})"
        fi
    fi

    # 强制内核刷回
    progress "强制刷回 page cache..."
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    step "Test 27b: buffered 写后回读验证"
    if run_fio "t27_buffered_verify" \
        --name=t27_bufvfy --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 9) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 --group_reporting; then
        pass "buffered 写后回读 CRC 全部通过 — page cache 交互正常"
    else
        local log="${LOGDIR}/fio_t27_buffered_verify.json"
        fail "buffered 写后回读发现错误! (error=$(get_fio_error "${log}"))"
        info "可能是内核刷写策略问题, 或 eMMC 在异步写下出现异常"
    fi

    # 清理区域 (丢弃缓存)
    progress "执行 blkdiscard 清理测试区域..."
    local discard_bytes=$((10 * 1073741824))
    local discard_off=$((46 * 1073741824))
    blkdiscard -o "${discard_off}" -l "${discard_bytes}" "${EMMC_DEV}" 2>/dev/null || \
        warn "blkdiscard 失败 (不影响测试结论)"
}
