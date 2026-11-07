<#
  run_doc_orphan_param_keeps_bytes.ps1 -- `document --apply` and <param> tags
  the signature does not name one-to-one (E-DOC-ORPHAN-PARAM, wave 146).

  THE REPORT (docs\INBOX-doc-orphan-param-whitespace-and-false-stale.md, BASICSF
  copy check 2026-11-06): with `procedure WordPosition(const N: cardinal;
  const S, WordDelims: string; var Pos: cardinal)` and the hand tags
  `<param name="S, WordDelims"> (string) </param>` and
  `<param name="var Pos"> (cardinal) </param>`, --apply marked both "param no
  longer exists" and re-emitted them without their blanks.

  CASES
    * MULTI   a tag naming several real params is neither marked stale nor
              rewritten, and no auto tag is added for S or WordDelims.
    * PREFIX  `var Pos` names the real parameter Pos: same.
    * ORPHAN  a true orphan (`Gone`) IS marked, and keeps its own bytes
              (blanks inside the tag) -- positive control: the stale path ran.
  Bytes are compared on the APPLIED file. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-orphanparam-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$u = Join-Path $root 'uWp.pas'
$lines = @(
  'unit uWp;', 'interface',
  '/// <summary>Finds a word.</summary>',
  '/// <param name="N"> (count) </param>',
  '/// <param name="S, WordDelims"> (string) </param>',
  '/// <param name="var Pos"> (cardinal) </param>',
  '/// <param name="Gone"> (old) </param>',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Integer;',
  'implementation',
  'function WordPosition(const N: cardinal; const S, WordDelims: string; var Pos: cardinal): Integer;',
  'begin', '  Result:= 0;', 'end;', 'end.')
[IO.File]::WriteAllText($u, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.ASCIIEncoding))
$db = Join-Path $root 'wp.sqlite'
& $Exe index $root --db $db 2>&1 | Out-Null
Check 'setup: index built' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
$o = & $Exe document --unit $u --db $db --apply 2>&1 | Out-String
Check 'setup: document --apply ran' ($LASTEXITCODE -eq 0) $o.Trim()
$t = [IO.File]::ReadAllText($u)
Check 'MULTI tag keeps its bytes' ($t.Contains('/// <param name="S, WordDelims"> (string) </param>')) $t
Check 'MULTI no "no longer exists" on it' ($t -notmatch 'WordDelims"[^\r\n]*no longer exists') ''
Check 'MULTI no auto tag for S' ($t -notmatch '<param name="S"') ''
Check 'MULTI no auto tag for WordDelims' ($t -notmatch '<param name="WordDelims"') ''
Check 'PREFIX var Pos keeps its bytes' ($t.Contains('/// <param name="var Pos"> (cardinal) </param>')) ''
Check 'PREFIX no auto tag for Pos' ($t -notmatch '<param name="Pos"') ''
Check 'ORPHAN true orphan IS marked (positive control)' ($t -match 'name="Gone">[^\r\n]*no longer exists') $t
Check 'ORPHAN keeps its inner blanks' ($t -match 'name="Gone"> \(old\) </param>') ''
$h0 = (Get-FileHash $u -Algorithm MD5).Hash
$null = & $Exe document --unit $u --db $db --apply 2>&1
Check 'FIXED second apply is byte-identical' ($h0 -eq (Get-FileHash $u -Algorithm MD5).Hash) ''
[IO.Directory]::Delete($root, $true)
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
