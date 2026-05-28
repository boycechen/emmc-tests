#!/bin/bash
# T20 — 全设备顺序遍历 (全盘扫描)
# 从 LBA 0 到最后一个 LBA 逐块读取
# 检测坏块、不可读扇区、读取超时区域
# 注意: 这是全盘非破坏性读测试, 不会清空数据

TEST_ID="t20"
TEST_NAME="全设备顺序遍历"
TEST_DESC="全盘范围顺序读取, 检测坏块和读取异常区域"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 从 LBA 0 到末尾逐段读取, 任何读失败都标志硬件问题.${C_RESET}"
    echo -e "${C_INFO}  注意: 这是只读测试, 不破坏已有数据.${C_RESET}"

    local dev_name="${EMMC_DEV#/dev/}"
    local sectors=$(cat "/sys/block/${dev_name}/size" 2>/dev/null || echo "0")
    if [ "${sectors}" -le 0 ]; then
        fail "无法获取设备大小"; return
    fi
    local size_mb=$((sectors / 2048))
    local size_gb=$(echo "scale=1; ${size_mb}/1024" | bc 2>/dev/null || echo "?")
    info "设备大小: ${size_mb}MB (~${size_gb}GB)"

    if ! ask_yes "全盘读扫描 (~${size_gb}GB, 可能耗时较长)? 建议在非繁忙系统上运行"; then
        warn "跳过 T20"; return
    fi

    # 使用 fio 分块顺序读, 记录读延迟
    step "全盘顺序读取 (分块 512MB)"
    progress "扫描中... 结果将记录到日志"

    local chunk_mb=512
    local chunks=$((size_mb / chunk_mb))
    local errors=0
    local slow_reads=0

    for ((c=0; c<chunks; c++)); do
        local off=$((c * chunk_mb))
        local pct=$(( (c * 100) / chunks ))
        printf "\r  ${C_PROGRESS}进度: ${pct}%% (${c}/${chunks} 块) 错误: ${errors}  慢读: ${slow_reads}${C_RESET}" >&2

        # 读 512MB 块, 记录延迟
        local chunk_file="${LOGDIR}/t20_chunk_${c}.json"
        fio --name=t20_scan --filename="${EMMC_DEV}" --offset="${off}M" --size="${chunk_mb}M" \
            --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=1M \
            --output="${chunk_file}" --output-format=json 2>/dev/null

        local fio_err=$(get_fio_error "${chunk_file}")
        if [ "${fio_err}" != "0" ] && [ "${fio_err}" != "unknown" ]; then
            ((errors++))
            info "块 ${c} (offset=${off}MB): 读错误 (error=${fio_err})"
            continue
        fi

        # 检查读延迟
        local lat=$(extract_fio_metric "${chunk_file}" "read_lat_ns")
        if [ -n "${lat}" ] && [ "${lat}" != "N/A" ] && [ "${lat}" -gt 1000000000 ] 2>/dev/null; then
            ((slow_reads++))
            local lat_ms=$(echo "${lat}/1000000" | bc 2>/dev/null)
            warn "块 ${c} (offset=${off}MB): 读延迟 ${lat_ms}ms (>1s)"
        fi
    done

    echo "" # 换行
    echo ""

    # 最终报告
    local pct_ok=$(echo "scale=1; (${chunks}-${errors})*100/${chunks}" | bc 2>/dev/null || echo "?")
    if [ "${errors}" -eq 0 ] && [ "${slow_reads}" -eq 0 ]; then
        pass "全盘遍历: ${chunks}/${chunks} 块正常"
    elif [ "${errors}" -eq 0 ]; then
        warn "全盘遍历: 无读错误, 但有 ${slow_reads} 个慢读块 (>1s)"
        info "这可能是正常的 GC 延迟, 建议结合 T7 延迟毛刺分析"
    else
        fail "全盘遍历: ${errors}/${chunks} 块有读错误, ${slow_reads} 个慢读块!"
        info "有读错误的块列表 (见日志):"
        grep -i "error\|读错误" "${LOGDIR}/results.log" 2>/dev/null | tail -10 | while IFS= read -r line; do warn "${line}"; done
    fi

    # 清理中间文件
    rm -f "${LOGDIR}"/t20_chunk_*.json
}
