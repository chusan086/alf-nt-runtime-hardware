# 移植说明

RTL 不包含任何工作区绝对路径。每个目录按以下顺序编译：
`n12_alf_v0_tables_pkg.sv`、`n12_aes_round_lane.sv`、流式前端、存在时的
配置/描述符模块、控制器、轮密钥存储、密钥/微调值模块、轮运算核，最后编译所选
顶层。

面向 FPGA 时，应保留 `n12_alf_key_bank.sv` 中推断的同步 RAM。后端可以在不改变
事务接口的前提下，将其映射为器件 RAM 原语。面向 ASIC 时，只能在相同轮密钥
存储服务边界之后替换存储实现，并重新执行完整的功能与时序证据链。随附的 ASIC
报告将 RTL 存储降解为标准单元逻辑，不是采用 SRAM 宏所得的 PPA。

M1 与 M4 有意导出相同的固定核顶层模块名，因此不得同时编译；两者是二选一的
elaboration-time 实例。

Vivado 2020.2 的 `xvlog` 编译这些 SystemVerilog 源码时需要使用 `--relax`，否则
会把 ``default_nettype none`` 下的 ANSI `input logic` 声明判为错误。这只是编译器
前端兼容选项，不改变 RTL 行为。发布的共享核和冻结的 M1/M4 固定核使用相同的
编译选项。

英文说明见 [PORTING-EN.md](PORTING-EN.md)。
