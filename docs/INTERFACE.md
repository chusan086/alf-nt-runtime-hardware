# Streaming interface

All three released tops use one 32-bit ready/valid request channel and one
32-bit ready/valid response channel:

| Signal | Direction | Meaning |
|---|---:|---|
| `clk_i` | input | rising-edge clock |
| `rst_ni` | input | active-low reset |
| `req_valid_i` | input | request word is valid |
| `req_ready_o` | output | request word is accepted when high with valid |
| `req_data_i[31:0]` | input | request word |
| `rsp_valid_o` | output | response word is valid |
| `rsp_ready_i` | input | response word is accepted when high with valid |
| `rsp_data_o[31:0]` | output | response word |

The shared top is `n12_alf_shared_top`. Both fixed directories use
`n12_alf_matched_fixed_v3_top`; compile only one fixed directory at a time.

The shared and released M1/M4 tops accept 20 little-word-order request words:

| Word(s) | Field |
|---:|---|
| 0--3 | 128-bit key, least-significant word first |
| 4--5 | 64-bit application/context identifier |
| 6--9 | 128-bit tweak |
| 10--13 | 128-bit `Q` |
| 14 | configuration: `n[3:0]`, `t[6:4]`, decrypt bit 7, cycle-walking bit 8, resident-context reuse bit 9; bits 31:10 zero |
| 15--18 | 128-bit input |
| 19 | command, currently `1` |

The response is five words: four 32-bit result words followed by one status
word. A word transfers only when valid and ready are both high. Request input
is not accepted while a previous operation or response is outstanding.

Status `0` means the request completed successfully. Status `1` means the
request was rejected or terminated with an error; in that case all four result
words are zero. Every request requires command word 19 to equal `1`, reserved
configuration bits 31:10 to be zero, and the 128-bit input to be smaller than
`Q`. The shared core additionally checks the documented `(n,t,Q)` legal domain.
The released M1/M4 fixed tops retain the 20-word transport for matched
comparison and require the transmitted `Q`, `n`, and `t` to equal the fixed
instance constants exactly.
