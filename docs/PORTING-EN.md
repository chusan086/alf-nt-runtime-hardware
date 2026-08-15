# Porting notes

The RTL contains no absolute workspace path. Compile each directory in this
order: `n12_alf_v0_tables_pkg.sv`, `n12_aes_round_lane.sv`, stream frontend,
profile/descriptor modules when present, controller, key bank, key/tweak,
round core, and finally the selected top.

For FPGA targets, preserve inferred synchronous RAM in
`n12_alf_key_bank.sv`. A backend may map it to device RAM primitives without
changing the transaction interface. For ASIC work, replace the storage
implementation only behind the same key-bank service boundary and re-run the
complete functional and timing evidence chain. Any included ASIC reports use
the RTL memory lowered to standard-cell logic; they are not SRAM-macro PPA.

Do not compile M1 and M4 together because they intentionally expose the same
fixed top-level module name. They are alternative elaboration-time instances.

Vivado 2020.2 `xvlog` requires `--relax` when compiling these SystemVerilog
sources because it otherwise treats ANSI `input logic` declarations under
``default_nettype none`` as errors. This is a compiler-front-end compatibility
option; it does not alter RTL behavior. The released shared source and the
frozen M1/M4 fixed sources use the same compiler option.

For Chinese documentation, see [PORTING-CN.md](PORTING-CN.md).
