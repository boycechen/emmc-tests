#!/bin/bash
# T2 — 对抗性数据模式测试
# 写入全0/全1/边界模式数据, 检测NAND Cell干扰和数据保持能力

TEST_ID="t2"
TEST_NAME="对抗性数据模式 (NAND Cell 压力)"
TEST_DESC="0xFF/0x00/0xAA/0x55/A5/5A/随机 写入回读比较"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    local patterns=(
        "0xFF:全1(擦除态):\\x00|tr \\0 \\377"
        "0x00:全0(编程态):\\x00"
        "0xAA:10101010:\\x00|tr \\0 \\252"
        "0x55:01010101:\\x00|tr \\0 \\125"
        "0xA5:10100101:\\x00|tr \\0 \\245"
        "0x5A:01011010:\\x00|tr \\0 \\132"
        "URANDOM:真随机:if=/dev/urandom"
    )

    local total=${#patterns[@]}; local cur=1

    for pat in "${patterns[@]}"; do
        local name="${pat%%:*}"
        local desc="${pat#*:}"; desc="${desc%%:*}"
        local source="${pat##*:}"

        step "[${cur}/${total}] ${name} (${desc})"
        progress "生成数据..."

        local src="${LOGDIR}/pat_${name}.src"
        local verify="${LOGDIR}/pat_${name}.vfy"

        case "${source}" in
            if=/dev/urandom) dd if=/dev/urandom of="${src}" bs=1M count=64 2>/dev/null ;;
            *\|*)
                local fill="${source%%|*}"; local tr_cmd="${source#*|}"
                dd if=/dev/zero bs=1M count=64 2>/dev/null | eval "${tr_cmd}" > "${src}" 2>/dev/null ;;
            *) dd if=/dev/zero bs=1M count=64 2>/dev/null > "${src}" 2>/dev/null ;;
        esac
        local exp_md5=$(md5sum "${src}" | awk '{print $1}')

        progress "写入 (direct)..."
        dd if="${src}" of="${EMMC_DEV}" bs=1M count=64 oflag=direct 2>/dev/null || {
            fail "${name}: 写 I/O 错误"; rm -f "${src}"; ((cur++)); continue
        }
        sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

        progress "回读..."
        dd if="${EMMC_DEV}" of="${verify}" bs=1M count=64 iflag=direct 2>/dev/null || {
            fail "${name}: 读 I/O 错误"; rm -f "${src}" "${verify}"; ((cur++)); continue
        }
        local act_md5=$(md5sum "${verify}" | awk '{print $1}')

        if [ "${exp_md5}" = "${act_md5}" ]; then
            pass "${name}: 64MB 一致 (MD5=${exp_md5})"
        else
            local diff=$(cmp -l "${src}" "${verify}" 2>/dev/null | head -3)
            fail "${name}: 数据不匹配! (${exp_md5} vs ${act_md5})"
            info "首个差异: ${diff}"
        fi
        rm -f "${src}" "${verify}"
        ((cur++))
    done
}
