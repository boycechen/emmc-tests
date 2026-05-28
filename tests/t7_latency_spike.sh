#!/bin/bash
# T7 — 延迟毛刺检测 (P50/P90/P99/P99.9/P99.99)
# iodepth=1, 测量 GC 暂停导致的极端延迟

TEST_ID="t7"
TEST_NAME="延迟毛刺检测"
TEST_DESC="P50~P99.99 延迟分布, 发现固件GC暂停"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    step "4K 随机读延迟 (60s)"
    progress "运行中..."
    run_fio "t7_readlat" \
        --name=t7_readlat --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=1 --rw=randread --bs=4k \
        --runtime=60 --time_based --lat_percentiles=1 \
        --percentile_list=50:90:99:99.9:99.99 --group_reporting || true

    step "4K 随机写延迟 (60s)"
    progress "运行中..."
    run_fio "t7_writelat" \
        --name=t7_writelat --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 2) \
        --direct=1 --ioengine=libaio --iodepth=1 --rw=randwrite --bs=4k \
        --runtime=60 --time_based --lat_percentiles=1 \
        --percentile_list=50:90:99:99.9:99.99 --group_reporting || true

    step "延迟分析报告"
    echo -e "\n${C_INFO}  方向     P50       P90       P99      P99.9     P99.99${C_RESET}"
    echo -e "${C_INFO}  ─────────────────────────────────────────────────────────${C_RESET}"

    for op in read write; do
        local logfile="${LOGDIR}/fio_t7_${op}lat.json"
        local p50=$(extract_fio_latency "${logfile}" "50.000000")
        local p90=$(extract_fio_latency "${logfile}" "90.000000")
        local p99=$(extract_fio_latency "${logfile}" "99.000000")
        local p999=$(extract_fio_latency "${logfile}" "99.900000")
        local p9999=$(extract_fio_latency "${logfile}" "99.990000")

        local line=$(printf "  %-7s %s %s %s %s %s" \
            "${op^^}" \
            "$(fmt_latency "${p50}")" "$(fmt_latency "${p90}")" \
            "$(fmt_latency "${p99}")" "$(fmt_latency "${p999}")" "$(fmt_latency "${p9999}")")
        info "${line}"

        local p999_int=0
        [ "${p999}" != "N/A" ] && [ "${p999}" != "null" ] && p999_int=$(echo "${p999}" | cut -d. -f1)
        if [ "${p999_int}" -gt 100000000 ] 2>/dev/null; then
            fail "${op^^} P99.9 > 100ms — 严重GC暂停!"
        elif [ "${p999_int}" -gt 50000000 ] 2>/dev/null; then
            warn "${op^^} P99.9 > 50ms — 明显GC抖动"
        else
            pass "${op^^} 延迟正常, 无严重毛刺"
        fi
    done
}
