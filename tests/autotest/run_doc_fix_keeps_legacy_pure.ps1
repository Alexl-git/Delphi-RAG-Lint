<#
  run_doc_fix_keeps_legacy_pure.ps1 -- a regeneration keeps the legacy
  `<para>Pure</para>` line the checker accepts (B-07, 1.31.5).

  THE DEFECT (docs\INBOX-doc-drift-fix-strips-pure-para.md, 2026-10-13). The
  checker takes the legacy `Pure` element out of the stored block and the
  `Effect-free (proven)` element out of the fresh render before comparing
  (TSharedFacts.BlockDrifted / WithoutLegacyPure), so a block that differs ONLY
  by that line is current -- owner ruling 2026-09-23, the migration is the
  explicit `document --migrate-pure`. The WRITER honoured the same exemption
  only when the line was the ONLY difference (SameButForLegacyPure). The moment
  a block had to be regenerated for ANY other reason, Merged was written as
  rendered, and the render never emits `Pure` -- so the line vanished, and the
  checker then called the new block current. Fixer and checker disagreed: a
  `--fix --apply` was a silent doc regression on every Pure block it touched.

  THE RULE NOW: a regeneration that cannot replace the line with the proven
  `Effect-free (proven)` fact keeps `<para>Pure</para>` where the stored block
  had it (TSharedFacts.KeepLegacyPure), unless `--migrate-pure` is set. The
  writer cannot DISPROVE the claim -- a missing purity verdict says nothing --
  and a writer that cannot see a fact keeps it.

  Fixture: Bump writes a unit-level global, so purity can never prove it
  effect-free -- the fresh render carries NEITHER line. Its block is made stale
  for a vouchable reason (an in-closure ghost caller), so the repair is offered
  and taken. POSITIVE CONTROLS: the ghost IS removed (the fix ran), and
  `document --migrate-pure` DOES drop the line (the keep is opt-out, not a
  rule that can never fire).

  APPLIES on the fixture and compares the file's BYTES -- a dry run proves the
  plan, never the bytes. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-keeppure-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proj = Join-Path $root 'proj'
New-Item -ItemType Directory -Force -Path $proj | Out-Null

$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding))
}
function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
# One declaration's OWN block: walk back from the declaration over its /// run.
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path)
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    $acc = ,$ls[$i] + $acc
  }
  return ($acc -join "`n")
}
# Insert $text as the first fact line of the declaration's own managed block.
function InjectAbove([string]$path, [string]$declPat, [string]$text) {
  $ls = [System.Collections.ArrayList]@([IO.File]::ReadAllLines($path))
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return -1 }
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    if ($ls[$i] -match 'drag-lint:auto BEGIN') { $ls.Insert($i + 1, $text); [IO.File]::WriteAllText($path, (($ls -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding)); return $i + 1 }
  }
  return -1
}

# --- fixture ----------------------------------------------------------------
$uPure = Join-Path $proj 'uPure.pas'
WriteAscii $uPure @(
  'unit uPure;', 'interface',
  'procedure Bump;',
  'procedure UseIt;',
  'implementation',
  'var G: Integer;',
  'procedure Bump;', 'begin', '  Inc(G);', 'end;',
  'procedure UseIt;', 'begin', '  Bump;', '  Bump;', 'end;',
  'end.')
WriteAscii (Join-Path $proj 'Pure.dpr') @('program Pure;', "uses uPure in 'uPure.pas';", 'begin', 'end.')
$db = Join-Path $root 'pure.sqlite'

