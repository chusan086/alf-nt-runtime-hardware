# 原始实现报告

本目录中的文件是论文所采用实现点的直接 EDA 输出。它们不是经过统一口径归一化的
跨论文 FF1 比较，也不构成板级 I/O 或硅后签核证据。

Vivado 命令头中仅作者机器的主机名和报告目标路径分别替换为 `<REDACTED>` 与
`<AUTHOR_OUTPUT>`；时序、利用率、布线状态和 DRC 内容均保持不变。这种窄范围
脱敏避免在审稿工件中暴露机器指纹和本地工作区路径。

## FPGA 实现点身份

下列 RTL 集合摘要是对按文件名排序的 UTF-8 行
`<file-sha256>  <basename>\n` 计算所得的 SHA-256。每个文件各自的哈希也记录在
根目录 `SHA256SUMS.txt` 中。

- `fpga/shared-8ns/`：顶层 `n12_alf_shared_top`；运行时域为
  `n=2..15`、`t=0..7` 及合法运行时 `Q`；11 文件 RTL 集合摘要
  `dc68650d5f46c5b3a514e167115bd59ba8b02e430bf9abd990b9768128dab2e0`；
  输入 DCP 摘要
  `704d1fd3b0d6965b8d5d1dbf2947e2debce3040ebfe6c294c83297b033f8ed69`；
  布线后 DCP 摘要
  `b280bfdfef54e02cdc04d05ec81e01156c896a954297d4e662f9bb9c88ce02c7`；
  器件 `xc7a200tfbg676-2`，周期 8.000 ns。
- `fpga/fixed-m1-8ns/`：顶层 `n12_alf_matched_fixed_v3_top`；M1 参数为
  `n=2`、`t=0`、`rounds=20`、`Q=65536`；8 文件 RTL 集合摘要
  `c3b9509973b772a67f24c6f7aaa60faf5806af233b770205afab1dfd9a39e8b3`；
  输入 DCP 摘要
  `f17241bd163e3f52bbd62f53f9ca42339817e0610b7a4d3a56c50e6f42cc6c85`；
  布线后 DCP 摘要
  `3f8e56990cd1e925ae6adfc567473be3139f7c881975e2a2881b47c366af4220`；
  器件 `xc7a200tfbg676-2`，周期 8.000 ns。
- `fpga/fixed-m4-7p750ns/`：顶层 `n12_alf_matched_fixed_v3_top`；M4 参数为
  `n=6`、`t=6`、`rounds=16`、`Q=10000000000000000`；8 文件 RTL 集合摘要
  `f38db691e71bfebf14df377a34d2abc571ca03ddd750fdfe9971648af62ad025`；
  综合后 DCP 摘要
  `92dfbe6095e3e76ba76dbc503803ad5e375660450d10715bcf8e40b9d55aa897`；
  布线后 DCP 摘要
  `04e8bcfb5c6119b98d7fa35a1248a0e8ca51566bd6aa32a90b3b9bb674d2c051`；
  器件 `xc7a200tfbg676-2`，周期 7.750 ns。DCP 是由哈希绑定的保留运行输入或
  输出，本精简工件不发布这些文件。

| 目录 | 周期 | 建立 WNS | 内部寄存器保持裕量 | LUT | 寄存器 | BRAM 块 |
|---|---:|---:|---:|---:|---:|---:|
| `fpga/shared-8ns/` | 8.000 ns | +0.026 ns | +0.114 ns | 18,481 | 5,454 | 3.5 |
| `fpga/fixed-m1-8ns/` | 8.000 ns | +0.417 ns | +0.060 ns | 6,830 | 3,401 | 2.0 |
| `fpga/fixed-m4-7p750ns/` | 7.750 ns | +0.086 ns | +0.117 ns | 10,227 | 3,593 | 2.0 |

每个 FPGA 目录均包含原始时序汇总、明确的寄存器到寄存器最小延迟报告、利用率、
布线状态，以及 DRC 或运行状态输出。Vivado 的完整时序汇总包含外部端口最小延迟
违例，因为这里实现的是没有板级 I/O 时序约束的独立核。因此，论文中的保持时间
表述仅限 `hold-top2000.rpt` 明确报告的寄存器到寄存器路径，不声称封装或板级接口
保持时间闭合。

“Fully Routed”和零布线错误不等于 DRC 签核干净。共享核 DRC 报告含 43 个警告：
1 个缺失配置电压属性警告、2 个报告数量上限警告，以及 40 个 RAMB 异步控制警告
（`REQP-1839/1840`）。固定 M1 含 22 个警告：1 个配置电压属性警告、1 个报告
数量上限警告，以及 20 个 `REQP-1839` 警告。RAMB 警告指出，驱动 RAM 控制端
寄存器的异步复位可能破坏复位期间的存储内容或读取值，且默认 STA 不分析这一
行为。因此，这些报告只证明布线后的稳态核级时序，不证明复位释放安全或板级
签核。固定 M4 没有单独的 `drc.rpt`；其 `route-status.rpt` 只证明零布线错误，
故不对 M4 声称 DRC 干净。

ASIC 目录包含一个冻结的标准单元实现点：

| 目录 | 工艺库 | 周期 | 建立 WNS | 保持 WNS | TNS | 面积 | 详细布线 DRC |
|---|---|---:|---:|---:|---:|---:|---:|
| `asic/nangate45-shared-5ns/` | Nangate45 | 5.000 ns | +2.980445 ns | +0.001993 ns | 0 ns | 205,358 um^2 | 0 |

该 ASIC 点使用 OpenROAD `v2.0-17598-ga008522d8`。RTL 轮密钥存储被降解为
标准单元，所得数字不是 SRAM 宏 PPA。零长度的 `50-detailed-route-drc.rpt`
是零剩余违例时 OpenROAD 直接生成的 DRC 输出；`openroad.exit` 和
`openroad-final-drc-excerpt.rpt` 保存了成功退出状态及最终零违例日志行。
`50-postroute-check-setup.rpt` 还保留了异步复位输入 `rst_ni` 没有外部输入延迟的
警告。因此，这只是核级物理实现证据，不是封装或签核时序。由 WNS 可描述性地
反推出 2.019555 ns 临界周期代理值，但项目并未在该周期重新实现，故不把它报告为
已实现频率。

英文说明见 [README-EN.md](README-EN.md)。
