# Nangate45 共享核物理实现点

本目录包含最终共享核在 5.000 ns 时钟约束下的部分直接 OpenROAD 输出。该次运行
使用 OpenROAD `v2.0-17598-ga008522d8`、配置 16 个线程，并采用 Nangate45
标准单元库。

所含文件覆盖建立时间 WNS 与路径、保持时间 WNS 与寄存器路径、TNS、时钟偏斜、
面积、单元使用率、约束检查和详细布线 DRC。体积较大的物理数据库（`ODB`、
`DEF`、`SPEF`）以及包含机器信息的运行日志被有意排除。

RTL 轮密钥存储被降解为标准单元。本目录不代表 SRAM 宏实现或硅后签核。
空的 `50-detailed-route-drc.rpt` 表示详细布线后零剩余违例；其旁的
`openroad.exit`（值为 `0`）和 `openroad-final-drc-excerpt.rpt` 保存了成功退出
状态，以及 OpenROAD 日志中详细布线和天线检查最终均为零违例的行。
复位输入延迟警告保留在 `50-postroute-check-setup.rpt` 中。

英文说明见 [README-EN.md](README-EN.md)。
