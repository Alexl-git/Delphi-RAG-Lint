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
  @{ N='F reintroduce without overload hides'; K="  TKid = class(TBase)`r`n    procedure M(A: Integer); reintroduce;`r`n  end;"; Impl="procedure TKid.M(A: Integer); begin end;"; C="K.M('x')"; Must=$false; Why='reintroduce with no overload hides' },
  @{ N='G override that renames its parameter'; K="  TKid = class(TBase)`r`n    procedure M(B: Integer); override;`r`n  end;"; Impl="procedure TKid.M(B: Integer); begin end;"; C="K.M(1)"; Must=$true; Why='149 RB2 item 6 (PB 146 b4): parameter NAMES take no part in override matching' },
  @{ N='H control: override that changes the parameter TYPE'; K="  TKid = class(TBase)`r`n    procedure M(B: Double); override;`r`n  end;"; Impl="procedure TKid.M(B: Double); begin end;"; C="K.M(1)"; Must=$false; Why='the shape (modifier + type) is what matches, so a different type is refused' }
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
  # 149 RB2 item 6: G compiling proves the renamed override is LEGAL; this proves it is the
  # overridden TWIN -- a call through a TBase reference dispatches to TKid.M at run time,
  # which only an override (never a hiding sibling) does. ParamShapeKey (CallResolver) keys
  # the twin on modifier + type, names dropped, for exactly this reason.
  $rdpr = Join-Path $Work 'pR.dpr'
  $rsrc = "program pR;`r`n{`$APPTYPE CONSOLE}`r`ntype`r`n  TBase = class`r`n    procedure M(A: Integer); virtual;`r`n  end;`r`n" +
          "  TKid = class(TBase)`r`n    procedure M(B: Integer); override;`r`n  end;`r`n" +
          "procedure TBase.M(A: Integer); begin Write('BASE'); end;`r`nprocedure TKid.M(B: Integer); begin Write('KID'); end;`r`n" +
          "var B: TBase;`r`nbegin`r`n  B:= TKid.Create;`r`n  B.M(1);`r`n  B.Free;`r`nend.`r`n"
  [IO.File]::WriteAllText($rdpr, $rsrc, [Text.Encoding]::ASCII)
  $null = & $Dcc -Q -CC "-E$Work" "-NU$Work" -NSSystem $rdpr 2>&1 | Out-String
  $rexe = Join-Path $Work 'pR.exe'
  $rout = if (Test-Path $rexe) { (& $rexe | Out-String).Trim() } else { '<no exe>' }
  $rok = ($rout -ceq 'KID')
  Write-Host ("  [{0}] R renamed-param override is the overridden twin: TBase ref dispatches to TKid.M (got '{1}')" -f (@('FAIL','PASS')[[int]$rok]), $rout)
  if (-not $rok) { $script:Failed = $true }
} finally {
  [IO.Directory]::Delete($Work, $true)
}
if ($script:Failed) { Write-Host 'FAILED'; exit 1 }
Write-Host 'ALL PASS'; exit 0