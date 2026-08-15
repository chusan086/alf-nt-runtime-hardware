# Frozen fixed controls

The `rtl/fixed/m1` and `rtl/fixed/m4` directories contain the two
representative same-source fixed controls released with this reviewer
artifact. They preserve the P20 request/response protocol, AES round lane,
encryption/decryption behavior, reset behavior, response backpressure, and
registered-read key-bank service used by the shared design. Runtime parameter
selection is replaced by the constants of the selected experiment point.

These directories support the matched comparisons reported by the paper. They
do not constitute an arbitrary-parameter fixed-core generator, and no physical
result is implied for a fixed point that is not accompanied by a direct report.
Both directories expose `n12_alf_matched_fixed_v3_top`; compile only one at a
time.

| Control | `n` | `t` | rounds | `Q` |
|---|---:|---:|---:|---:|
| M1 | 2 | 0 | 20 | 65,536 |
| M4 | 6 | 6 | 16 | 10,000,000,000,000,000 |

The inherited source comment `row0/P20 projection` names the fixed-control
transport lineage; it is not the parameter identity. The localparams in each
top and the table above are authoritative for M1 versus M4.

## 中文说明

`rtl/fixed/m1` 与 `rtl/fixed/m4` 是本审稿工件发布的两个代表性同源固定对照。
它们保留与共享设计一致的 P20 请求/响应协议、AES 轮通道、加解密行为、复位、
响应反压和寄存读轮密钥存储服务，并把运行时参数选择替换为相应实验点的常量。

这两个目录只服务于论文中已经报告的匹配比较，不构成任意参数固定核生成器；
没有直接实现报告的参数点也不因此获得物理结果。两个目录都导出顶层模块
`n12_alf_matched_fixed_v3_top`，编译时只能选择其中一个。

M1 固定为 `n=2、t=0、rounds=20、Q=65536`；M4 固定为
`n=6、t=6、rounds=16、Q=10000000000000000`。源码中继承的
`row0/P20 projection` 注释表示固定对照的传输接口谱系，不是参数身份；参数身份
以各顶层的 localparam 和上表为准。
