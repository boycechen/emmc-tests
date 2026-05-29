#!/bin/bash
# 设备选择逻辑

DEVICE_SIZE_SECTORS=0
DEVICE_SIZE_GB=0
DEVICE_SIZE_MB=0
DEVICE_SIZE_BYTES=0

select_device() {
    clear
    full_line "${C_TITLE}" "═"
    center_text "eMMC Deep Stress Test Suite v3.0" "${C_TITLE}"
    full_line "${C_INFO}" "─"
    center_text "模块化 · 可扩展 · fio 驱动" "${C_INFO}"

    echo -e "\n${C_INFO}已检测: fio=${HAS_FIO} mmc-utils=${HAS_MMC_UTILS}${C_RESET}"
    [ "${HAS_MMC_UTILS}" = false ] && \
        echo -e "${C_WARN}提示: mmc-utils 未安装, 部分测试(T1/T6/T22/T30)功能受限${C_RESET}"

    # 列出候选设备
    echo -e "\n${C_PROMPT}扫描可用块设备...${C_RESET}\n"
    local candidates=()
    local idx=0
    local has_mmc=false

    while IFS= read -r line; do
        local name=$(echo "${line}" | awk '{print $1}')
        local size=$(echo "${line}" | awk '{print $2}')
        local type=$(echo "${line}" | awk '{print $3}')
        local model=$(echo "${line}" | cut -d' ' -f4-)
        if [[ "${name}" == mmcblk* ]]; then
            has_mmc=true
            candidates+=("/dev/${name}")
            echo -e "  ${C_STEP}[${idx}]${C_RESET} /dev/${name}  ${C_PROGRESS}${size}${C_RESET}  ${type}  ${model}"
            ((idx++))
        fi
    done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n 2>/dev/null | grep -vE 'loop|sr|ram')

    # 无 mmcblk → 列出所有非 loop 设备
    if [ ${#candidates[@]} -eq 0 ]; then
        echo -e "  ${C_WARN}未发现 mmcblk 设备. 列出所有可用块设备:${C_RESET}\n"
        while IFS= read -r line; do
            local name=$(echo "${line}" | awk '{print $1}')
            candidates+=("/dev/${name}")
            echo -e "  ${C_STEP}[${idx}]${C_RESET} /dev/${name}  ${line#* }"
            ((idx++))
        done < <(lsblk -d -o NAME,SIZE,TYPE,MODEL -n 2>/dev/null | grep -vE 'loop|sr|ram')
    fi

    if [ ${#candidates[@]} -eq 0 ]; then
        echo -e "${C_FAIL}没有找到可用块设备!${C_RESET}"; exit 1
    fi

    # 用户选择
    local choice=-1
    while true; do
        echo -ne "\n${C_PROMPT}选择测试设备编号 [0-$((${#candidates[@]}-1))]: ${C_RESET}"
        read -r choice
        [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 0 ] && [ "${choice}" -lt "${#candidates[@]}" ] && break
        echo -e "${C_FAIL}无效选择${C_RESET}"
    done

    EMMC_DEV="${candidates[$choice]}"
    local dev_size=$(lsblk -d -o SIZE -n "${EMMC_DEV}" 2>/dev/null || echo "?")
    local dev_model=$(lsblk -d -o MODEL -n "${EMMC_DEV}" 2>/dev/null || echo "?")
    echo -e "\n${C_PASS}已选择: ${C_PROGRESS}${EMMC_DEV}${C_RESET}  (${dev_size}, ${dev_model})"

    # 检测容量
    detect_device_size

    if mount | grep -q "${EMMC_DEV}p"; then
        echo -e "${C_WARN}⚠ 分区已挂载! 测试使用原始块设备, 数据可能损坏${C_RESET}"
    fi

    # 初始化日志 (由入口脚本 main() 统一管理)
    # init_logdir 不在这里调用, 避免与 main() 重复

    # 危险确认
    echo -e "\n${C_FAIL}⚠ 警告: 测试会向 ${EMMC_DEV} 写入大量数据${C_RESET}"
    echo -e "${C_FAIL}  覆盖 0~20GB, 会破坏已有数据!${C_RESET}"
    ask_yes "继续?" || { echo -e "${C_WARN}已取消${C_RESET}"; exit 0; }
}

# ─── 设备容量检测 (独立函数, 同时被 select_device 和 main() 调用) ──
detect_device_size() {
    local dev_name="${EMMC_DEV#/dev/}"
    if command -v blockdev &>/dev/null; then
        DEVICE_SIZE_BYTES=$(blockdev --getsize64 "${EMMC_DEV}" 2>/dev/null || echo "0")
    else
        DEVICE_SIZE_SECTORS=$(cat "/sys/block/${dev_name}/size" 2>/dev/null || echo "0")
        DEVICE_SIZE_BYTES=$((DEVICE_SIZE_SECTORS * 512))
    fi
    DEVICE_SIZE_MB=$((DEVICE_SIZE_BYTES / 1048576))
    DEVICE_SIZE_GB=$((DEVICE_SIZE_MB / 1024))
    if [ "${DEVICE_SIZE_BYTES}" -gt 0 ]; then
        info "设备容量: ${DEVICE_SIZE_MB}MB (~${DEVICE_SIZE_GB}GB)"
        if [ "${DEVICE_SIZE_GB}" -lt 16 ]; then
            warn "设备仅 ${DEVICE_SIZE_GB}GB (<16GB)! 部分测试将跳过"
        fi
    else
        warn "无法读取设备容量!"
    fi
}
