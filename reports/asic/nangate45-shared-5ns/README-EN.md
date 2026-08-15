# Nangate45 shared-core physical point

This directory contains selected direct OpenROAD outputs for the final shared
core under a 5.000 ns clock constraint. The run used OpenROAD
`v2.0-17598-ga008522d8`, 16 configured threads and the Nangate45 standard-cell
library.

Included files cover setup WNS and paths, hold WNS and register paths, TNS,
clock skew, area, cell usage, constraint checks and detailed-route DRC. Large
physical databases (`ODB`, `DEF`, `SPEF`) and the machine-specific run log are
intentionally excluded.

The key-bank RTL memory was lowered to standard cells. This directory does not
represent an SRAM-macro implementation or silicon signoff. The empty
`50-detailed-route-drc.rpt` records zero remaining detailed-route violations.
It is accompanied by `openroad.exit` (`0`) and
`openroad-final-drc-excerpt.rpt`, which preserves the final detailed-route and
antenna zero-violation lines from the OpenROAD log. The reset input-delay
warning is retained in
`50-postroute-check-setup.rpt`.

For Chinese documentation, see [README-CN.md](README-CN.md).
