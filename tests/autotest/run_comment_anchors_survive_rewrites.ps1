<#
  run_comment_anchors_survive_rewrites.ps1 -- RED repro (DECISION-2026-10-28-comment-anchors).

  Owner ruling 2026-09-22: a `// dl:bk<N>` bookmark stays unless the USER erases it.
  So no engine rewrite path may delete a bookmark, nor copy a `dl:` marker's text into
  generated documentation. Two defects, both measured 2026-10-28:
    A. `lint-all --fix --apply` (unused-local) deletes the whole declaration line,
       taking its trailing `// dl:bk7` with it.
    B. `document --apply` copies an own-line `// dl:ok ...` comment above a method into
       the generated <summary>, so the marker text now exists twice.
  Fixed on gaps/ki-d7: A keeps the dl: comment as an own-line comment; B skips dl: markers when harvesting and inserts the block above them.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }
function Write-Ascii([string]$Path,[string]$Body){ [IO.File]::WriteAllText($Path, ($Body -replace "`r`n","`n" -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_anchors_' + [guid]::NewGuid().ToString('N').Substring(0,8))

function New-Fixture([string]$Name,[string]$Unit){
  $d = Join-Path $scratch $Name
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  Write-Ascii (Join-Path $d 'Fx.pas') $Unit
  Write-Ascii (Join-Path $d 'P.dpr') "program P;`nuses`n  Fx in 'Fx.pas';`nbegin`nend.`n"
  & $exePath index $d --db (Join-Path $d 'x.sqlite') *> $null
  return $d
}

# --- A: unused-local fix must not delete a bookmark -----------------------------
$unitA = @'
unit Fx;
interface
type
  TFx = class(TObject)
  public
    procedure Run;
  end;
implementation
procedure TFx.Run;
var
  Unused: Integer; // dl:bk7 keep me
begin
  // body
end;
end.
'@
$dA = New-Fixture 'a' $unitA
& $exePath lint-all --db (Join-Path $dA 'x.sqlite') --fix --apply *> $null
$outA = [IO.File]::ReadAllText((Join-Path $dA 'Fx.pas'))
Check 'A positive control: the fix ran (unused local gone)' ($outA -notmatch 'Unused: Integer')
Check 'A bookmark dl:bk7 survives the unused-local fix' ($outA -match 'dl:bk7')

# --- B: document --apply must not copy a dl: marker into the summary ------------
$unitB = @'
unit Fx;
interface
type
  TFx = class(TObject)
  public
    // dl:ok magic-literal@abc123 -- marker before method
    procedure Run(aValue: Integer);
  end;
implementation
procedure TFx.Run(aValue: Integer);
begin
  if aValue < 0 then
    raise Exception.Create('x');
end;
end.
'@
$dB = New-Fixture 'b' $unitB
& $exePath document --unit (Join-Path $dB 'Fx.pas') --apply --no-backup --db (Join-Path $dB 'x.sqlite') *> $null
$outB = [IO.File]::ReadAllText((Join-Path $dB 'Fx.pas'))
$n = ([regex]::Matches($outB,'marker before')).Count
Check 'B positive control: a doc block was generated' ($outB -match '///\s*<param')
Check 'B no <summary> carries marker prose' ($outB -notmatch '(?s)<summary>[^<]*marker before')
Check 'B doc block sits ABOVE the marker, marker adjacent to the method' ($outB -match '(?s)///[^\r\n]*\r\n(\s*///[^\r\n]*\r\n)*\s*// dl:ok[^\r\n]*\r\n\s*procedure Run')
Check 'B marker text appears exactly once' ($n -eq 1) ("count=$n")

try { [IO.Directory]::Delete($scratch,$true) } catch { }
if ($script:Failed) { exit 1 } else { exit 0 }
