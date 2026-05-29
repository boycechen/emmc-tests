#!/bin/bash
# T24 — 密集短间隔数据保持测试
# 写入数据后以递增间隔回读 (10s / 60s / 300s)
# 检测短时间内的数据保持退化, 暴露 NAND Cell 弱保持特性

TEST_ID="t24"
TEST_NAME="短间隔数据保持退化"
TEST_DESC="写入后10s/60s/300s分阶段回读, 检测NAND Cell电荷泄露"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 对 NAND Cell 写入后, 电荷会随时间缓慢泄露.${C_RESET}"
    echo -e "${C_INFO}  弱 Cell 在极短时间内就会产生位翻转 (数据保持错误).${C_RESET}"

    local data_pct=50

    pct_check "T24" 55 || { warn "设备空间不足, 跳过 T24"; return; }

    step "Test 24a: 写入参考数据"
    local ref_file="${LOGDIR}/t24_ref.dat"
    local ref_md5_file="${LOGDIR}/t24_ref.md5"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=64 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')
    echo "${ref_md5}" > "${ref_md5_file}"

    # 写入 4 份相同数据到不同区域
    info "写入 4 份副本到不同区域 (等待时间递增验证)"
    local base_seek=$((DEVICE_SIZE_MB * data_pct / 100))
    for copy in 1 2 3 4; do
        local seek_val=$((base_seek + (copy-1) * 128))
        local off_desc="${base_seek}M+$(( (copy-1) * 128 ))M"
        dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=64 seek="${seek_val}" oflag=direct 2>/dev/null || {
            fail "副本 ${copy} 写入失败"; rm -f "${ref_file}"; return
        }
    done
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    pass "参考数据已写入 (4 副本)"

    # 分阶段回读 — 每阶段读不同的副本
    local intervals=(10 60 300)
    local stage=1

    for interval in "${intervals[@]}"; do
        info "等待 ${interval}s..."
        sleep "${interval}"

        # 每阶段读对应的副本: stage 1→copy 1, stage 2→copy 2, stage 3→copy 3
        local read_seek=$((base_seek + (stage-1) * 128))
        local read_desc="${base_seek}M+$(( (stage-1) * 128 ))M"

        step "Test 24b: 阶段 ${stage} — 写入后 ${interval}s 回读 (offset=${read_desc})"
        local vfy_file="${LOGDIR}/t24_vfy_${interval}s.dat"
        dd if="${EMMC_DEV}" of="${vfy_file}" bs=1M count=64 skip="${read_seek}" iflag=direct 2>/dev/null || {
            fail "阶段 ${stage}: 回读失败!"; rm -f "${vfy_file}"; ((stage++)); continue
        }
        local vfy_md5=$(md5sum "${vfy_file}" | awk '{print $1}')

        if [ "${vfy_md5}" = "${ref_md5}" ]; then
            pass "阶段 ${stage} (${interval}s): 数据完整"
        else
            local diff_bytes=$(cmp -l "${ref_file}" "${vfy_file}" 2>/dev/null | wc -l)
            fail "阶段 ${stage} (${interval}s): 数据退化! 差异字节数: ${diff_bytes}"
            info "  参考 MD5: ${ref_md5}"
            info "  实际 MD5: ${vfy_md5}"
            if [ "${diff_bytes}" -gt 0 ] && [ "${diff_bytes}" -lt 100 ]; then
                cmp -l "${ref_file}" "${vfy_file}" 2>/dev/null | head -10 | while IFS= read -r line; do
                    info "  diff: ${line}"
                done
            fi
        fi
        rm -f "${vfy_file}"
        ((stage++))
    done

    rm -f "${ref_file}"

    step "Test 24c: 热温数据保持 (写入后紧接大量读干扰)"
    local hot_file="${LOGDIR}/t24_hot_ref.dat"
    local hot_offset=$((base_seek + 4 * 128))  # copy 4 之后 (base_seek+512M)
    dd if=/dev/urandom of="${hot_file}" bs=1M count=16 2>/dev/null
    local hot_md5=$(md5sum "${hot_file}" | awk '{print $1}')

    dd if="${hot_file}" of="${EMMC_DEV}" bs=1M count=16 seek="${hot_offset}" oflag=direct 2>/dev/null
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    # 对相邻区域做大量读干扰 (hot_offset + 16M 处)
    progress "对相邻区域做 60s 高频读干扰..."
    local disturb_offset=$((hot_offset + 16))
    fio --name=t24_hotdisturb --filename="${EMMC_DEV}" --offset="${disturb_offset}M" --size=64M \
        --direct=1 --ioengine=libaio --iodepth=64 --rw=randread --bs=4k \
        --runtime=60 --time_based --output=/dev/null 2>/dev/null

    # 回读热温数据
    local hot_vfy="${LOGDIR}/t24_hot_vfy.dat"
    dd if="${EMMC_DEV}" of="${hot_vfy}" bs=1M count=16 skip="${hot_offset}" iflag=direct 2>/dev/null
    local hot_actual=$(md5sum "${hot_vfy}" | awk '{print $1}')

    if [ "${hot_md5}" = "${hot_actual}" ]; then
        pass "Test 24c: 热温数据 + 相邻读干扰后数据完整"
    else
        fail "Test 24c: 热温数据被相邻读干扰损坏!"
    fi

    rm -f "${hot_file}" "${hot_vfy}"
}
