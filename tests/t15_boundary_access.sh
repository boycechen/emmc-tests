#!/bin/bash
# T15 — 边界地址访问测试
# 测试 eMMC 在边界地址下的行为: 设备末尾、跨 4K Block 边界、
# 跨 erase block 边界、offset=0

TEST_ID="t15"
TEST_NAME="边界地址访问测试"
TEST_DESC="设备首尾/跨Block边界/零偏移 等边界条件的访问"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    # 获取设备扇区数
    local dev_name="${EMMC_DEV#/dev/}"
    local sectors=$(cat "/sys/block/${dev_name}/size" 2>/dev/null || echo "0")
    local size_bytes=$((sectors * 512))
    local size_gb=$(echo "scale=1; ${size_bytes}/1073741824" | bc 2>/dev/null || echo "?")
    info "设备大小: ${sectors} 扇区 = ${size_bytes} 字节 (~${size_gb}GB)"

    if [ "${sectors}" -le 0 ] || [ "${sectors}" = "0" ]; then
        fail "无法读取设备大小"
        return
    fi

    local last_lba=$((sectors - 1))
    local last_byte=$((size_bytes - 1))

    # ── Test A: 设备末尾边界 ──
    step "Test 15a: 末尾 16MB 边界访问"
    local tail_start=$((size_bytes - 16 * 1024 * 1024))
    local tail_start_gb=$(echo "scale=2; ${tail_start}/1073741824" | bc 2>/dev/null || echo "${tail_start}")
    info "访问范围: ${tail_start_gb}GB → 设备末尾 (${size_gb}GB)"

    progress "写入 16MB 到末尾..."
    local ref_file="${LOGDIR}/t15_tail.dat"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=16 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')

    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=16 seek=$((tail_start / (1024*1024))) oflag=direct 2>/dev/null || {
        fail "末尾写入失败!"; rm -f "${ref_file}"; return
    }
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    progress "从末尾回读..."
    local vfy_file="${LOGDIR}/t15_tail_vfy.dat"
    dd if="${EMMC_DEV}" of="${vfy_file}" bs=1M count=16 skip=$((tail_start / (1024*1024))) iflag=direct 2>/dev/null || {
        fail "末尾回读失败!"; rm -f "${ref_file}" "${vfy_file}"; return
    }
    local act_md5=$(md5sum "${vfy_file}" | awk '{print $1}')
    [ "${ref_md5}" = "${act_md5}" ] && pass "Test 15a: 末尾 16MB 数据正确" || \
        fail "Test 15a: 末尾数据损坏!"
    rm -f "${ref_file}" "${vfy_file}"

    # ── Test B: 起始偏移 (LBA 0) ──
    step "Test 15b: LBA 0 偏移访问"
    progress "写入并回读 LBA 0-8191 (4MB)..."
    local ref_file="${LOGDIR}/t15_lba0.dat"
    dd if=/dev/urandom of="${ref_file}" bs=4k count=1024 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')
    dd if="${ref_file}" of="${EMMC_DEV}" bs=4k count=1024 seek=0 oflag=direct 2>/dev/null || {
        fail "LBA0 写入失败!"; rm -f "${ref_file}"; return
    }
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    local vfy_file="${LOGDIR}/t15_lba0_vfy.dat"
    dd if="${EMMC_DEV}" of="${vfy_file}" bs=4k count=1024 skip=0 iflag=direct 2>/dev/null
    local act_md5=$(md5sum "${vfy_file}" | awk '{print $1}')
    [ "${ref_md5}" = "${act_md5}" ] && pass "Test 15b: LBA 0 边界正常" || \
        fail "Test 15b: LBA 0 数据损坏!"
    rm -f "${ref_file}" "${vfy_file}"

    # ── Test C: fio 跨边界访问 ──
    step "Test 15c: fio 跨 erase block 随机访问"
    progress "跨 0~4GB 范围随机访问 (60s)..."
    if run_fio "t15_cross_block" \
        --name=t15_cross --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 4) \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=randrw --rwmixread=50 \
        --bs=4k --verify=crc32c --verify_state_save=0 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 15c: 跨边界随机访问无错误"
    else
        local log="${LOGDIR}/fio_t15_cross_block.json"
        fail "Test 15c: 跨边界访问出错 (error=$(get_fio_error "${log}"))"
    fi

    # ── Test D: 跨 4K 非对齐访问 (512B) ──
    step "Test 15d: 非对齐访问 (512B)"
    progress "512B 粒度随机写 (60s)..."
    if run_fio "t15_unaligned" \
        --name=t15_unalign --filename="${EMMC_DEV}" --offset=$(pct_offset 47) --size=512M \
        --direct=1 --ioengine=psync --iodepth=1 --rw=randwrite --bs=512 \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 15d: 512B 非对齐访问正常"
    else
        local log="${LOGDIR}/fio_t15_unaligned.json"
        fail "Test 15d: 512B 访问出错 (error=$(get_fio_error "${log}"))"
    fi

    pass "边界地址测试完成"
}
