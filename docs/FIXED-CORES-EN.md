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

For Chinese documentation, see [FIXED-CORES-CN.md](FIXED-CORES-CN.md).
