#Requires -Version 7
<#
  run_lsp_type_hierarchy_guard.ps1 -- `textDocument/prepareTypeHierarchy`,
  `typeHierarchy/supertypes`, `typeHierarchy/subtypes` (lane 145 lsp).

  Fixture: IShape; TBase(TInterfacedObject, IShape); TMid(TBase); TLeaf(TMid).
  Positive controls (a handler answering null / [] or a constant fails them):
    initialize advertises typeHierarchyProvider.
    prepare on TMid -> one item named TMid.
    supertypes(TMid) -> exactly [TBase]; supertypes(TBase) -> [IShape] (TInterfacedObject is outside the
      index: left out, never guessed).
    subtypes(TBase) -> exactly [TMid] (DIRECT only: TLeaf is a grand-child); subtypes(TLeaf) -> [].
  Honest misses: prepare on a routine name and on whitespace -> null; a stale item -> [].
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-typehier-$PID"
)
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lsp_stdio_helpers.ps1')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uTypes.pas'
WriteAnsi $file @'
unit uTypes;

interface

uses
  System.Classes;

type
  IShape = interface
    procedure Draw;
  end;

  TBase = class(TInterfacedObject, IShape)
  public
    procedure Draw;
  end;

  TMid = class(TBase)
  end;

  TLeaf = class(TMid)
  end;

procedure Solo;

implementation

procedure TBase.Draw;
begin
end;

procedure Solo;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'types.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) { for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } } return -1 }
$uri = 'file:///' + ($file -replace '\\', '/')
$lMid = LineOf '^  TMid = class'; $lBase = LineOf '^  TBase = class'; $lLeaf = LineOf '^  TLeaf = class'
$lSolo = LineOf '^procedure Solo;$' ((LineOf '^implementation') + 1)
function Prep([int]$line, [int]$col) { @{ method='textDocument/prepareTypeHierarchy'; params=(PosParams $uri $line $col) } }

$r1 = LspSession $Exe $WorkDir $db @((Prep $lMid 4), (Prep $lBase 4), (Prep $lLeaf 4), (Prep $lSolo 10), (Prep 1 0))   # 11..15
Check 'initialize advertises typeHierarchyProvider' ($r1.init.capabilities.typeHierarchyProvider -eq $true)
Check 'prepare answered (not -32601)' ($r1.res.ContainsKey(11)) $(if ($r1.err.Count) { 'error=' + (($r1.err.Values | % { $_.code }) -join ',') })
if (-not $r1.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
$pm = @($r1.res[11][0])
Check 'prepare on TMid: one item named TMid' ($pm.Count -eq 1 -and $pm[0].name -eq 'TMid') "got=$($pm.Count)/$($pm[0].name)"
Check 'prepare on a routine name -> null' (IsNull $r1 14)
Check 'prepare on whitespace -> null' (IsNull $r1 15)
$iMid = $pm[0]; $iBase = @($r1.res[12][0])[0]; $iLeaf = @($r1.res[13][0])[0]
$stale = @{ name='TMid'; kind=5; uri=$uri; range=$iMid.range; selectionRange=$iMid.selectionRange; data=@{ id=999999; path=$file } }
$r2 = LspSession $Exe $WorkDir $db @(
  @{ method='typeHierarchy/supertypes'; params=@{ item=$iMid } },   # 11
  @{ method='typeHierarchy/supertypes'; params=@{ item=$iBase } },  # 12
  @{ method='typeHierarchy/subtypes';   params=@{ item=$iBase } },  # 13
  @{ method='typeHierarchy/subtypes';   params=@{ item=$iLeaf } },  # 14
  @{ method='typeHierarchy/supertypes'; params=@{ item=$stale } }   # 15
)
$s1 = @($r2.res[11][0])
Check 'supertypes(TMid) = [TBase]' ($s1.Count -eq 1 -and $s1[0].name -eq 'TBase') "got=$(($s1 | % { $_.name }) -join ',')"
$s2 = @($r2.res[12][0])
Check 'supertypes(TBase) = [IShape] (TInterfacedObject, outside the index, is left out)' ($s2.Count -eq 1 -and $s2[0].name -eq 'IShape') "got=$(($s2 | % { $_.name }) -join ',')"
$s3 = @($r2.res[13][0])
Check 'subtypes(TBase) = [TMid] (direct only, TLeaf is not a child)' ($s3.Count -eq 1 -and $s3[0].name -eq 'TMid') "got=$(($s3 | % { $_.name }) -join ',')"
Check 'subtypes(TLeaf) = []' ($r2.res.ContainsKey(14) -and @($r2.res[14][0]).Count -eq 0)
Check 'a stale item answers [] not an error' ($r2.res.ContainsKey(15) -and @($r2.res[15][0]).Count -eq 0 -and -not $r2.err.ContainsKey(15))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
