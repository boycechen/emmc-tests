#!/bin/bash
# T18 — 密集 fsync 压力测试
# 高频 fsync (每秒数百次) 迫使 eMMC 内部缓存频繁刷新
# 暴露缓存固件、提交队列管理、写缓存一致性方面的问题

TEST_ID="t18"
TEST_NAME="密集 fsync 压力"
TEST_DESC="每秒数百次 fsync, 暴露 Cache 固件和写提交缺陷"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_INFO}  原理: 每次 fsync 都触发 eMMC 缓存刷写到 NAND.${C_RESET}"
    echo -e "${C_INFO}  高频 fsync 可暴露缓存一致性、写放大、固件调度异常.${C_RESET}"

    local mount_pt="/tmp/emmc_mnt_${TIMESTAMP}"
    local part_dev=""

    # 查找可用分区: mmcblk0p1 / nvme0n1p1 等
    for pn in 1 2 3; do
        if [[ -b "${EMMC_DEV}p${pn}" ]]; then
            part_dev="${EMMC_DEV}p${pn}"
            break
        fi
    done

    mkdir -p "${mount_pt}"

    if mount | grep -q "${part_dev}"; then
        info "使用已挂载 ${part_dev}"
    elif ask_yes "格式化 ${part_dev} 为 ext4 用于 fsync 测试?"; then
        mkfs.ext4 -F "${part_dev}" 2>&1 | tail -1
        mount "${part_dev}" "${mount_pt}" || { fail "挂载失败"; rm -rf "${mount_pt}"; return; }
    else
        warn "跳过 T18 (需要可写入分区)"
        rm -rf "${mount_pt}"; return
    fi

    # ── Test A: 单文件密集 fsync ──
    step "Test 18a: 单文件同步写 (fsync 每 4K)"
    progress "使用 fio --sync=1 模式 (60s)..."
    if run_fio "t18_fsync_heavy" \
        --name=t18_fsync --filename="${mount_pt}/t18_fsync.dat" --size=512M \
        --ioengine=sync --rw=randwrite --bs=4k --fsync=1 \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 18a: 高频 fsync (4K 每次) 通过"
    else
        local log="${LOGDIR}/fio_t18_fsync_heavy.json"
        fail "Test 18a: fsync 错误 (error=$(get_fio_error "${log}"))"
        info "这可能说明 eMMC 写缓存或提交队列固件存在问题!"
    fi

    # ── Test B: 多文件同时 fsync ──
    step "Test 18b: 多文件并行 sync (numjobs=4)"
    progress "4 个线程各自 fsync 自己的文件..."
    if run_fio "t18_fsync_multi" \
        --name=t18_multifs --directory="${mount_pt}" --size=128M \
        --ioengine=sync --rw=write --bs=4k --fsync=1 \
        --numjobs=4 --nrfiles=4 \
        --verify=crc32c --verify_state_save=0 --verify_fatal=1 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 18b: 多文件并行 fsync 通过"
    else
        local log="${LOGDIR}/fio_t18_fsync_multi.json"
        fail "Test 18b: 多文件 fsync 错误 (error=$(get_fio_error "${log}"))"
    fi

    # ── Test C: fdatasync 高频触发 ──
    step "Test 18c: fdatasync (仅刷数据, 不刷元数据)"
    progress "fdatasync 模式 (60s)..."
    if run_fio "t18_fdatasync" \
        --name=t18_dsync --filename="${mount_pt}/t18_dsync.dat" --size=512M \
        --ioengine=sync --rw=randwrite --bs=4k --fdatasync=1 \
        --verify=crc32c --verify_state_save=0 \
        --runtime=60 --time_based --group_reporting; then
        pass "Test 18c: fdatasync 高频通过"
    else
        local log="${LOGDIR}/fio_t18_fdatasync.json"
        local err=$(get_fio_error "${log}")
        [ "${err}" = "0" ] && pass "Test 18c: fdatasync 通过 (exit code 非0但无实际错误)" || \
            fail "Test 18c: fdatasync 错误 (error=${err})"
    fi

    # ── 性能统计 ──
    step "fsync 性能统计"
    local log="${LOGDIR}/fio_t18_fsync_heavy.json"
    local wi=$(extract_fio_metric "${log}" "write_iops")
    local wb=$(extract_fio_metric "${log}" "write_bw")
    info "fsync 写性能: ${wi} IOPS / ${wb} KB/s"
    info "每秒 fsync 次数 ≈ 写 IOPS (因 --fsync=1)"

    rm -f "${mount_pt}/t18_fsync.dat" "${mount_pt}/t18_dsync.dat"
    for i in $(seq 0 3); do rm -f "${mount_pt}/t18_multifs.${i}.0" 2>/dev/null; done

    umount "${mount_pt}" 2>/dev/null || true
    rm -rf "${mount_pt}"
}
