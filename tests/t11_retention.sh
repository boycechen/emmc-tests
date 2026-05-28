#!/bin/bash
# T11 — 数据保持测试 (写入参考数据, 供断电后验证)

TEST_ID="t11"
TEST_NAME="数据保持 (写入参考)"
TEST_DESC="写入1GB已知数据生成哈希, 断电静置后回读验证"

run_test() {
    title "${TEST_ID}: ${TEST_NAME}"
    info "${TEST_DESC}"
    echo -e "${C_WARN}注意: 写入 ${EMMC_DEV} 偏移 0 处 1GB 数据, 会覆盖分区表!${C_RESET}"

    if ! ask_yes "写入 1GB 参考数据并记录哈希?"; then
        warn "跳过"; return
    fi

    local out_ref="${LOGDIR}/retention_ref.bin"
    local md5file="${LOGDIR}/retention_ref.md5"

    step "生成 1GB 参考数据"
    progress "写入到 ${EMMC_DEV}..."
    dd if=/dev/urandom of="${out_ref}" bs=1M count=1024 2>/dev/null
    local md5=$(md5sum "${out_ref}" | awk '{print $1}')
    local sha=$(sha256sum "${out_ref}" | awk '{print $1}')

    dd if="${out_ref}" of="${EMMC_DEV}" bs=1M count=1024 oflag=direct 2>/dev/null || {
        fail "写入失败"; rm -f "${out_ref}"; return
    }
    pass "参考数据已写入 (1GB)"

    cat > "${md5file}" <<EOF
# eMMC Data Retention Check
# Device: ${EMMC_DEV}
# Written: $(date)
# Offset: 0, 1024MB
MD5:    ${md5}
SHA256: ${sha}
#
# 验证命令 (断电后运行):
#   dd if=${EMMC_DEV} bs=1M count=1024 iflag=direct | md5sum
#   dd if=${EMMC_DEV} bs=1M count=1024 iflag=direct | sha256sum
EOF

    echo -e "\n${C_WARN}┌─────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_WARN}│  断电后验证:                                        │${C_RESET}"
    echo -e "${C_WARN}│  dd if=${EMMC_DEV} bs=1M count=1024 iflag=direct | md5sum${C_RESET}"
    echo -e "${C_WARN}│  预期 MD5: ${md5}${C_RESET}"
    echo -e "${C_WARN}└─────────────────────────────────────────────────────┘${C_RESET}"
}
