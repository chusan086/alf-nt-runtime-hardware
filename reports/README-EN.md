# Raw implementation reports

These files are direct EDA outputs for the implementation points used in the
paper. They are not normalized cross-paper FF1 comparisons and do not imply
board I/O or silicon signoff.

Only the author-machine host name and destination path in the Vivado command
header were replaced with `<REDACTED>` and `<AUTHOR_OUTPUT>`; timing,
utilization, route-status and DRC content is otherwise unchanged. This narrow
sanitization prevents a machine fingerprint and local workspace path from
becoming part of the reviewer artifact.

## FPGA point identity

The RTL-set digest below is SHA-256 over UTF-8 lines of the form
`<file-sha256>  <basename>\n`, sorted by basename. Individual file hashes are
also present in the root `SHA256SUMS.txt`.

- `fpga/shared-8ns/`: top `n12_alf_shared_top`; runtime domain
  `n=2..15`, `t=0..7`, legal runtime `Q`; 11-file RTL-set digest
  `dc68650d5f46c5b3a514e167115bd59ba8b02e430bf9abd990b9768128dab2e0`;
  input-DCP digest
  `704d1fd3b0d6965b8d5d1dbf2947e2debce3040ebfe6c294c83297b033f8ed69`;
  routed-DCP digest
  `b280bfdfef54e02cdc04d05ec81e01156c896a954297d4e662f9bb9c88ce02c7`;
  `xc7a200tfbg676-2`, 8.000 ns.
- `fpga/fixed-m1-8ns/`: top `n12_alf_matched_fixed_v3_top`; M1 with
  `n=2`, `t=0`, `rounds=20`, `Q=65536`; 8-file RTL-set digest
  `c3b9509973b772a67f24c6f7aaa60faf5806af233b770205afab1dfd9a39e8b3`;
  input-DCP digest
  `f17241bd163e3f52bbd62f53f9ca42339817e0610b7a4d3a56c50e6f42cc6c85`;
  routed-DCP digest
  `3f8e56990cd1e925ae6adfc567473be3139f7c881975e2a2881b47c366af4220`;
  `xc7a200tfbg676-2`, 8.000 ns.
- `fpga/fixed-m4-7p750ns/`: top `n12_alf_matched_fixed_v3_top`; M4 with
  `n=6`, `t=6`, `rounds=16`, `Q=10000000000000000`; 8-file RTL-set digest
  `f38db691e71bfebf14df377a34d2abc571ca03ddd750fdfe9971648af62ad025`;
  post-synthesis-DCP digest
  `92dfbe6095e3e76ba76dbc503803ad5e375660450d10715bcf8e40b9d55aa897`;
  routed-DCP digest
  `04e8bcfb5c6119b98d7fa35a1248a0e8ca51566bd6aa32a90b3b9bb674d2c051`;
  `xc7a200tfbg676-2`, 7.750 ns. The DCPs are hash-bound preserved run inputs or
  outputs and are not distributed in this lean artifact.

| Directory | Period | Setup WNS | Internal register hold | LUT | Registers | BRAM tiles |
|---|---:|---:|---:|---:|---:|---:|
| `fpga/shared-8ns/` | 8.000 ns | +0.026 ns | +0.114 ns | 18,481 | 5,454 | 3.5 |
| `fpga/fixed-m1-8ns/` | 8.000 ns | +0.417 ns | +0.060 ns | 6,830 | 3,401 | 2.0 |
| `fpga/fixed-m4-7p750ns/` | 7.750 ns | +0.086 ns | +0.117 ns | 10,227 | 3,593 | 2.0 |

Each FPGA directory contains the original timing summary, the explicit
register-to-register minimum-delay report, utilization, route status, and DRC
or run-status output. The broad Vivado timing summaries include external-port
minimum-delay failures because this is an out-of-context core without a board
I/O timing contract. The paper's hold statement is therefore restricted to
the explicit register-to-register `hold-top2000.rpt`; it does not claim package
or board-interface hold closure.

"Fully Routed" and zero routing errors do not mean DRC-clean signoff. The
shared DRC report contains 43 warnings: one missing configuration-voltage
property, two report-limit warnings, and 40 RAMB asynchronous-control warnings
(`REQP-1839/1840`). Fixed M1 contains 22 warnings: one configuration-voltage
property warning, one report-limit warning, and 20 `REQP-1839` warnings. The
RAMB warnings state that asynchronous reset on registers driving RAM controls
may corrupt memory contents or read values during reset and is not analyzed by
default STA. Consequently these reports establish routed steady-state core
timing only; they do not establish reset-release safety or board signoff.
The fixed M4 point has no standalone `drc.rpt`; its `route-status.rpt` proves
zero routing errors only, so no DRC-clean claim is made for M4.

The ASIC directory contains one frozen standard-cell implementation point:

| Directory | Library | Period | Setup WNS | Hold WNS | TNS | Area | Detailed-route DRC |
|---|---|---:|---:|---:|---:|---:|---:|
| `asic/nangate45-shared-5ns/` | Nangate45 | 5.000 ns | +2.980445 ns | +0.001993 ns | 0 ns | 205,358 um^2 | 0 |

The ASIC point uses OpenROAD `v2.0-17598-ga008522d8`. The RTL key-bank memory
was lowered to standard cells; the numbers are not SRAM-macro PPA. The
zero-length `50-detailed-route-drc.rpt` is the direct OpenROAD DRC output for
zero remaining violations; `openroad.exit` and
`openroad-final-drc-excerpt.rpt` preserve the successful exit and final
zero-violation log lines. `50-postroute-check-setup.rpt` also preserves the
warning that asynchronous reset input `rst_ni` has no external input delay.
Consequently this is core-level physical evidence, not package or signoff
timing. WNS implies a descriptive 2.019555 ns critical-period proxy, but no
implementation was run at that period and it is not reported as achieved
frequency.

For Chinese documentation, see [README-CN.md](README-CN.md).
