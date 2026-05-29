#!/bin/bash
# 颜色定义 — 全脚本共用
# 类型色体系: 每种状态有专属色, 一眼可辨

C_TITLE=$'\033[1;38;5;45m'       # 亮青   — 测试大类标题
C_INFO=$'\033[38;5;117m'        # 淡青   — 信息提示
C_PASS=$'\033[1;38;5;82m'       # 亮绿   — 通过
C_FAIL=$'\033[1;38;5;196m'      # 亮红   — 失败
C_WARN=$'\033[1;38;5;214m'      # 橙黄   — 警告
C_STEP=$'\033[1;38;5;39m'       # 亮蓝   — 测试步骤
C_PROGRESS=$'\033[38;5;226m'    # 亮黄   — 进度指示
C_PROMPT=$'\033[1;38;5;201m'    # 粉紫   — 交互提示
C_CMD=$'\033[38;5;245m'         # 灰色   — 命令/代码显示
C_RESET=$'\033[0m'              # 重置

# 状态图标
ICON_PASS="${C_PASS}✔${C_RESET}"
ICON_FAIL="${C_FAIL}✘${C_RESET}"
ICON_WARN="${C_WARN}⚠${C_RESET}"
ICON_INFO="${C_INFO}ℹ${C_RESET}"
ICON_STEP="${C_STEP}▸${C_RESET}"
ICON_PROGRESS="${C_PROGRESS}⏳${C_RESET}"
ICON_PROMPT="${C_PROMPT}❓${C_RESET}"
