<#
  run_convert_single_pass.ps1 -- pins the SINGLE-PASS behaviour of convert-apply (INBOX-REPLY-chain1 E1/E3)
  and the book warnings that follow from it (1.37.0 CHAIN H1 + H3).

  H1  book '#convert TA -> TB' + '#convert TB -> TC': after --apply the .pas and the .dfm both say TB
      (checked separately); a book '#convert TA -> TC' converts to TC (positive control: the fixture
      converts at all).
  H3  a chained book warns 'line 2: warning: chain: TB is also a From type (line 1 converts TA -> TB;
      single pass, TA ends as TB)'; a book with two '#convert TA -> ..' lines warns
      'line 2: warning: duplicate From TA (line 1 wins)'. Warnings never change the exit code.
      The texts start with 'line N: warning: chain' / 'line N: warning: duplicate From' so the
      ConvRulesEditor can recognise them and not double-mark.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_single_pass_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }

Write-Ascii (P 'ChainLib.pas') @'
unit ChainLib;

interface

uses
  System.Classes;

type
  TA = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TB = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TC = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

implementation

end.
'@
function NewUnit([string]$Dir) {
  New-Item -ItemType Directory $Dir | Out-Null
  Copy-Item (P 'ChainLib.pas') $Dir
  Write-Ascii (Join-Path $Dir 'ChainDM.pas') @'
unit ChainDM;

interface

uses
  System.Classes, ChainLib;

type
  TChainDM = class(TDataModule)
    x: TA;
  end;

implementation

{$R *.dfm}

end.
'@
  Write-Ascii (Join-Path $Dir 'ChainDM.dfm') @'
object ChainDM: TChainDM
  object x: TA
    Caption = 'hello'
  end
end
'@
}
$Chain  = "#convert ChainLib.TA -> ChainLib.TB`n#convert ChainLib.TB -> ChainLib.TC`n"
$Direct = "#convert ChainLib.TA -> ChainLib.TC`n"
$Dup    = "#convert ChainLib.TA -> ChainLib.TB`n#convert ChainLib.TA -> ChainLib.TC`n"

function RunBook([string]$Tag, [string]$Book, [switch]$Apply) {
  $dir = P $Tag
  NewUnit $dir
  Write-Ascii (Join-Path $dir 'x.rules') $Book
  $db = Join-Path $dir 'fx.sqlite'
  $null = & $Exe index $dir --db $db 2>&1
  $args2 = @('convert-apply', '--unit', (Join-Path $dir 'ChainDM.pas'), '--rules', (Join-Path $dir 'x.rules'), '--db', $db)
  if ($Apply) { $args2 += @('--apply', '--no-backup') }
  $out = (& $Exe @args2 2>&1) -join "`n"
  return [pscustomobject]@{ Dir = $dir; Out = $out; Exit = $LASTEXITCODE
    Pas = [IO.File]::ReadAllText((Join-Path $dir 'ChainDM.pas')); Dfm = [IO.File]::ReadAllText((Join-Path $dir 'ChainDM.dfm')) }
}

# ---- H1: single pass -----------------------------------------------------------------
$r = RunBook 'h1' $Chain -Apply
Check 'H1a chained book: exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
Check 'H1b chained book: the .pas says TB (not TC)' (($r.Pas -match 'x: TB;') -and ($r.Pas -notmatch 'x: TC;')) $r.Pas
Check 'H1c chained book: the .dfm says TB (not TC)' (($r.Dfm -match 'object x: TB') -and ($r.Dfm -notmatch '\bTC\b')) $r.Dfm
$r = RunBook 'h1c' $Direct -Apply
Check 'H1+ control: TA -> TC converts the .pas to TC' ($r.Pas -match 'x: TC;') "$($r.Out) || $($r.Pas)"
Check 'H1+ control: TA -> TC converts the .dfm to TC' ($r.Dfm -match 'object x: TC') "$($r.Out) || $($r.Dfm)"

# ---- H3: warnings --------------------------------------------------------------------
$r = RunBook 'h3a' $Chain
Check 'H3a chain warning text (convert-apply, dry run)' `
  ($r.Out -match '(?m)^\s*line 2: warning: chain: TB is also a From type \(line 1 converts TA -> TB; single pass, TA ends as TB\)') $r.Out
Check 'H3a ... exit code unchanged (warnings only)' ($r.Exit -eq 0) "exit=$($r.Exit)"
$v = (& $Exe convert-validate --rules (Join-Path $r.Dir 'x.rules') 2>&1) -join "`n"
Check 'H3a chain warning text (convert-validate)' ($v -match '(?m)^\s*line 2: warning: chain: TB is also a From type') $v
$r = RunBook 'h3b' $Dup
Check 'H3b duplicate-From warning text' ($r.Out -match '(?m)^\s*line 2: warning: duplicate From TA \(line 1 wins\)') $r.Out
Check 'H3b ... exit code unchanged' ($r.Exit -eq 0) "exit=$($r.Exit)"
$r = RunBook 'h3c' $Direct
Check 'H3c a clean book prints neither warning' (($r.Out -notmatch 'warning: chain') -and ($r.Out -notmatch 'duplicate From')) $r.Out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath "C:\TEMP\draglint_convert_single_pass_$PID") { Remove-Item -LiteralPath "C:\TEMP\draglint_convert_single_pass_$PID" -Recurse -Force -ErrorAction SilentlyContinue }
}
