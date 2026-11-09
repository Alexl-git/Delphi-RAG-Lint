<#
  run_doc_apply_refuse_capped_calls.ps1 -- 148 DX: `document --apply` falsely REFUSED a
  declaration whose stored `Calls:` list was CAPPED (146 int: 16 blocks, 147 int: 24).

  THE SHAPE: a long `Calls:` list ends `..., DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds
  (+70 more)</para>`. CallsLostUnseen (Doc.SharedFacts) split on commas and judged the LAST
  entry with its cap suffix glued on; UnitVouchable read ` (+70 more)` as a `(file.pas)` part
  naming a unit "+70 more", which no index holds, so the run said "the chosen --db cannot
  see" a unit it indexes, and the block could never be regenerated (doc-drift forever).

  CASES
    * CAPPED   last entry `uB.S (+5 more)`, uB indexed: NOT refused, the block is rewritten.
    * CONTROL  last entry `uC.T (+2 more)`, uC NOT indexed: still REFUSED, names uC.T, file
               byte-identical (the guard for truly unseen units is not weakened).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-refusecap-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force -Path $root | Out-Null
function Lane-WriteAscii($path, $lines) { [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding)) }
function Lane-Run([string[]]$xs) { $o = & $Exe @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
Lane-WriteAscii (Join-Path $root 'uB.pas') @('unit uB;','interface','procedure Q;','procedure S;','implementation','procedure Q; begin end;','procedure S; begin end;','end.')
$ua = Join-Path $root 'uA.pas'
Lane-WriteAscii $ua @('unit uA;','interface','uses uB;',
  '/// <summary>P.</summary>','/// <remarks>','/// <!-- drag-lint:auto BEGIN -->',
  '/// <para>Calls: uB.Q, uB.S (+5 more)</para>','/// <!-- drag-lint:auto END -->','/// </remarks>',
  'procedure P;','implementation','procedure P; begin Q; end;','end.')
$uc = Join-Path $root 'uA2.pas'
Lane-WriteAscii $uc @('unit uA2;','interface','uses uB;',
  '/// <summary>P2.</summary>','/// <remarks>','/// <!-- drag-lint:auto BEGIN -->',
  '/// <para>Calls: uB.Q, uC.T (+2 more)</para>','/// <!-- drag-lint:auto END -->','/// </remarks>',
  'procedure P2;','implementation','procedure P2; begin Q; end;','end.')
$db = Join-Path $root 'cap.sqlite'
$r = Lane-Run @('index',$root,'--db',$db); Check 'setup: index (uA, uA2, uB; no uC)' ($r.Code -eq 0) "exit $($r.Code)"
$r = Lane-Run @('document','--unit',$ua,'--db',$db,'--apply')
$t = [IO.File]::ReadAllText($ua)
Check 'CAPPED not refused' ($r.Out -notmatch 'REFUSED') $r.Out.Trim()
Check 'CAPPED block rewritten (cap suffix gone)' ($t -notmatch '\(\+5 more\)') $t
Check 'CAPPED real call kept' ($t -match 'Calls: [^\r\n]*uB\.Q') $t
$h0 = (Get-FileHash $uc -Algorithm MD5).Hash
$r = Lane-Run @('document','--unit',$uc,'--db',$db,'--apply')
Check 'CONTROL unseen uC still REFUSED' ($r.Out -match 'REFUSED') $r.Out.Trim()
Check 'CONTROL names uC.T' ($r.Out -match 'uC\.T') ''
Check 'CONTROL file byte-identical' ($h0 -eq (Get-FileHash $uc -Algorithm MD5).Hash) ([IO.File]::ReadAllText($uc))
[IO.Directory]::Delete($root, $true)
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
