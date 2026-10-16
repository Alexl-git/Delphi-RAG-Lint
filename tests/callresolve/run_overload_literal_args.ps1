<#
  run_overload_literal_args.ps1 -- two overloads whose arity ranges overlap are
  told apart by the call's LITERAL arguments.

  THE PROBLEM (field report, 2026-09-29). ProjectA's UAuxGeneric declares
    GetReportPDFBase64(aSiteCode, aOrderCode: string; aExprCode: string = '';
                      aCreateTransaction: Boolean = True; ...): string; overload;
    GetReportPDFBase64(aHashType: THashType; out aHash: string; aSiteCode,
                      aOrderCode: string; aExprCode: string = ''; ...): string; overload;
  Their optional parameters make the arity ranges overlap, so arity -- the only
  test PickFromMatches applied -- could not choose, and 16 of the 22 callers came
  out [ambiguous]. `GetReportPDFBase64(FSiteCode, FOrderCode, FExprCode, False,
  False)` cannot be the second: its 4th argument is a Boolean literal and that
  overload's 4th parameter is a string.

  THE FIX (resolver 1.12.0-alpha). ArgsRuleOut rules a candidate out when a
  literal argument cannot go to its parameter: a string/Boolean/numeric literal
  into a BUILTIN parameter of another family, or any literal into var/out.

  CONTROLS:
    * a call with NO literal argument stays ambiguous -- the fix does not guess.
      Since resolver 1.18.0 its string VARIABLES are typed too, and it stays
      ambiguous for a better reason: overload 1 matches arguments 1-3 exactly
      and overload 2 arguments 2-4, a split no candidate dominates;
    * overloads that differ only in a NON-builtin type (two records): a literal
      never rules one out. Until resolver 1.18.0 this call stayed ambiguous;
      its argument is a VARIABLE, GRA: TRecA, and 1.18.0 binds the TRecA
      overload, certain -- the compiler's choice.

  Usage: pwsh -File tests/callresolve/run_overload_literal_args.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_overload_literal_args_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $src 'uReport.pas') @'
unit uReport;

interface

type
  THashKind = (hkSha1, hkSha2);
  TRecA = record X: Integer; end;
  TRecB = record Y: Integer; end;

function GetReport(aPost, aOrder: string; aExpr: string = ''; aTrans: Boolean = True;
  aQuebra: Boolean = True): string; overload;
function GetReport(aKind: THashKind; out aHash: string; aPost, aOrder: string;
  aExpr: string = ''; aTrans: Boolean = True): string; overload;

procedure Put(const A: TRecA; B: Integer = 0); overload;
procedure Put(const A: TRecB; B: Integer = 0); overload;

implementation

function GetReport(aPost, aOrder: string; aExpr: string = ''; aTrans: Boolean = True;
  aQuebra: Boolean = True): string;
begin
  Result := aPost + aOrder;
end;

function GetReport(aKind: THashKind; out aHash: string; aPost, aOrder: string;
  aExpr: string = ''; aTrans: Boolean = True): string;
begin
  aHash := '';
  Result := aPost;
end;

procedure Put(const A: TRecA; B: Integer);
begin
end;

procedure Put(const A: TRecB; B: Integer);
begin
end;

end.
'@

Write-Ascii (Join-Path $src 'uCalls.pas') @'
unit uCalls;

interface

procedure LiteralBool;
procedure LiteralString;
procedure NoLiteral;
procedure UnknownTypes;

implementation

uses
  uReport;

var
  GPost, GOrder, GExpr, GHash: string;
  GRA: TRecA;

procedure LiteralBool;
begin
  GetReport(GPost, GOrder, GExpr, False, False);
end;

procedure LiteralString;
begin
  GetReport(GPost, '01', '', True);
end;

procedure NoLiteral;
begin
  GetReport(GPost, GOrder, GExpr, GHash);
end;

procedure UnknownTypes;
begin
  Put(GRA, 1);
end;

end.
'@

$db = Join-Path $WorkDir 'ovl.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$rows = @()
try { $rows = @(ConvertFrom-Json -InputObject ((& $exePath query find-callers --name GetReport --resolved --json --db $db 2>$null) -join "`n")) } catch {}
function Row([string]$Caller) { return @($rows | Where-Object { $_.caller_qname -eq "uCalls.$Caller" }) }
function Desc([object[]]$R) { return (($R | ForEach-Object { "$($_.target_qname)[$($_.confidence)] line=$($_.line)" }) -join '; ') }

# The first overload is declared FIRST, so it is the lower id and the pre-fix
# answer for an unresolved choice too -- the assertions therefore check the
# CONFIDENCE, which only a real decision can raise to certain.
$b = Row 'LiteralBool'
Check 'precondition: the Boolean-literal call has one resolved row' ($b.Count -eq 1) (Desc $b)
Check 'ASSERT: a Boolean literal where overload 2 wants a string -> overload 1, certain' `
  (($b.Count -eq 1) -and ($b[0].confidence -eq 'certain')) (Desc $b)

$s = Row 'LiteralString'
Check 'ASSERT: a string literal into overload 2''s `out` parameter -> overload 1, certain' `
  (($s.Count -eq 1) -and ($s[0].confidence -eq 'certain')) (Desc $s)

$n = Row 'NoLiteral'
Check 'CONTROL: no literal argument -- still ambiguous, the fix does not guess' `
  (($n.Count -eq 1) -and ($n[0].confidence -eq 'ambiguous')) (Desc $n)

$p = @()
try { $p = @(ConvertFrom-Json -InputObject ((& $exePath query find-callers --name Put --resolved --json --db $db 2>$null) -join "`n")) } catch {}
# Which overload: run_overload_arg_types.ps1 reads the target's declaration line.
Check 'ASSERT: a record VARIABLE decides the overload, certain (resolver 1.18.0)' `
  (($p.Count -eq 1) -and ($p[0].confidence -eq 'certain')) (Desc $p)

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_overload_literal_args_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
