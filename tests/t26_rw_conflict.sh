#!/bin/bash
# T26 — 同时读写同一 LBA (读写冲突)
# 对同一 LBA 同时进行读写操作, 检测 eMMC 内部读写冲突处理
# 正常设备应保证读操作返回旧数据或新数据, 但不能返回半损坏数据

TEST_ID="t26"
TEST_NAME="读写冲突测试 (同一 LBA)"
TEST_DESC="同时对同一 LBA 读写, 检测内部一致性"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 写线程和读线程同时操作同一 LBA.${C_RESET}"
    echo -e "${C_INFO}  eMMC 应提供一致性保证: 读返回完整旧数据或完整新数据.${C_RESET}"

    local conflict_offset=$(pct_offset 50)
    local conflict_size=$(pct_size 3)
    pct_check "T26" 55 || { warn "设备空间不足, 跳过 T26"; return; }

    step "并发读写同一范围 (120s)"
    progress "使用 numjobs=2 (一个写、一个读) 竞争同一 LBA..."

    if run_fio "t26_rw_conflict" \
        --name=t26_writer --filename="${EMMC_DEV}" --offset="${conflict_offset}" --size="${conflict_size}" \
        --direct=1 --ioengine=libaio \
        --thread --numjobs=2 \
        --runtime=120 --time_based --group_reporting \
        \
        --jobname=writer --rw=write --bs=4k --iodepth=16 \
        --verify=crc32c --verify_state_save=0 \
        \
        --jobname=reader --rw=randread --bs=4k --iodepth=32; then
        pass "并发读写同一 LBA: 无一致性错误"
    else
        local log="${LOGDIR}/fio_t26_rw_conflict.json"
        local err=$(get_fio_error "${log}")
        if [ "${err}" != "0" ]; then
            fail "读写冲突出现错误! (error=${err})"
            info "从同一 LBA 同时读写返回数据不一致 — 可能存在读写冲突 bug!"
        else
            warn "读写冲突 exit code 非0但 fio error=0, 手动检查日志"
        fi
    fi

    step "验证最终数据完整性"
    progress "回读并 CRC 校验..."
    if run_fio "t26_final_verify" \
        --name=t26_vfy --filename="${EMMC_DEV}" --offset="${conflict_offset}" --size="${conflict_size}" \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=read --bs=4k \
        --verify=crc32c --verify_only --verify_state_save=0 --group_reporting; then
        pass "最终数据 CRCC 校验通过"
    else
        local log="${LOGDIR}/fio_t26_final_verify.json"
        fail "最终数据损坏! (error=$(get_fio_error "${log}"))"
    fi
}
