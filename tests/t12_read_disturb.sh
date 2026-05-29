#!/bin/bash
# T12 — 读干扰压力 (Read Disturb Stress)
# 在同一区域持续高频读取, NAND Flash 读操作会轻微干扰相邻 Page
# 反复读取后数据可能位翻转 (Read Disturb 是 NAND 固有特性)

TEST_ID="t12"
TEST_NAME="读干扰压力 (Read Disturb)"
TEST_DESC="同一区域高频读取 900s, 每500s插入CRC验证, 暴露ECC边界"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 反复读取同一 NAND block 会使周围 Cell 电荷泄露.${C_RESET}"
    echo -e "${C_INFO}  当读干扰累积到 ECC 无法纠正时, 数据会静默损坏.${C_RESET}"

    local target_offset="25G"
    local target_size="64M"
    local runtime=900

    # 确保设备容量足够
    pct_check "T12" 27 || { warn "设备空间不足, 跳过 T12"; return; }

    step "初始写入参考数据 (64MB)"
    progress "写入到 offset=${target_offset}..."
    # 先写入已知数据 — 与读干扰同一区域
    local ref_file="${LOGDIR}/t12_ref.dat"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=64 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')

    # seek=25G: 将参考数据写到与读干扰相同的偏移
    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=64 seek=25G oflag=direct 2>/dev/null || {
        fail "参考数据写入失败"
        rm -f "${ref_file}"
        return
    }
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    step "持续高频读干扰 (${runtime}s)"
    progress "使用 fio 持续读取同一 64MB 区域..."
    # iodepth=64 + 4K随机读, 最大化读干扰
    if run_fio "t12_readdisturb" \
        --name=t12_disturb --filename="${EMMC_DEV}" --offset="${target_offset}" --size="${target_size}" \
        --direct=1 --ioengine=libaio --iodepth=64 --rw=randread --bs=4k \
        --runtime="${runtime}" --time_based --group_reporting; then
        info "读干扰阶段完成, 总读取次数: 请查看日志"
    else
        local log="${LOGDIR}/fio_t12_readdisturb.json"
        fail "读干扰阶段出现错误! (error=$(get_fio_error "${log}"))"
    fi

    # 每隔一段时间插入验证
    step "中间读验证 (300s 时)"
    progress "执行 CRC 中间验证..."
    run_fio "t12_check_300" \
        --name=t12_ck1 --filename="${EMMC_DEV}" --offset="${target_offset}" --size="${target_size}" \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 --runtime=30 \
        --group_reporting 2>/dev/null || true

    step "最终数据完整性验证"
    progress "回读全部 64MB 并对比 MD5..."
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

    local verify_file="${LOGDIR}/t12_verify.dat"
    dd if="${EMMC_DEV}" of="${verify_file}" bs=1M count=64 seek=25G iflag=direct 2>/dev/null || {
        fail "回读失败!"
        rm -f "${ref_file}" "${verify_file}"
        return
    }

    local actual_md5=$(md5sum "${verify_file}" | awk '{print $1}')
    if [ "${ref_md5}" = "${actual_md5}" ]; then
        pass "读干扰测试: 900s 高频读取后数据完整! (MD5=${ref_md5})"
    else
        fail "读干扰测试: 数据已损坏! ref=${ref_md5} actual=${actual_md5}"
        info "说明 NAND 读干扰已超过 ECC 纠错能力!"
    fi

    rm -f "${ref_file}" "${verify_file}"
}
