#!/bin/bash
# T25 — 全范围随机读取压力 (大范围读干扰)
# 在全设备范围内随机读取, 覆盖尽可能多的 NAND block
# 检测全局读干扰效应 + 随机区域读取一致性

TEST_ID="t25"
TEST_NAME="全范围随机读取"
TEST_DESC="全设备范围随机读取, 检测全局读干扰和一致性"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 在全设备随机地址上反复读取, 模拟重度使用场景.${C_RESET}"
    echo -e "${C_INFO}  可暴露固件地址映射错误、随机读取一致性缺陷.${C_RESET}"

    local dev_name="${EMMC_DEV#/dev/}"
    local sectors=$(cat "/sys/block/${dev_name}/size" 2>/dev/null || echo "0")
    if [ "${sectors}" -le 0 ]; then
        fail "无法获取设备大小, 使用 16GB 范围"
        local max_size="16G"
    else
        local size_bytes=$((sectors * 512))
        if [ "${size_bytes}" -gt $((40 * 1073741824)) ]; then
            local max_size="40G"  # 限制范围以节省时间
        else
            local max_size="${size_bytes}"
        fi
    fi
    info "随机读取范围: 0 ~ ${max_size}"

    step "全范围随机读 (300s, iodepth=32)"
    progress "运行中 (约 5 分钟)..."
    if run_fio "t25_fullscan_random" \
        --name=t25_fullrand --filename="${EMMC_DEV}" --offset=0 --size="${max_size}" \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randread --bs=4k \
        --runtime=300 --time_based --group_reporting; then
        pass "全范围随机读取: 无错误"
    else
        local log="${LOGDIR}/fio_t25_fullscan_random.json"
        local err=$(get_fio_error "${log}")
        fail "全范围随机读出现错误! (error=${err})"
        grep -i 'error\|EIO' "${log}" 2>/dev/null | head -5 | while IFS= read -r line; do
            info "  详情: ${line}"
        done
    fi

    # 统计
    local log="${LOGDIR}/fio_t25_fullscan_random.json"
    local ri=$(extract_fio_metric "${log}" "read_iops")
    local rb=$(extract_fio_metric "${log}" "read_bw")
    local rl=$(extract_fio_metric "${log}" "read_lat_ns")
    local total_read=$(grep -oP '"io_bytes":\s*\K[0-9]+' "${log}" | tail -1 2>/dev/null || echo "N/A")
    if [ "${total_read}" != "N/A" ]; then
        local total_read_gb=$(echo "scale=2; ${total_read}/1073741824" | bc 2>/dev/null || echo "${total_read}")
        info "总读取量: ${total_read_gb}GB"
    fi
    info "平均: ${ri} IOPS / ${rb} KB/s / ${rl}ns 延迟"
}
