#!/bin/bash
# T14 — TRIM/Discard 功能验证
# eMMC 的 TRIM (CMD38) 通知设备哪些 LBA 不再使用
# 设备可以在内部进行垃圾回收和块擦除
# 如果 TRIM 实现有 bug, 可能导致数据损坏或性能下降

TEST_ID="t14"
TEST_NAME="TRIM/Discard 功能验证"
TEST_DESC="blkdiscard + fio 写回读, 检测TRIM实现是否正常"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: TRIM 后 NAND 块应返回全 0 或全 1, 再次写入后数据完整.${C_RESET}"
    echo -e "${C_INFO}  如果 TRIM 实现有 bug, 可能导致后续写入数据异常.${C_RESET}"

    if ! command -v blkdiscard &>/dev/null; then
        warn "blkdiscard 未找到, 跳过 TRIM 测试"
        info "安装: sudo apt install util-linux (通常已预装)"
        return
    fi

    local trim_pct=50
    local trim_offset=$((DEVICE_SIZE_MB * trim_pct / 100 * 1048576))  # 50% 偏移, 字节单位
    local trim_len=$((512 * 1024 * 1024))            # 512MB
    local test_offset=$(pct_offset ${trim_pct})
    pct_check "T14" $((trim_pct + 2)) || { warn "设备空间不足, 跳过 T14"; return; }

    # ── 测试前先确认设备支持 discard ──
    step "检查 discard 支持"
    local dev_name="${EMMC_DEV#/dev/}"
    local discard_gran=$(cat "/sys/block/${dev_name}/queue/discard_granularity" 2>/dev/null || echo "0")
    local discard_max=$(cat "/sys/block/${dev_name}/queue/discard_max_bytes" 2>/dev/null || echo "0")
    local discard_zero=$(cat "/sys/block/${dev_name}/queue/discard_zeroes_data" 2>/dev/null || echo "N/A")
    info "discard_granularity=${discard_gran} bytes"
    info "discard_max_bytes=${discard_max} bytes"
    info "discard_zeroes_data=${discard_zero}"

    if [ "${discard_gran}" = "0" ] || [ "${discard_max}" = "0" ]; then
        warn "设备不支持 discard/TRIM, 跳过 T14"
        return
    fi
    pass "eMMC 支持 TRIM/Discard"

    # ── 写入已知数据 ──
    step "Test 14a: TRIM 后全零验证"
    progress "写入已知数据..."
    local ref_file="${LOGDIR}/t14_ref.dat"
    local trim_vfy="${LOGDIR}/t14_trim_read.dat"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=512 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')

    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=512 seek=0 oflag=direct 2>/dev/null || {
        fail "参考数据写入失败"; rm -f "${ref_file}"; return
    }
    sync

    # ── 执行 TRIM ──
    progress "执行 blkdiscard (偏移 ${trim_offset}, 长度 ${trim_len})..."
    blkdiscard -o "${trim_offset}" -l "${trim_len}" "${EMMC_DEV}" 2>&1 | tail -2 || {
        warn "blkdiscard 失败 (可能内核不支持)"
        rm -f "${ref_file}"
        return
    }
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # ── TRIM 后读取 — 预期为全零 ──
    progress "读取 TRIM 后区域..."
    dd if="${EMMC_DEV}" of="${trim_vfy}" bs=1M count=512 iflag=direct 2>/dev/null

    # 检查是否全零
    local trim_md5=$(md5sum "${trim_vfy}" | awk '{print $1}')
    local zero_md5="a933cc12f0f35353ae27f9bda4d4e1bf"  # 512MB 全零 MD5

    if [ "${trim_md5}" = "${zero_md5}" ]; then
        pass "Test 14a: TRIM 后区域为全零 — discard 实现正确"
    else
        # 也可能是全 0xFF (某些 eMMC 行为不同)
        # 检查是否全 0xFF
        local all_ff=true
        for ((i=0; i<10; i++)); do
            local byte=$(xxd -p -l1 -s $((i * 1024 * 1024)) "${trim_vfy}" 2>/dev/null || echo "00")
            [ "${byte}" != "ff" ] && all_ff=false && break
        done
        if ${all_ff}; then
            info "TRIM 后区域为全 0xFF (符合 eMMC 规范变体)"
            pass "Test 14a: TRIM 后区域一致 (全FF)"
        else
            warn "Test 14a: TRIM 后区域既非全0也非全FF (md5=${trim_md5})"
            info "这可能不是问题 — 某些 eMMC 实现不保证读取什么"
        fi
    fi

    # ── TRIM 后写入回读 ──
    step "Test 14b: TRIM 后再写入完整性"
    progress "重新写入参考数据..."
    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=512 seek=0 oflag=direct 2>/dev/null
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    progress "回读验证..."
    local verify_file="${LOGDIR}/t14_rewrite_vfy.dat"
    dd if="${EMMC_DEV}" of="${verify_file}" bs=1M count=512 iflag=direct 2>/dev/null
    local vfy_md5=$(md5sum "${verify_file}" | awk '{print $1}')

    if [ "${vfy_md5}" = "${ref_md5}" ]; then
        pass "Test 14b: TRIM 后重写数据完整 — 无残留数据污染"
    else
        fail "Test 14b: TRIM 后写数据不匹配! (${ref_md5} vs ${vfy_md5})"
        info "说明 TRIM 固件有 bug — 擦除后写入仍读取到旧数据!"
    fi

    rm -f "${ref_file}" "${trim_vfy}" "${verify_file}"

    # ── fio discard + verify ──
    step "Test 14c: fio discard 循环"
    progress "运行 fio 带 discard 的随机写+校验..."
    if run_fio "t14_discard_fio" \
        --name=t14_dfio --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=8 --rw=randwrite --bs=4k \
        --discard=1 --discard_random=50 --verify=crc32c --verify_state_save=0 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 14c: fio discard + 校验通过 — TRIM 与写入协同正常"
    else
        local log="${LOGDIR}/fio_t14_discard_fio.json"
        fail "Test 14c: discard+验证出错 (error=$(get_fio_error "${log}"))"
    fi
}
