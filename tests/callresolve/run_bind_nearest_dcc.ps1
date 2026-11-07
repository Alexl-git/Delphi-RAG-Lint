<#
  run_bind_nearest_dcc.ps1 -- what dcc itself says about the rule TCallResolver.NarrowToNearest
  encodes (E-BIND-NEAREST-WINS, wave 146 lane b4): "a level with no `overload` directive hides
  every deeper level; a level with `overload` lets the lookup go on."
  The rule was written from memory of Delphi; this asks the compiler.
  Each case is a whole program: it must compile, or must be refused with the named error.
  POSITIVE CONTROL: case P (a call with the wrong type and no hiding at all) must be refused,
  so a harness that always answered "compiled" fails here.
#>
[CmdletBinding()]
param([string]$Dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe')
$ErrorActionPreference = 'Continue'
$script:Failed = $false
if (-not (Test-Path $Dcc)) { Write-Host "FATAL: no compiler at $Dcc"; exit 2 }
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-nearest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Work)

$Base = "  TBase = class`r`n    procedure M(A: Integer); overload; virtual;`r`n    procedure M(const S: string); overload;`r`n  end;`r`n"
$Cases = @(
  @{ N='P control: no such overload anywhere'; K="  TKid = class(TBase) end;"; Impl=''; C="K.M(1.5)"; Must=$false; Why='wrong argument type is refused, the harness can say no' },
  @{ N='A no hiding: both base overloads reachable'; K="  TKid = class(TBase) end;"; Impl=''; C="K.M('x')"; Must=$true; Why='no level in between' },
  @{ N='B kid without overload hides the base'; K="  TKid = class(TBase)`r`n    procedure M(X: Double);`r`n  end;"; Impl="procedure TKid.M(X: Double); begin end;"; C="K.M('x')"; Must=$false; Why='a level with no overload hides every deeper level' },
  @{ N='C kid with overload lets the lookup go on'; K="  TKid = class(TBase)`r`n    procedure M(X: Double); overload;`r`n  end;"; Impl="procedure TKid.M(X: Double); begin end;"; C="K.M('x')"; Must=$true; Why='a level with overload does not hide' },
  @{ N='D override without overload'; K="  TKid = class(TBase)`r`n    procedure M(A: Integer); override;`r`n  end;"; Impl="procedure TKid.M(A: Integer); begin end;"; C="K.M('x')"; Must=$true; Why='an override with no overload directive does NOT hide the sibling overload' },
  @{ N='E override with overload'; K="  TKid = class(TBase)`r`n    procedure M(A: Integer); overload; override;`r`n  end;"; Impl="procedure TKid.M(A: Integer); begin end;"; C="K.M('x')"; Must=$true; Why='overload on the override keeps the sibling visible' },
  @{ N='F reintroduce without overload hides'; K="  TKid = class(TBase)`r`n    procedure M(A: Integer); reintroduce;`r`n  end;"; Impl="procedure TKid.M(A: Integer); begin end;"; C="K.M('x')"; Must=$false; Why='reintroduce with no overload hides' }
)
try {
  foreach ($c in $Cases) {
    $id = 'p' + ($c.N.Substring(0,1))
    $dpr = Join-Path $Work "$id.dpr"
    $src = "program $id;`r`ntype`r`n$Base$($c.K)`r`n" +
           "procedure TBase.M(A: Integer); begin end;`r`nprocedure TBase.M(const S: string); begin end;`r`n$($c.Impl)`r`n" +
           "var K: TKid;`r`nbegin`r`n  K:= TKid.Create;`r`n  $($c.C);`r`n  K.Free;`r`nend.`r`n"
    [IO.File]::WriteAllText($dpr, $src, [Text.Encoding]::ASCII)
    $out = & $Dcc -Q -CC "-E$Work" "-NU$Work" -NSSystem $dpr 2>&1 | Out-String
    $compiled = ($LASTEXITCODE -eq 0)
    $ok = ($compiled -eq $c.Must)
    $tag = if ($ok) { 'PASS' } else { 'FAIL' }
    $err = ([regex]::Match($out, '(?m)^.*(Error|Fatal)[^\r\n]*$')).Value
    Write-Host ("  [{0}] {1}: compiled={2}, expected={3} ({4}) {5}" -f $tag, $c.N, $compiled, $c.Must, $c.Why, $err)
    if (-not $ok) { $script:Failed = $true }
  }
} finally {
  [IO.Directory]::Delete($Work, $true)
}
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'ALL PASS'; exit 0