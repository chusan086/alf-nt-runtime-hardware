# Release manifest / 发布清单

Version: `0.2.0-rc1`

This anonymous-review candidate contains:

- 11 SystemVerilog files for the runtime-parameterized shared core;
- 8 SystemVerilog files for the frozen M1 fixed control;
- 8 SystemVerilog files for the frozen M4 fixed control;
- direct Vivado reports for shared 8.000 ns, fixed M1 8.000 ns, and fixed M4
  7.750 ns implementation points;
- direct OpenROAD reports for one Nangate45 shared-core 5.000 ns physical
  point; and
- concise architecture, interface, fixed-control, porting, citation, license,
  and integrity documentation.

It intentionally excludes simulation infrastructure, test vectors, EDA launch
wrappers, physical databases, historical RTL, arbitrary fixed-core generation,
and authors' internal project records. The released reports do not establish
board I/O or silicon signoff, and the representative physical points do not
mean that all 112 parameter pairs were separately placed and routed.

Integrity is defined by `SHA256SUMS.txt`. The artifact is released under the
MIT License; the anonymous copyright line is the only license metadata that
must be deanonymized later.

## 中文

本匿名审稿候选包含：全参数运行时共享核的 11 个 SystemVerilog 文件、冻结的
M1 与 M4 固定对照各 8 个 SystemVerilog 文件、三个 FPGA 实现点的直接 Vivado
报告、一个 Nangate45 共享核物理实现点的直接 OpenROAD 报告，以及精简的架构、
接口、固定对照、移植、引用、许可和完整性说明。

本候选明确不包含仿真环境、测试向量、EDA 启动脚本、物理数据库、历史 RTL、
任意固定核生成器或作者内部项目记录。所附报告不构成板级 I/O 或流片签核证据；
代表性物理实现点也不表示 112 个参数对均分别完成了布局布线。

本工件采用 MIT License；正式去匿名时只需替换匿名版权人并重建哈希清单。
