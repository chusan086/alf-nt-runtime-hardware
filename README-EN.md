# Runtime-Parameterized ALF-n-t Hardware

This repository is a lean source-and-direct-evidence companion to the paper.
It intentionally excludes the authors' local simulation environment, test
vectors, EDA wrappers, internal ledgers, and historical RTL.

## Contents

- `rtl/shared/`: final runtime-parameterized shared core,
  top `n12_alf_shared_top`.
- `rtl/fixed/m1/` and `rtl/fixed/m4/`: same-source representative fixed cores.
- `reports/`: direct Vivado/OpenROAD reports for the implementation points
  cited by the paper, with author-machine fields sanitized.
- `docs/`: architecture, interface, and porting notes.
- `RELEASE-MANIFEST.md`: payload, evidence scope, and explicit exclusions for
  this release candidate.
- `SHA256SUMS.txt`: SHA-256 for every released payload file except the
  checksum file itself.

The legal domain declared by the shared RTL covers all 112 pairs with
`n=2..15` and `t=0..7`, and accepts runtime `Q` satisfying
`2^(8n+t-1) < Q <= 2^(8n+t)`. FPGA reports use `xc7a200tfbg676-2` and Vivado
2020.2. The authors' full-parameter simulation suite is not distributed in
this lean artifact; the representative implementation reports must not be
read as routed evidence for all 112 pairs. See `reports/README-EN.md` for the
exact report-to-claim mapping and scope limits.

M1 and M4 are frozen same-source controls from the paper's experiment matrix;
this repository does not claim arbitrary-parameter fixed-core generation.
Both fixed directories expose the same top-level module name, so compile only
one fixed directory at a time. See `docs/INTERFACE-EN.md`, `docs/PORTING-EN.md`,
and `docs/FIXED-CORES-EN.md` for the protocol, compile order, and comparison
boundary.

Use PowerShell 7 on Windows, Linux, or macOS to verify both the exact payload
set and every file hash:

```powershell
$root = (Resolve-Path .).Path
$manifest = Join-Path $root 'SHA256SUMS.txt'
$listed = @{}
Get-Content $manifest | ForEach-Object {
  if ($_ -match '^([0-9a-f]{64})  (.+)$') {
    if ($listed.ContainsKey($Matches[2])) { throw "Duplicate entry: $($Matches[2])" }
    $listed[$Matches[2]] = $Matches[1]
  } else {
    throw "Malformed manifest line: $_"
  }
}
$actual = Get-ChildItem $root -Recurse -File |
  Where-Object FullName -ne $manifest |
  ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\','/') }
if (Compare-Object @($listed.Keys | Sort-Object) @($actual | Sort-Object)) {
  throw 'Payload set differs from SHA256SUMS.txt'
}
foreach ($path in $actual) {
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root $path)).Hash.ToLowerInvariant()
  if ($hash -ne $listed[$path]) { throw "SHA-256 mismatch: $path" }
}
```

This artifact is released under the MIT License. During anonymous review the
copyright holder is written as `Anonymous Authors`; replace that line and
rebuild `SHA256SUMS.txt` when the repository is deanonymized.
