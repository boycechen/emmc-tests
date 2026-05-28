# eMMC Tests — Deep Stress Test Suite

eMMC 深度压力测试套件，覆盖固件、NAND Flash、控制器、ECC、时序接口等全部已知失效模式。

## 快速开始

```bash
# 在目标设备 (如 Rock 5B) 上
sudo bash emmc_test.sh
```

## 特性

- **30 项专项测试**，覆盖 eMMC 各组件
- **自动设备适配**：通过 `blockdev` 检测容量，按百分比动态分配偏移
- **实时输出**：fio 进度条实时显示，JSON 日志供事后分析
- **彩色汇总表**：ID / 名称 / 时长 / P/F/W 计数 / 结果
- **关键指标提取**：自动从日志中提取寿命(PRE_EOL)、延迟(P99)、性能基线
- **模块化设计**：每项测试独立文件，新增测试只需加 `.sh` 到 `tests/`

## 用法

```bash
# 列出所有测试
./emmc_test.sh --list

# 指定设备运行
sudo ./emmc_test.sh --run t1,t7,t8 --device /dev/mmcblk0

# 全部测试
sudo ./emmc_test.sh --run-all

# 交互菜单
sudo ./emmc_test.sh
```

## 测试项 (30 项)

| ID | 测试 | 目标 |
|----|------|------|
| t1 | 设备信息与寿命评估 | PRE_EOL / 磨损等级 |
| t2 | 对抗性数据模式 | NAND Cell 串扰 |
| t3 | CRC32C 校验 | ECC 数据路径 |
| t4 | 长时间混合压力 | 热/GC/BKOPS 稳定性 |
| t5 | 写原子性 | fsync 一致性 |
| t6 | 内部管理功能 | Cache/BKOPS/Sleep |
| t7 | 延迟毛刺检测 | P50~P99.99 |
| t8 | ECC/坏块重映射 | 保留块池耗尽 |
| t9 | 多线程并发 | 控制器仲裁 |
| t10 | 性能基线 | 退化检测 |
| t11 | 数据保持 | 断电后验证 |
| t12 | 读干扰压力 | Read Disturb |
| t13 | 热区写压力 | 磨损均衡 |
| t14 | TRIM/Discard | 固件实现正确性 |
| t15 | 边界地址访问 | 首尾/跨边界 |
| t16 | IO 深度冲击 | 队列管理 |
| t17 | 混合粒度 | 512B~1M |
| t18 | 密集 fsync | 缓存固件 |
| t19 | 单 LBA 热点 | 重映射逻辑 |
| t20 | 全设备遍历 | 坏块扫描 |
| t21 | 异质性负载 | 控制器调度 |
| t22 | Reset 恢复 | 固件状态机 |
| t23 | WAF 估算 | 写放大因子 |
| t24 | 短间隔保持 | Cell 电荷泄露 |
| t25 | 全范围随机读 | 全局读干扰 |
| t26 | 读写冲突 | 同一 LBA 一致性 |
| t27 | Page Cache 交互 | 内核块层 |
| t28 | 空闲/唤醒切换 | BKOPS/GC |
| t29 | Boot 分区 | 启动区功能 |
| t30 | 温复位+I/O | 热恢复能力 |

## 目录结构

```
emmc_tests/
├── emmc_test.sh              # 入口脚本
├── lib/
│   ├── colors.sh             # 颜色定义
│   ├── common.sh             # 公共函数库
│   └── devices.sh            # 设备选择
└── tests/                    # 30 项测试, 任意扩展
    ├── t1_device_info.sh
    ├── t2_pattern_rw.sh
    └── ...
```

## 依赖

- `fio` (必须)
- `mmc-utils` (可选, 增强 T1/T6/T22/T30)
- `bc` (可选, 延迟格式化)
- `blockdev` (可选, 容量检测)
