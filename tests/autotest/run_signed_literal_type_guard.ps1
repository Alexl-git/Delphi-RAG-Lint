<#
  run_signed_literal_type_guard.ps1 -- a SIGNED numeric literal still infers its
  type, even when a space separates the sign from the digits.

  THE DEFECT. `Tight = -2` parses as a literalNumber with the sign folded in and
  has always typed as Integer. `Spaced = - 1` -- a space after the sign, which is
  what ORM3's iFOLDERS.PAS literally contains -- parses as exprUnary instead, and
  ConstSignatureOf inferred only from literal NODES, so the declaration came out
  untyped:

      old:  "signature": "= - 1"
      new:  "signature": "Integer = - 1"

  Integer is not a guess there; it is the only thing it can be.

  WHAT THE CONTROLS ARE FOR. The cheap version of this fix is "infer from
  expressions too", which would invent types for things the extractor cannot
  actually read. The narrowing is the design, so it is what gets asserted:

    2  Spaced   = - 1     -> Integer   <- THE FIX
    3  NegFloat = - 1.5   -> Extended  <- classified from the OPERAND
    4  NegHex   = - $1E5  -> Integer   <- POSITIVE CONTROL (see below)
    5  NotTrue  = not True-> UNTYPED   <- POSITIVE CONTROL: only + and - qualify
    6  Sum      = 1 + 1   -> UNTYPED   <- POSITIVE CONTROL: not all expressions

  ASSERTION 4 IS THE SHARP ONE. The operand's own text is classified, never the
  whole value text. Classifying '- $1E5' would fail the '$'-prefix test (its
  first character is '-'), fall through to the exponent test, see the 'E', and
  type it Extended. A hex literal is an Integer. If this assertion ever goes red,
  the classifier is being handed the wrong string.

  5 AND 6 FAIL LOUDLY IF THE NARROWING IS LOST: `not True` is Boolean and `1 + 1`
  is a binary expression -- neither is a signed literal, and typing either as a
  number would be fabrication.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$w = Join-Path C:\TEMP 'draglint_signed_literal'
if (Test-Path $w) { Remove-Item $w -Recurse -Force }
New-Item -ItemType Directory $w | Out-Null

$src = @'
unit uConsts;

interface

const
  Tight    = -2;
  Spaced   = - 1;
  NegFloat = - 1.5;
  NegHex   = - $1E5;
  NotTrue  = not True;
  Sum      = 1 + 1;

implementation

end.
'@
[System.IO.File]::WriteAllText((Join-Path $w 'uConsts.pas'),
  ($src -replace "`r`n","`n" -replace "`n","`r`n"), (New-Object System.Text.ASCIIEncoding))

$db = Join-Path $w 'c.sqlite'

# The inferred type is the LEADING token of the stored signature: 'Integer = 7'.
# An untyped const stores just '= <value>'.
function SigOf([string]$Name) {
  $j = (& $exePath query --name $Name --db $db --json 2>$null | Out-String)
  $m = [regex]::Match($j, '"signature"\s*:\s*"([^"]*)"')
  if ($m.Success) { return $m.Groups[1].Value } else { return '<none>' }
}

Push-Location C:\TEMP
try {
  & $exePath index $w --db $db 2>&1 | Out-Null
  Check '1. SANITY: the index exists' (Test-Path $db)

  $tight = SigOf 'Tight'
  Check '1b. SANITY: the no-space form was ALWAYS typed' ($tight -like 'Integer*') `
        "Tight => '$tight' -- if this is untyped the fixture is not exercising the right thing"

  $spaced = SigOf 'Spaced'
  Check '2. `= - 1` infers Integer' ($spaced -like 'Integer*') "Spaced => '$spaced'"

  $negf = SigOf 'NegFloat'
  Check '3. `= - 1.5` infers Extended' ($negf -like 'Extended*') "NegFloat => '$negf'"

  $negh = SigOf 'NegHex'
  Check '4. POSITIVE CONTROL: `= - $1E5` is Integer, not Extended' ($negh -like 'Integer*') `
        "NegHex => '$negh' -- Extended here means the WHOLE value text was classified, not the operand"

  $nott = SigOf 'NotTrue'
  Check '5. POSITIVE CONTROL: `not True` stays untyped' `
        (($nott -ne '<none>') -and ($nott.TrimStart() -like '=*')) `
        "NotTrue => '$nott' -- only + and - over a numeric literal may infer"

  $sum = SigOf 'Sum'
  Check '6. POSITIVE CONTROL: `1 + 1` stays untyped' `
        (($sum -ne '<none>') -and ($sum.TrimStart() -like '=*')) `
        "Sum => '$sum' -- a binary expression is not a signed literal"
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
