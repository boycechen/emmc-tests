#!/bin/bash
# T22 — eMMC Reset 恢复测试
# 通过 mmc-utils 发送软复位, 复位后立即读写验证
# 检测 eMMC 固件在复位后的状态恢复是否完整

TEST_ID="t22"
TEST_NAME="eMMC Reset 恢复测试"
TEST_DESC="软复位后立即读写, 检测固件状态恢复完整性"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 发送 MMC_RESET 命令, eMMC 应恢复到初始状态.${C_RESET}"
    echo -e "${C_INFO}  复位后无法正常读写的说明固件状态机有缺陷.${C_RESET}"

    if [ "${HAS_MMC_UTILS}" = false ]; then
        warn "需要 mmc-utils, 安装: sudo apt install mmc-utils"
        return
    fi

    # 检查 mmc 是否支持 reset
    if ! mmc --help 2>&1 | grep -qi reset; then
        warn "当前 mmc-utils 版本不支持 reset 命令, 跳过 T22"
        return
    fi

    step "Test 22a: 复位前写入参考数据"
    local ref_file="${LOGDIR}/t22_ref.dat"
    local vfy_file="${LOGDIR}/t22_vfy.dat"
    dd if=/dev/urandom of="${ref_file}" bs=1M count=64 2>/dev/null
    local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')
    dd if="${ref_file}" of="${EMMC_DEV}" bs=1M count=64 seek=40 oflag=direct 2>/dev/null || {
        fail "参考数据写入失败"; rm -f "${ref_file}"; return
    }
    sync
    pass "参考数据已写入"

    step "Test 22b: 执行 eMMC 软复位"
    progress "发送 MMC_RESET..."
    local reset_out
    reset_out=$(mmc reset "${EMMC_DEV}" 2>&1)
    local rc=$?
    info "mmc reset 输出: ${reset_out}"

    if [ "${rc}" -ne 0 ]; then
        warn "mmc reset 命令失败 (exit=${rc})"
        info "这可能是内核驱动不支持 MMC_RESET, 非硬件问题"
        rm -f "${ref_file}"
        return
    fi

    info "复位成功, 等待 2s 让设备重新初始化..."
    sleep 2

    step "Test 22c: 复位后回读验证"
    progress "读取之前写入的数据..."
    dd if="${EMMC_DEV}" of="${vfy_file}" bs=1M count=64 skip=40 iflag=direct 2>/dev/null || {
        fail "复位后读取失败! — eMMC 固件复位异常!"
        rm -f "${ref_file}" "${vfy_file}"; return
    }
    local vfy_md5=$(md5sum "${vfy_file}" | awk '{print $1}')
    [ "${ref_md5}" = "${vfy_md5}" ] && \
        pass "复位后数据完整 (MD5=${ref_md5}) — eMMC 复位恢复正常" || \
        fail "复位后数据损坏! (${ref_md5} vs ${vfy_md5})"

    rm -f "${ref_file}" "${vfy_file}"

    step "Test 22d: 复位后立即 fio CRC 验证"
    progress "运行 fio 随机写+CRC 校验 (60s)..."
    if run_fio "t22_after_reset" \
        --name=t22_postrst --filename="${EMMC_DEV}" --offset=0 --size=512M \
        --direct=1 --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=60 --time_based --group_reporting; then
        pass "复位后 fio 随机写+校验完全正常"
    else
        local log="${LOGDIR}/fio_t22_after_reset.json"
        fail "复位后 fio 出错 (error=$(get_fio_error "${log}"))"
        info "说明复位没有完全恢复 eMMC 内部状态!"
    fi
}
