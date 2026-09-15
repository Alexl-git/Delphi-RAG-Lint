<#
  run_doc_exception_reraise_var.ps1 -- `raise E` names the handler's declared
  TYPE in <exception cref>, never the handler VARIABLE.

  THE DEFECT (PLAN-autofix-campaign 4.2, sample B, BASICSF.pas:5037-5046)
  --------------------------------------------------------------------------------
      except
        on E: Exception do
        begin
          ...
          raise E;
        end;
      end;

  produced `/// <exception cref="E"><!-- drag-lint:auto --></exception>`. The
  raise scanner takes the identifier after `raise` as the class name, which is
  right for `raise EFoo.Create(...)` and wrong for a re-raise through the
  handler variable: `E` is not a type, and DocInsight renders a link to a class
  called E. A generated tag that names a class which does not exist is a
  FABRICATION -- the failure class this repo treats as worse than silence.

  WHERE THE FIX LIVES, and why this guard can exist without an extractor bump
  --------------------------------------------------------------------------------
  Raises are NOT extracted at index time. TDocFactsBuilder.MineRaises /
  MineRaisesDetailed scan the routine's source lines when `document` (or
  doc-drift) runs. So the repair is render-time in DRagLint.Doc.Facts and costs
  no DRAGLINT_EXTRACTOR_VERSION bump.

  THE RULE UNDER TEST
  --------------------------------------------------------------------------------
    * `raise <Ident>` with NO `.Ctor` / `(` after the identifier can never be a
      class (a class reference is not an object; `raise EFoo;` does not compile).
      It is a VARIABLE. If an `on <Ident>: <Type> do` handler binding precedes
      it in the body, the tag names <Type>. If no binding is known, NO tag is
      emitted -- absence over a wrong name.
    * `raise <Class>.Create(...)` is unchanged, message and all (positive
      control: without it, "cref=E is gone" would also pass on an engine that
      stopped mining raises altogether).
    * `raise Unit.Class.Create(...)` names the CLASS (the segment before the
      constructor), not the unit -- the same "first identifier" defect through
      another door.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_reraise_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }
# The /// block immediately above `procedure <Name>;` / `function <Name>(`.
function Get-DocBlock([string]$Text, [string]$Name) {
  $lines = $Text -split "`r?`n"
  $ix = -1
  for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match "^\s*(procedure|function)\s+$Name\b") { $ix = $i; break } }
  if ($ix -lt 0) { return '' }
  $acc = @()
  for ($j = $ix - 1; $j -ge 0; $j--) { if ($lines[$j] -match '^\s*///') { $acc = ,$lines[$j] + $acc } else { break } }
  return ($acc -join "`n")
}

$src = Join-Path $scratch 'reraise.pas'
$db  = Join-Path $scratch 'r.sqlite'

Write-Ascii $src @'
unit reraise;

interface

uses
  System.SysUtils;

procedure ReRaiseBase;
procedure ReRaiseTyped;
procedure ReRaiseTwoHandlers;
procedure PlainCtor;
procedure DottedCtor;
procedure UnknownVar;
procedure BareReRaise;
procedure Quiet;

implementation

procedure ReRaiseBase;
begin
  try
    Beep;
  except
    on E: Exception do
    begin
      Sleep(1);
      raise E;
    end;
  end;
end;

procedure ReRaiseTyped;
begin
  try
    Beep;
  except
    on E: EConvertError do
      raise E;
  end;
end;

procedure ReRaiseTwoHandlers;
begin
  try
    Beep;
  except
    on E: EAbort do
      raise E;
    on E: EInOutError do
      raise E;
  end;
end;

procedure PlainCtor;
begin
  raise EPlainThing.Create('plain message');
end;

procedure DottedCtor;
begin
  raise System.SysUtils.Exception.Create('dotted message');
end;

procedure UnknownVar;
var
  Err: Exception;
begin
  Err := Exception.Create('made elsewhere');
  raise Err;
end;

procedure BareReRaise;
begin
  try
    Beep;
  except
    raise;
  end;
end;

procedure Quiet;
begin
end;

