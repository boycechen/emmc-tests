#!/bin/bash
# T23 — 写放大因子 (WAF) 估算
# 通过对比应用层写入量和实际 NAND 写入量来估算 WAF
# 高 WAF 说明内部 GC 效率低, 会提前耗尽管寿命
# 注意: 这是估算, 因为 eMMC 不暴露实际 NAND 写入计数

TEST_ID="t23"
TEST_NAME="写放大因子 (WAF) 估算"
TEST_DESC="通过写入性能趋势估算 WAF — 高 WAF 意味着低寿命"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 持续写入直至观察到性能下降.${C_RESET}"
    echo -e "${C_INFO}  当 eMMC 内部需要频繁 GC 时, 写性能会下降, 说明 WAF 升高.${C_RESET}"

    local waf_offset=$(pct_offset 50)
    local record_file="${LOGDIR}/waf_performance.log"

    pct_check "T23" 60 || { warn "设备空间不足, 跳过 T23"; return; }

    step "阶段写入 + 性能采样 (监测性能退化)"
    info "分 16 个阶段, 每阶段写 256MB, 记录性能变化"
    info "如果性能持续下降, 说明 WAF 较高"

    # 预填充区域 (使 GC 压力增大)
    progress "预填充区域 (增大 GC 压力)..."
    dd if=/dev/zero of="${EMMC_DEV}" bs=1M count=1024 seek=0 oflag=direct 2>/dev/null || true
    sync

    echo "# segment  write_iops  write_bw_KBps  write_lat_ns" > "${record_file}"
    local peak_iops=0
    local min_iops=99999999

    for seg in $(seq 0 15); do
        local seg_off="${waf_offset}+$((seg * 256))M"
        progress "阶段 ${seg}/15 — 写入 256MB..."

        fio --name=t23_waf --filename="${EMMC_DEV}" --offset="${seg_off}" --size=256M \
            --direct=1 --ioengine=libaio --iodepth=32 --rw=write --bs=4k \
            --output="${LOGDIR}/fio_t23_seg_${seg}.json" --output-format=json 2>/dev/null

        local wi=$(extract_fio_metric "${LOGDIR}/fio_t23_seg_${seg}.json" "write_iops")
        local wb=$(extract_fio_metric "${LOGDIR}/fio_t23_seg_${seg}.json" "write_bw")
        local wl=$(extract_fio_metric "${LOGDIR}/fio_t23_seg_${seg}.json" "write_lat_ns")

        echo "${seg}  ${wi}  ${wb}  ${wl}" >> "${record_file}"

        # 记录峰值/谷值
        if [ "${wi}" != "N/A" ]; then
            local wi_int=$(echo "${wi}" | cut -d. -f1)
            [ "${wi_int}" -gt "${peak_iops}" ] && peak_iops=${wi_int}
            [ "${wi_int}" -lt "${min_iops}" ] && min_iops=${wi_int}
        fi

        # 检查 fio 错误
        local err=$(get_fio_error "${LOGDIR}/fio_t23_seg_${seg}.json")
        if [ "${err}" != "0" ] && [ "${err}" != "unknown" ]; then
            fail "阶段 ${seg}: I/O 错误 (error=${err})!"
        fi
    done

    step "WAF 分析报告"
    if [ "${peak_iops}" -gt 0 ] && [ "${min_iops}" -gt 0 ] && [ "${peak_iops}" -ne "${min_iops}" ]; then
        local perf_drop=$(echo "scale=2; (${peak_iops}-${min_iops})*100/${peak_iops}" | bc 2>/dev/null)
        info "峰值 IOPS: ${peak_iops}, 谷值 IOPS: ${min_iops}"
        info "性能下降: ${perf_drop}%"

        if [ "$(echo "${perf_drop} > 30" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
            warn "性能下降 ${perf_drop}% (>30%) — WAF 可能偏高, GC 效率不足"
            info "建议: 定期执行 fstrim/discard 以降低 WAF"
        elif [ "$(echo "${perf_drop} > 15" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
            warn "性能下降 ${perf_drop}% — WAF 中等"
        else
            pass "性能波动 ${perf_drop}% — WAF 正常"
        fi
    else
        warn "无法计算 WAF (峰值=${peak_iops}, 谷值=${min_iops})"
    fi

    # 打印性能表
    echo ""
    cat "${record_file}" | column -t | while IFS= read -r line; do
        if echo "${line}" | grep -q "^#"; then
            info "${line}"
        else
            echo -e "${C_CMD}  ${line}${C_RESET}"
        fi
    done
}
