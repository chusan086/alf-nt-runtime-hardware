# ALF-n-t 全参数运行时共享硬件

本仓库是论文配套的精简源码与直接实现证据，不包含作者本地使用的仿真环境、
测试向量、EDA 包装脚本、内部账本或历史 RTL。

## 目录

- `rtl/shared/`：最终全参数运行时共享核，顶层 `n12_alf_shared_top`。
- `rtl/fixed/m1/`、`rtl/fixed/m4/`：同源代表性固定参数核。
- `reports/`：论文引用实现点经机器字段脱敏的直接 Vivado/OpenROAD 报告。
- `docs/`：架构、接口和移植说明。
- `RELEASE-MANIFEST.md`：本发布候选的载荷、证据范围和明确排除项。
- `SHA256SUMS.txt`：除校验和文件自身外，全部发布载荷文件的 SHA-256。

共享核 RTL 声明的合法域覆盖 `n=2..15`、`t=0..7` 的 112 个参数对，并在
`2^(8n+t-1) < Q <= 2^(8n+t)` 内接收合法运行时 `Q`。FPGA 报告使用
`xc7a200tfbg676-2` 和 Vivado 2020.2。具体数字、报告对应关系和口径限制见
`reports/README.md`。作者的全参数仿真验证不随这一精简工件发布，不能把目录中
有限的代表性实现报告误读成 112 个参数点全部完成布局布线。

M1 和 M4 是论文实验矩阵中已冻结的同源固定对照，不代表本仓库提供任意参数
固定核生成能力。两套固定核使用相同的顶层模块名，编译时只能选择其中一套。
接口、编译顺序和固定对照边界分别见 `docs/INTERFACE.md`、
`docs/PORTING.md` 和 `docs/FIXED-CORES.md`。

在 PowerShell 中可用以下命令核对全部发布文件：

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

本工件采用 MIT License。匿名审稿阶段版权人写作 `Anonymous Authors`；去匿名
发布时只需替换版权人并重建 `SHA256SUMS.txt`。

英文说明见 `README-EN.md`。
