#!/bin/bash
# T16 — I/O 深度冲击测试
# 在 iodepth=1/8/32/128 之间快速切换
# 暴露 eMMC 控制器的队列管理、内部 DMA 调度问题

TEST_ID="t16"
TEST_NAME="I/O 深度冲击测试"
TEST_DESC="iodepth 1/8/32/128 交替切换, 检测队列管理缺陷"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 深度切换迫使 eMMC 控制器重新分配内部 DMA 通道.${C_RESET}"
    echo -e "${C_INFO}  队列管理有 bug 的设备在高→低深度切换时会出现超时.${C_RESET}"

    local depths=(1 8 1 32 1 64 1 128 1 64 1 32 1 8 1)
    local idx=1

    step "深度循环: ${depths[*]}"
    for d in "${depths[@]}"; do
        progress "[${idx}/${#depths[@]}] iodepth=${d} 随机读写 (30s)..."
        if run_fio "t16_depth_${d}" \
            --name=t16_d${d} --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
            --direct=1 --ioengine=libaio --iodepth="${d}" --rw=randrw --rwmixread=50 \
            --bs=4k --runtime=30 --time_based --group_reporting; then
            info "depth=${d}: OK"
        else
            local log="${LOGDIR}/fio_t16_depth_${d}.json"
            fail "depth=${d}: 出错! (error=$(get_fio_error "${log}"))"
        fi
        ((idx++))
    done

    pass "I/O 深度冲击完成"

    step "深度冲击性能变化报告"
    echo -e "\n${C_INFO}  深度     IOPS(R)    IOPS(W)      BW(R)      BW(W)${C_RESET}"
    echo -e "${C_INFO}  ─────────────────────────────────────────────────${C_RESET}"
    for d in 1 8 32 64 128; do
        local log="${LOGDIR}/fio_t16_depth_${d}.json"
        [ ! -f "${log}" ] && continue
        local ri=$(extract_fio_metric "${log}" "read_iops")
        local wi=$(extract_fio_metric "${log}" "write_iops")
        local rb=$(extract_fio_metric "${log}" "read_bw")
        local wb=$(extract_fio_metric "${log}" "write_bw")
        printf "  %5s    %8s  %8s  %8s  %8s\n" "${d}" "${ri}" "${wi}" "${rb}" "${wb}" | while IFS= read -r line; do info "${line}"; done
    done
}
