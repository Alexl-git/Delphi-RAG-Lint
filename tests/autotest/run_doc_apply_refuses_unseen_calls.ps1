<#
  run_doc_apply_refuses_unseen_calls.ps1 -- `document --apply` refuses, and says
  why, instead of deleting a fact the chosen DB cannot see (E-DOC-REFUSE, wave 146).

  THE SHAPE: uA.P calls uB.Q. A block written from a DB that holds BOTH units
  says `Calls: uB.Q` (and a seealso). Re-applied from a DB that holds only uA,
  the fresh render no longer names uB.Q -- the index cannot see it -- and the
  regeneration silently deleted both lines. Inbound entries were already kept
  (run_doc_apply_keeps_unseen_entries); an OUTBOUND `Calls:` entry was not.

  CASES
    * REFUSE   the declaration is left byte-identical, the run says REFUSED and
               names the entry and the unit; exit 0 (nothing failed, nothing written).
    * CONTROL  the same declaration applied from the WIDE db is not refused (the
               refusal keys on what the DB cannot see, not on every change).
    * DRIFT    an entry that vanished because the call really went, with the unit
               INDEXED, is reaped as before (positive control: the writer still writes).
  Bytes are compared on the applied file. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-refuse-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$a = Join-Path $root 'a'; $b = Join-Path $root 'b'
New-Item -ItemType Directory -Force -Path $a, $b | Out-Null
function WriteAscii($path, $lines) { [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding)) }
function Run([string[]]$xs) { $o = & $Exe @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
WriteAscii (Join-Path $b 'uB.pas') @('unit uB;','interface','procedure Q;','implementation','procedure Q; begin end;','end.')
$ua = Join-Path $a 'uA.pas'
$srcLines = @('unit uA;','interface','uses uB;','procedure P;','implementation','procedure P; begin Q; end;','procedure R; begin P; end;','end.')
WriteAscii $ua $srcLines
$narrow = Join-Path $root 'narrow.sqlite'; $wide = Join-Path $root 'wide.sqlite'
$null = Run @('index',$a,'--db',$wide); $null = Run @('index',$b,'--db',$wide)
$r = Run @('index',$a,'--db',$narrow); Check 'setup: narrow index (uA only)' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('document','--unit',$ua,'--db',$wide,'--apply'); Check 'setup: block written from the WIDE db' ($r.Code -eq 0) $r.Out.Trim()
$before = [IO.File]::ReadAllText($ua)
Check 'setup: block carries Calls: uB.Q' ($before -match 'Calls: uB\.Q') $before
$h0 = (Get-FileHash $ua -Algorithm MD5).Hash
$r = Run @('document','--unit',$ua,'--db',$narrow,'--apply')
Check 'REFUSE the file is byte-identical' ($h0 -eq (Get-FileHash $ua -Algorithm MD5).Hash) ([IO.File]::ReadAllText($ua))
Check 'REFUSE the run says REFUSED' ($r.Out -match 'REFUSED') $r.Out.Trim()
Check 'REFUSE the run names the entry' ($r.Out -match 'uB\.Q') ''
Check 'REFUSE exit 0' ($r.Code -eq 0) "exit $($r.Code)"
# CONTROL: the wide db may write
$r = Run @('document','--unit',$ua,'--db',$wide,'--apply')
Check 'CONTROL wide db is not refused' ($r.Out -notmatch 'REFUSED') $r.Out.Trim()
# DRIFT: the call really goes; uB is indexed in the wide db, so the entry is reaped
WriteAscii $ua @('unit uA;','interface','uses uB;','procedure P;','implementation','procedure P; begin end;','procedure R; begin P; end;','end.')
$t = [IO.File]::ReadAllText($ua)
$injected = $before -replace '(?s)implementation.*$', "implementation`r`nprocedure P; begin end;`r`nprocedure R; begin P; end;`r`nend.`r`n"
[IO.File]::WriteAllText($ua, $injected, (New-Object Text.ASCIIEncoding))
$r = Run @('index',$a,'--db',$wide)
$r = Run @('document','--unit',$ua,'--db',$wide,'--apply')
Check 'DRIFT reaped with the unit indexed (positive control)' (([IO.File]::ReadAllText($ua) -notmatch 'Calls: uB\.Q') -and ($r.Out -notmatch 'REFUSED')) ([IO.File]::ReadAllText($ua))
[IO.Directory]::Delete($root, $true)
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