$r = Run @('index','--project',(Join-Path $proj 'Pure.dpr'),'--db',$db)
Check 'setup: index built' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('document','--unit',$uPure,'--db',$db,'--apply')
Check 'setup: fact blocks engine-written' ($r.Code -eq 0) "exit $($r.Code)"
$blk = BlockAbove $uPure 'procedure Bump;'
Check 'setup: Bump has a managed block naming its caller' ($blk -match 'Called from: uPure\.UseIt') $blk
Check 'setup: the fresh render carries NO purity line for Bump (writes a global)' `
  (($blk -notmatch 'Effect-free') -and ($blk -notmatch '<para>Pure</para>')) 'neither line rendered'

# Age the block: the legacy purity line, and an in-closure ghost caller that
# makes the block stale for a reason this index CAN vouch for.
$i1 = InjectAbove $uPure 'procedure Bump;' '/// <para>Pure</para>'
Check 'setup: legacy Pure line injected into Bump''s own block' ($i1 -ge 0) "line $i1"
$src = [IO.File]::ReadAllText($uPure)
$src = $src.Replace('Called from: uPure.UseIt (uPure.pas)', 'Called from: uPure.NoSuchCaller (uPure.pas), uPure.UseIt (uPure.pas)')
[IO.File]::WriteAllText($uPure, $src, (New-Object System.Text.ASCIIEncoding))
$blk = BlockAbove $uPure 'procedure Bump;'
Check 'setup: ghost caller landed in Bump''s own block' ($blk -match 'NoSuchCaller') 'scoped to Bump'
$r = Run @('index','--project',(Join-Path $proj 'Pure.dpr'),'--db',$db)
Check 'setup: reindexed after the edits' ($r.Code -eq 0) "exit $($r.Code)"
Copy-Item $uPure "$uPure.aged" -Force

# --- CONTROL-1: the aged block IS reported, and offered as fixable ----------
$d = Run @('doc-drift','--qname','uPure.Bump','--db',$db)
Check 'CONTROL-1 the ghost makes the block stale' ($d.Out -match 'ddFactsBlockStale') $d.Out.Trim()
Check 'CONTROL-1 and the repair is offered (this index vouches for the ghost)' ($d.Out -match '\[FIXABLE\]') $d.Out.Trim()

# --- CASE-FIX: lint --fix --apply keeps the Pure line ------------------------
$r = Run @('lint',$uPure,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply')
$blk = BlockAbove $uPure 'procedure Bump;'
Check 'CASE-FIX the fix RAN: the ghost caller is gone (positive control)' ($blk -notmatch 'NoSuchCaller') $blk
Check 'CASE-FIX the real caller survived' ($blk -match 'uPure\.UseIt') $blk
Check 'CASE-FIX <para>Pure</para> is KEPT by the regeneration' ($blk -match '<para>Pure</para>') $blk
Check 'CASE-FIX the file is still 7-bit ASCII with CRLF' `
  ((-not ([IO.File]::ReadAllBytes($uPure) | Where-Object { $_ -gt 127 })) -and ([IO.File]::ReadAllText($uPure) -notmatch '(?<!\r)\n')) 'bytes'

# --- CASE-AGREE: the checker calls the written block current, and a second
# fix writes nothing (fixed point) --------------------------------------------
$r = Run @('index','--project',(Join-Path $proj 'Pure.dpr'),'--db',$db)
$d = Run @('doc-drift','--qname','uPure.Bump','--db',$db)
Check 'CASE-AGREE checker: the block the fixer wrote is current' ($d.Out -notmatch 'ddFactsBlockStale') $d.Out.Trim()
$h0 = (Get-FileHash $uPure -Algorithm MD5).Hash
$null = Run @('lint',$uPure,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply')
$h1 = (Get-FileHash $uPure -Algorithm MD5).Hash
Check 'CASE-AGREE fixer: a second --fix --apply is byte-identical' ($h0 -eq $h1) "$h0 vs $h1"

# --- CASE-DOC: document --unit --apply on the aged file keeps the line too ----
Copy-Item "$uPure.aged" $uPure -Force
$r = Run @('index','--project',(Join-Path $proj 'Pure.dpr'),'--db',$db)
$r = Run @('document','--unit',$uPure,'--db',$db,'--apply')
$blk = BlockAbove $uPure 'procedure Bump;'
Check 'CASE-DOC document --apply removed the ghost (it regenerated)' ($blk -notmatch 'NoSuchCaller') $blk
Check 'CASE-DOC document --apply KEPT <para>Pure</para>' ($blk -match '<para>Pure</para>') $blk

# --- CONTROL-2: --migrate-pure is the opt-out, and it still drops the line ----
Copy-Item "$uPure.aged" $uPure -Force
$r = Run @('index','--project',(Join-Path $proj 'Pure.dpr'),'--db',$db)
$r = Run @('document','--unit',$uPure,'--db',$db,'--apply','--migrate-pure')
$blk = BlockAbove $uPure 'procedure Bump;'
Check 'CONTROL-2 document --migrate-pure DROPS the legacy line (the keep is opt-out)' ($blk -notmatch '<para>Pure</para>') $blk
Check 'CONTROL-2 ...and still regenerated the rest' ($blk -notmatch 'NoSuchCaller') $blk

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
