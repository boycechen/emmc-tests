#!/bin/bash
# T5 — 写原子性与数据一致性
# 需要可用分区, 测试 fsync / 事务写 / drop_cache 后数据完整性

TEST_ID="t5"
TEST_NAME="写原子性与数据一致性"
TEST_DESC="fsync + drop_cache 回读, fio 多文件事务校验"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    local mount_pt="/tmp/emmc_mnt_${TIMESTAMP}"
    local part_dev=""

    # 查找可用分区: mmcblk0p1 / nvme0n1p1 等
    # 按分区号递增查找 (p1 → p2 → ...)
    for pn in 1 2 3; do
        if [[ -b "${EMMC_DEV}p${pn}" ]]; then
            part_dev="${EMMC_DEV}p${pn}"
            break
        fi
    done

    mkdir -p "${mount_pt}"

    if mount | grep -q "${part_dev}"; then
        info "使用已挂载 ${part_dev}"
    elif [ -n "${part_dev}" ] && ask_yes "格式化 ${part_dev} 为 ext4?"; then
        mkfs.ext4 -F "${part_dev}" 2>&1 | tail -1
        mount "${part_dev}" "${mount_pt}" || { fail "挂载失败"; rm -rf "${mount_pt}"; return; }
    else
        warn "无可用分区, 跳过 T5"
        rm -rf "${mount_pt}"; return
    fi

    # Test A: fsync 保证
    step "Test 5a: fsync + drop_cache 回读"
    dd if=/dev/urandom of="${mount_pt}/t5_ref.dat" bs=1M count=256 2>/dev/null
    local ref_md5=$(md5sum "${mount_pt}/t5_ref.dat" | awk '{print $1}')
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    dd if="${mount_pt}/t5_ref.dat" of="${mount_pt}/t5_cp.dat" bs=1M conv=fsync 2>/dev/null
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    local cp_md5=$(md5sum "${mount_pt}/t5_cp.dat" | awk '{print $1}')
    [ "${ref_md5}" = "${cp_md5}" ] && pass "fsync 数据一致 (${ref_md5})" || \
        fail "fsync 数据不匹配! ${ref_md5} vs ${cp_md5}"
    rm -f "${mount_pt}/t5_ref.dat" "${mount_pt}/t5_cp.dat"

    # Test B: fio 多文件事务写
    step "Test 5b: fio 多文件事务写"
    fio --name=t5_atomic --directory="${mount_pt}" --size=64M --ioengine=sync \
        --nrfiles=8 --rw=write --verify=crc32c --verify_state_save=0 --do_verify=1 \
        --output="${LOGDIR}/fio_t5_atomic.json" --output-format=json 2>/dev/null
    local err=$(get_fio_error "${LOGDIR}/fio_t5_atomic.json")
    [ "${err}" = "0" ] && pass "多文件事务写通过" || fail "事务写 error=${err}"

    umount "${mount_pt}" 2>/dev/null || true
    rm -rf "${mount_pt}"
}