end.
'@

$md5Orig = Get-FileMd5 $src

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5First = Get-FileMd5 $src
  $text = [IO.File]::ReadAllText($src)
  Write-Host '--- applied file ---' -ForegroundColor DarkGray
  Write-Host $text -ForegroundColor DarkGray

  # --- THE DEFECT: the handler variable is never a cref -----------------------
  Check 'no <exception cref="E"> anywhere in the file' `
    (-not ($text -match '<exception cref="E">')) $text

  $b = Get-DocBlock $text 'ReRaiseBase'
  Check 'ReRaiseBase: `on E: Exception do ... raise E` -> cref="Exception"' `
    ($b -match '<exception cref="Exception">') $b
  $b = Get-DocBlock $text 'ReRaiseTyped'
  Check 'ReRaiseTyped: `on E: EConvertError do raise E` -> cref="EConvertError"' `
    ($b -match '<exception cref="EConvertError">') $b
  $b = Get-DocBlock $text 'ReRaiseTwoHandlers'
  Check 'ReRaiseTwoHandlers: the SAME variable name bound twice resolves to BOTH types' `
    (($b -match '<exception cref="EAbort">') -and ($b -match '<exception cref="EInOutError">')) $b
  Check '  ...and to nothing else' `
    (([regex]::Matches($b, '<exception cref=')).Count -eq 2) $b

  # --- POSITIVE CONTROL: the working shape is untouched, message included ----
  $b = Get-DocBlock $text 'PlainCtor'
  Check 'CONTROL: PlainCtor keeps cref="EPlainThing" WITH its mined message' `
    ($b -match '<exception cref="EPlainThing"><!-- drag-lint:auto exc -->plain message</exception>') $b

  # --- the sibling shape: a unit-qualified constructor names the CLASS ------
  $b = Get-DocBlock $text 'DottedCtor'
  Check 'DottedCtor: `raise System.SysUtils.Exception.Create` -> cref="Exception", not "System"' `
    (($b -match '<exception cref="Exception">') -and -not ($b -match '<exception cref="System">')) $b
  Check '  ...and its message is still mined' `
    ($b -match 'dotted message') $b

  # --- absence over wrong: a bare variable with no handler binding ----------
  $b = Get-DocBlock $text 'UnknownVar'
  Check 'UnknownVar: `raise Err` (a local, no `on` binding) emits NO <exception> at all' `
    (-not ($b -match '<exception')) $b
  $b = Get-DocBlock $text 'BareReRaise'
  Check 'BareReRaise: a bare `raise;` emits NO <exception>' `
    (-not ($b -match '<exception')) $b
  $b = Get-DocBlock $text 'Quiet'
  Check 'CONTROL: Quiet (raises nothing) gains no <exception>' `
    (-not ($b -match '<exception')) $b

  # --- idempotency ----------------------------------------------------------
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'IDEMPOTENT: reindex + a second --apply is byte-identical' `
    ((Get-FileMd5 $src) -eq $md5First) ("first=$md5First second=" + (Get-FileMd5 $src))

  Check 'every emitted /// line is 7-bit ASCII' `
    (@([IO.File]::ReadAllLines($src) | Where-Object { $_ -match '^\s*///' -and ($_.ToCharArray() | Where-Object { [int]$_ -gt 126 }) }).Count -eq 0)

  # --- CONTROL: strip is the exact inverse ------------------------------------
  # The fixture has NO hand-written doc at all, so after `--strip --apply` the
  # file must be the original bytes again. This is what proves the generated
  # <exception> tags -- AUTO_MARK (no message) and AUTO_EXC (message) alike --
  # are recognised by the stripper; before 2026-09-15 it knew neither opener.
  & $exePath document --unit $src --db $db --strip --apply 2>$null | Out-Null
  Check 'document --strip --apply exits 0' ($LASTEXITCODE -eq 0)
  Check 'INVERSE: strip(apply(original)) is byte-identical to the original' `
    ((Get-FileMd5 $src) -eq $md5Orig) ("orig=$md5Orig strip=" + (Get-FileMd5 $src))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
