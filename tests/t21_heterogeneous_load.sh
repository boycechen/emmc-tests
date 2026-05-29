#!/bin/bash
# T21 — 多线程混合负载 (异质性压力)
# 不同线程运行不同工作负载: 大块顺序读 + 小块随机写 + 元数据密集访问
# 模拟真实多任务场景, 测试控制器的任务调度和优先级管理

TEST_ID="t21"
TEST_NAME="多线程混合负载"
TEST_DESC="不同线程: 大块顺序读/小块随机写/密集小写, 模拟真实多任务"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 同时运行 3 种不同类型的 I/O, 暴露控制器调度缺陷.${C_RESET}"
    echo -e "${C_INFO}  - 线程1: 1M 大块顺序读 (高带宽)${C_RESET}"
    echo -e "${C_INFO}  - 线程2: 512B 极小块随机写 (高 IOPS)${C_RESET}"
    echo -e "${C_INFO}  - 线程3: 4K 混合读写 (典型负载)${C_RESET}"

    step "3 线程异质性负载 (180s)"
    progress "运行中 (约 3 分钟)... 异质性最高, 最易暴露调度 bug"

    local base_pct=50
    pct_check "T21" $((base_pct + 15)) || { warn "设备空间不足, 跳过 T21"; return; }

    # 使用 fio 的 3 个独立 job 定义 (每个 --name 开始一个新 job)
    if run_fio "t21_hetero" \
        --thread=1 --direct=1 --ioengine=libaio \
        --runtime=180 --time_based --group_reporting \
        \
        --name=t21_seqrd --filename="${EMMC_DEV}" \
        --bs=1M --size=$(pct_size 3) --offset=$(pct_offset ${base_pct}) \
        --rw=read --iodepth=8 \
        \
        --name=t21_tinywr --filename="${EMMC_DEV}" \
        --bs=512 --size=512M --offset=$(pct_offset $((base_pct + 5))) \
        --rw=randwrite --iodepth=16 \
        \
        --name=t21_mix --filename="${EMMC_DEV}" \
        --bs=4k --size=$(pct_size 2) --offset=$(pct_offset $((base_pct + 8))) \
        --rw=randrw --rwmixread=70 --iodepth=32; then
        pass "异质性负载运行完毕, 无错误"
    else
        local log="${LOGDIR}/fio_t21_hetero.json"
        local err=$(get_fio_error "${log}")
        fail "异质性负载出错! (error=${err}) — 控制器任务调度异常!"
        grep -i 'error\|EIO\|fail' "${log}" 2>/dev/null | head -5 | while IFS= read -r line; do
            info "  详情: ${line}"
        done
    fi

    step "各线程性能报告"
    local log="${LOGDIR}/fio_t21_hetero.json"
    if [ -f "${log}" ]; then
        local ri=$(extract_fio_metric "${log}" "read_iops")
        local wi=$(extract_fio_metric "${log}" "write_iops")
        local rb=$(extract_fio_metric "${log}" "read_bw")
        local wb=$(extract_fio_metric "${log}" "write_bw")
        info "综合: R_IOPS=${ri} W_IOPS=${wi} R_BW=${rb}KB/s W_BW=${wb}KB/s"
    fi
}
