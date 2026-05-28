#!/bin/bash
# T17 — 混合 IO 粒度测试
# 512B / 4K / 64K / 1M 四种粒度交替进行
# 暴露 eMMC 对不同传输粒度的处理能力
# 某些 eMMC 在小粒度下表现正常, 大粒度下有问题 (或反之)

TEST_ID="t17"
TEST_NAME="混合 IO 粒度测试"
TEST_DESC="512B/4K/64K/1M 交替混合读写, 检测粒度适配缺陷"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 快速切换 IO 粒度迫使控制器调整内部缓冲区策略.${C_RESET}"
    echo -e "${C_INFO}  某些 eMMC 固件在粒度切换时存在缓冲区泄漏或对齐 bug.${C_RESET}"

    local tests=(
        "512b:512:randwrite:60"
        "4k:4k:randwrite:60"
        "64k:64k:randwrite:60"
        "1m:1m:write:60"
        "512b_mix:512:randrw:60"
        "4k_mix:4k:randrw:60"
        "64k_mix:64k:randrw:60"
        "1m_seq:1m:rw:60"
    )

    local idx=1
    for spec in "${tests[@]}"; do
        local name="${spec%%:*}"
        local bs="${spec#*:}"; bs="${bs%%:*}"
        local rw="${spec#*:*:}"; rw="${rw%%:*}"
        local rt="${spec##*:}"

        step "[${idx}/${#tests[@]}] bs=${bs} rw=${rw} (${rt}s)"
        progress "运行中..."
        if run_fio "t17_${name}" \
            --name=t17_${name} --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
            --direct=1 --ioengine=libaio --iodepth=16 --rw="${rw}" --bs="${bs}" \
            --rwmixread=50 --verify=crc32c --verify_state_save=0 \
            --runtime="${rt}" --time_based --group_reporting; then
            info "bs=${bs}: OK"
        else
            local log="${LOGDIR}/fio_t17_${name}.json"
            fail "bs=${bs}: 出错! (error=$(get_fio_error "${log}"))"
        fi
        ((idx++))
    done

    pass "混合粒度测试完成"

    step "粒度性能对比"
    echo -e "\n${C_INFO}  粒度       IOPS(R)    IOPS(W)    BW(R)KB/s  BW(W)KB/s   Lat(R)ns   Lat(W)ns${C_RESET}"
    echo -e "${C_INFO}  ───────────────────────────────────────────────────────────────────────────${C_RESET}"
    for spec in "${tests[@]}"; do
        local name="${spec%%:*}"
        local bs="${spec#*:}"; bs="${bs%%:*}"
        local log="${LOGDIR}/fio_t17_${name}.json"
        [ ! -f "${log}" ] && continue
        local ri=$(extract_fio_metric "${log}" "read_iops")
        local wi=$(extract_fio_metric "${log}" "write_iops")
        local rb=$(extract_fio_metric "${log}" "read_bw")
        local wb=$(extract_fio_metric "${log}" "write_bw")
        local rl=$(extract_fio_metric "${log}" "read_lat_ns")
        local wl=$(extract_fio_metric "${log}" "write_lat_ns")
        printf "  %-8s  %8s  %8s  %9s  %9s  %9s  %9s\n" \
            "${bs}" "${ri}" "${wi}" "${rb}" "${wb}" "${rl}" "${wl}" | while IFS= read -r line; do info "${line}"; done
    done
}
