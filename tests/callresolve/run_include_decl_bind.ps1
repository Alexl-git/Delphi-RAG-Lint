<#
  run_include_decl_bind.ps1 -- a ref to a symbol DECLARED in an include file of a used unit binds
  to that symbol as a member of the host unit's scope (wave 152c lane RINC).

  Fixture tests\callresolve\fixtures\include_decl_bind:
    IncDeclA.pas   interface {$I IncDeclA_decls.inc} (procedure P, const cIncLimit, class TFoo),
                   implementation {$I IncDeclA_impl.inc} (const cImplOnly); TBar / Q in the .pas body.
    IncDeclB.pas   uses IncDeclA: TFoo var + TFoo.Create, P call, cIncLimit / cImplOnly reads, TBar, Q.
    IncDeclC.pas   uses nothing, names TFoo / P / cIncLimit.

  Bound (RED on the 1.50.0-alpha base, all NULL): B's TFoo type_use + read, P call (+ call edge),
  cIncLimit read; A's own TFoo (the TFoo.Run header).
  Controls: TBar / Q (declared in the .pas body) bind to IncDeclA.pas as before; cImplOnly (an
  IMPLEMENTATION include) stays unbound from B; C (no uses of IncDeclA) binds none of the three --
  visibility follows the uses scope, not the name.

  Usage: pwsh -File tests\callresolve\run_include_decl_bind.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
