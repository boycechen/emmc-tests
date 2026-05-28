#!/bin/bash
# T30 — 温复位 + 初始化压力
# 在多线程 I/O 进行中时发送 eMMC 复位, 然后恢复 I/O
# 模拟系统在 I/O 进行时的意外复位场景

TEST_ID="t30"
TEST_NAME="温复位 + I/O 压力"
TEST_DESC="I/O 忙时执行 eMMC 复位, 检测固件热恢复能力"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 在持续 I/O 进行中发送 MMC_RESET.${C_RESET}"
    echo -e "${C_INFO}  模拟系统在忙时意外复位, 检测 eMMC 固件恢复能力.${C_RESET}"

    if [ "${HAS_MMC_UTILS}" = false ]; then
        warn "需要 mmc-utils, 跳过 T30"
        return
    fi

    if ! mmc --help 2>&1 | grep -qi reset; then
        warn "mmc-utils 不支持 reset"
        return
    fi

    step "Test 30a: 写入参考数据"
    local ref_file="${LOGDIR}/t30_ref.dat"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=128 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')
    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=128 seek=0 oflag=direct 2>/dev/null || {
        fail "参考数据写入失败"; rm -f "${ref_file}"; return
    }
    sync

    step "Test 30b: I/O 忙时复位"
    progress "启动后台持续 I/O..."
    fio --name=t30_bg --filename="${EMMC_DEV}" --offset=0 --size=$(pct_size 3) \
        --direct=1 --ioengine=libaio --iodepth=32 --rw=randrw --rwmixread=50 \
        --bs=4k --runtime=60 --time_based --output=/dev/null 2>/dev/null &
    local bg_pid=$!

    sleep 5  # 等待 I/O 稳定

    progress "在 I/O 忙时发送 mmc reset..."
    local reset_out
    reset_out=$(mmc reset "${EMMC_DEV}" 2>&1)
    local rc=$?
    info "mmc reset: exit=${rc}, output=${reset_out}"

    if [ "${rc}" -ne 0 ]; then
        warn "复位命令失败 (exit=${rc}), 可能内核不支持"
        kill "${bg_pid}" 2>/dev/null || true
        wait "${bg_pid}" 2>/dev/null || true
        rm -f "${ref_file}"; return
    fi

    info "复位后等待 3s 让设备重新初始化..."
    sleep 3

    # 停止后台 I/O
    kill "${bg_pid}" 2>/dev/null || true
    wait "${bg_pid}" 2>/dev/null || true

    step "Test 30c: 复位后数据完整性"
    progress "回读参考数据..."
    local vfy_file="${LOGDIR}/t30_vfy.dat"
    dd if="${EMMC_DEV}" of="${vfy_file}" bs=1M count=128 iflag=direct 2>/dev/null || {
        fail "复位后回读失败!"; rm -f "${ref_file}" "${vfy_file}"; return
    }
    local vfy_md5=$(md5sum "${vfy_file}" | awk '{print $1}')

    if [ "${ref_md5}" = "${vfy_md5}" ]; then
        pass "I/O 忙时复位后数据完整 — eMMC 热恢复正常"
    else
        fail "I/O 忙时复位导致数据损坏! (${ref_md5} vs ${vfy_md5})"
    fi

    rm -f "${ref_file}" "${vfy_file}"

    step "Test 30d: 复位后重新 I/O 测试"
    progress "复位后新写入 + CRC 校验 (60s)..."
    if run_fio "t30_post_reset" \
        --name=t30_postrst --filename="${EMMC_DEV}" --offset=0 --size=512M \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=60 --time_based --group_reporting; then
        pass "复位后新 I/O 完全正常"
    else
        local log="${LOGDIR}/fio_t30_post_reset.json"
        fail "复位后 I/O 出错 (error=$(get_fio_error "${log}"))"
    fi
}
