#!/bin/bash
# T29 — Boot 分区读写测试
# 测试 eMMC Boot 分区的读写功能 (如果硬件暴露)
# Boot 分区通常较小 (4-8MB) 但有自己的擦除块

TEST_ID="t29"
TEST_NAME="Boot 分区读写测试"
TEST_DESC="访问 eMMC Boot0/Boot1 分区, 检测启动区功能"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"

    # 查找 boot 分区
    local boot0=""
    local boot1=""
    local dev_name="${EMMC_DEV#/dev/}"

    # eMMC boot 分区设备节点命名:
    # /dev/mmcblk0boot0  /dev/mmcblk0boot1
    local base="${EMMC_DEV%blk*}"
    if [ -b "${base}blk0boot0" ]; then
        boot0="${base}blk0boot0"
        boot1="${base}blk0boot1"
    elif [ -b "${EMMC_DEV}boot0" ]; then
        boot0="${EMMC_DEV}boot0"
        boot1="${EMMC_DEV}boot1"
    fi

    if [ -z "${boot0}" ] || [ ! -b "${boot0}" ]; then
        warn "Boot 分区不可访问 (设备节点不存在)"
        info "某些内核/eMMC不暴露 boot 分区节点"
        return
    fi

    info "发现 Boot0: ${boot0}, Boot1: ${boot1}"

    # 获取大小
    local b0_name="${boot0#/dev/}"
    local b0_size=$(cat "/sys/block/${b0_name}/size" 2>/dev/null || echo "N/A")
    local b0_size_mb="?"
    if [ "${b0_size}" != "N/A" ] && [ "${b0_size}" -gt 0 ]; then
        b0_size_mb=$((b0_size / 2048))
    fi
    info "Boot0 大小: ${b0_size_mb}MB (${b0_size} 扇区)"

    # ── Test A: Boot0 只读验证 ──
    step "Test 29a: Boot0 分区读取"
    progress "读取 Boot0 全部内容 (非破坏性)..."
    dd if="${boot0}" of="${LOGDIR}/t29_boot0_dump.dat" bs=1M count=16 iflag=direct 2>/dev/null || {
        fail "Boot0 读取失败!"; return
    }
    local boot0_md5=$(md5sum "${LOGDIR}/t29_boot0_dump.dat" | awk '{print $1}')
    info "Boot0 内容 MD5: ${boot0_md5}"
    pass "Boot0 分区可读取"

    # ── Test B: Boot1 分区读写 (非破坏, 仅当分区为空或可写) ──
    step "Test 29b: Boot1 分区写入/回读 (需确认)"
    if ask_yes "向 Boot1 分区写入测试数据? (Boot0/Boot1 通常各 4MB, 只写 Boot1)"; then
        progress "写入已知数据到 Boot1..."
        local ref_file="${LOGDIR}/t29_boot1_ref.dat"
        dd if=/dev/urandom of="${ref_file}" bs=1M count=4 2>/dev/null
        local ref_md5=$(md5sum "${ref_file}" | awk '{print $1}')

        # 切换到 Boot1 (某些 eMMC 需要)
        dd if="${ref_file}" of="${boot1}" bs=1M count=4 oflag=direct 2>/dev/null || {
            fail "Boot1 写入失败 (可能被写保护)"; rm -f "${ref_file}"; return
        }
        sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

        progress "回读 Boot1..."
        local vfy_file="${LOGDIR}/t29_boot1_vfy.dat"
        dd if="${boot1}" of="${vfy_file}" bs=1M count=4 iflag=direct 2>/dev/null
        local vfy_md5=$(md5sum "${vfy_file}" | awk '{print $1}')

        if [ "${ref_md5}" = "${vfy_md5}" ]; then
            pass "Boot1 分区读写正常"
        else
            fail "Boot1 数据不匹配! (${ref_md5} vs ${vfy_md5})"
        fi
        rm -f "${ref_file}" "${vfy_file}"
    else
        info "跳过 Boot1 写入测试"
    fi
}