. "$repo\tests\autotest\lib\HermeticEngine.ps1"; $exePath = Get-HermeticEngine $exePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_incdecl_$PID"
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}
function Invoke-Rows([string]$Db, [string]$Query) {
  $raw = (& $exePath sql --db $Db --json --query $Query 2>$null) -join "`n"
  $j = $raw | ConvertFrom-Json
  $cols = @($j.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($j.rows)) {
    $o = [ordered]@{}
    for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $r[$i] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}
try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $fx = Join-Path $scratch 'fx'
  [void](New-Item -ItemType Directory -Force -Path $fx)
  Copy-Item (Join-Path $PSScriptRoot 'fixtures\include_decl_bind\*') $fx
  $db = Join-Path $scratch 'incdecl.sqlite'
  & $exePath index $fx --db $db 2>&1 | Out-Null
  $q = "SELECT f.path AS src, r.name_text AS name, r.kind AS kind, r.start_line AS line, " +
       "COALESCE(tf.path, '') AS target, (SELECT COUNT(*) FROM call_edges c WHERE c.ref_id = r.id AND c.target_symbol_id = r.symbol_id) AS edges " +
       "FROM refs r JOIN files f ON f.id = r.file_id LEFT JOIN symbols s ON s.id = r.symbol_id LEFT JOIN files tf ON tf.id = s.file_id " +
       "WHERE r.name_text IN ('TFoo', 'P', 'cIncLimit', 'cImplOnly', 'TBar', 'Q', 'R', 'TBaz') AND r.kind IN ('type_use', 'read', 'call')"
  $rows = Invoke-Rows $db $q
  Check 'the fixture produced the 17 candidate refs' ($rows.Count -eq 17) "$($rows.Count)"
  function Target([string]$Src, [string]$Name, [string]$Kind) {
    $hit = @($rows | Where-Object { (Split-Path $_.src -Leaf) -eq $Src -and $_.name -eq $Name -and $_.kind -eq $Kind })
    if ($hit.Count -ne 1) { return "<$($hit.Count) refs>" }
    if ($hit[0].target -eq '') { return '' }
    return (Split-Path $hit[0].target -Leaf)
  }
  $inc = 'IncDeclA_decls.inc'
  Check 'B: TFoo (type_use) binds to the include declaration' ((Target 'IncDeclB.pas' 'TFoo' 'type_use') -eq $inc) (Target 'IncDeclB.pas' 'TFoo' 'type_use')
  Check 'B: TFoo (read, TFoo.Create) binds to the include declaration' ((Target 'IncDeclB.pas' 'TFoo' 'read') -eq $inc) (Target 'IncDeclB.pas' 'TFoo' 'read')
  Check 'B: P (call) binds to the include declaration' ((Target 'IncDeclB.pas' 'P' 'call') -eq $inc) (Target 'IncDeclB.pas' 'P' 'call')
  $pEdge = @($rows | Where-Object { (Split-Path $_.src -Leaf) -eq 'IncDeclB.pas' -and $_.name -eq 'P' -and $_.kind -eq 'call' })
  Check 'B: P has a call edge to the include declaration' (($pEdge.Count -eq 1) -and ($pEdge[0].edges -eq 1)) "$($pEdge.edges)"
  Check 'B: cIncLimit (read) binds to the include declaration' ((Target 'IncDeclB.pas' 'cIncLimit' 'read') -eq $inc) (Target 'IncDeclB.pas' 'cIncLimit' 'read')
  Check 'A: TFoo (the TFoo.Run header in the host) binds to the include declaration' ((Target 'IncDeclA.pas' 'TFoo' 'type_use') -eq $inc) (Target 'IncDeclA.pas' 'TFoo' 'type_use')
  # Controls.
  Check 'control: TBar (type_use) still binds to IncDeclA.pas' ((Target 'IncDeclB.pas' 'TBar' 'type_use') -eq 'IncDeclA.pas') (Target 'IncDeclB.pas' 'TBar' 'type_use')
  Check 'control: TBar (read) still binds to IncDeclA.pas' ((Target 'IncDeclB.pas' 'TBar' 'read') -eq 'IncDeclA.pas') (Target 'IncDeclB.pas' 'TBar' 'read')
  Check 'control: Q (call) still binds to IncDeclA.pas' ((Target 'IncDeclB.pas' 'Q' 'call') -eq 'IncDeclA.pas') (Target 'IncDeclB.pas' 'Q' 'call')
  Check 'control: cImplOnly (an implementation include) stays unbound from B' ((Target 'IncDeclB.pas' 'cImplOnly' 'read') -eq '') (Target 'IncDeclB.pas' 'cImplOnly' 'read')
  Check 'control: C (no uses) does not bind TFoo' ((Target 'IncDeclC.pas' 'TFoo' 'type_use') -eq '') (Target 'IncDeclC.pas' 'TFoo' 'type_use')
  Check 'control: C (no uses) does not bind P' ((Target 'IncDeclC.pas' 'P' 'call') -eq '') (Target 'IncDeclC.pas' 'P' 'call')
  Check 'control: C (no uses) does not bind cIncLimit' ((Target 'IncDeclC.pas' 'cIncLimit' 'read') -eq '') (Target 'IncDeclC.pas' 'cIncLimit' 'read')
  # 152c RINC2 (a): a routine header that FOLLOWS a type section in an include (IncDeclD_decls.inc:
  # `type TBaz = class end;` then `procedure R;`) is a symbol of the include, and E's call binds to it.
  $incD = 'IncDeclD_decls.inc'
  $rSym = Invoke-Rows $db "SELECT s.kind AS kind, s.start_line AS line FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = 'R' AND f.path LIKE '%IncDeclD_decls.inc'"
  Check '(a) IncDeclD_decls.inc declares R (a routine after a type section), line 5' (($rSym.Count -eq 1) -and ($rSym[0].kind -eq 'procedure') -and ($rSym[0].line -eq 5)) "$($rSym.Count) $($rSym.kind) $($rSym.line)"
  Check '(a) E: R (call) binds to the include declaration' ((Target 'IncDeclE.pas' 'R' 'call') -eq $incD) (Target 'IncDeclE.pas' 'R' 'call')
  Check '(a) control: E: TBaz (type_use) binds to the include declaration' ((Target 'IncDeclE.pas' 'TBaz' 'type_use') -eq $incD) (Target 'IncDeclE.pas' 'TBaz' 'type_use')
  Check '(a) control: F (no uses) does not bind R' ((Target 'IncDeclF.pas' 'R' 'call') -eq '') (Target 'IncDeclF.pas' 'R' 'call')
} finally {  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green; exit 0
