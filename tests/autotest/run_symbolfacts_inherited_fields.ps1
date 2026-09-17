<#
  run_symbolfacts_inherited_fields.ps1 -- symbol_facts.reads_fields /
  writes_fields include fields declared on an ANCESTOR class (Option A,
  decided 2026-09-15), resolved by the facts-inherited post-pass that runs
  AFTER the ancestry stage.

  WHY THE POST-PASS, and why this guard runs under --rebuild
  --------------------------------------------------------------------------------
  Facts are computed per file DURING the parse pass; ResolveAncestry is a
  post-pass. On a --rebuild every ancestor edge is unresolved when Analyze
  runs, so widening the lookup inside AnalyzeReadsWrites reports nothing on
  the very run that matters and passes only on later incremental runs. The
  post-pass is the fix, and --rebuild is the ordering that proves it.

  Measured case: uAREAOFINTEREST.TmcAREAOFINTEREST.SetAREA writes fModified
  (declared on the generic TMicObjectBase<I: IMicObject>) and reported only
  fAREA; 2,094 unclassified fmodified writes on ORM3 CLIENT.

  Spec: docs\superpowers\specs\2026-09-17-extractor-batch-generics-nested-locals-inherited-fields-design.md (F1-F8)
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_inhfields'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ifXBase: a plain base and a GENERIC base, in their own unit. The file name
# sorts AFTER ifChild ('ifChild' < 'ifXBase') so a parse-order-dependent
# implementation cannot pass by luck (the child is parsed first, before the
# base exists in the DB).
Write-Ascii (Join-Path $scratch 'ifXBase.pas') @'
unit ifXBase;

interface

type
  TPlainBase = class
  protected
    FBaseField: Integer;
    FName: string;
  end;

  TGenBase<T> = class
  protected
    FModified: Boolean;
    FItem: T;
  end;

  TGrand = class
  protected
    FG: Integer;
  end;

  TMid = class(TGrand)
  protected
    FM: Integer;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $scratch 'ifChild.pas') @'
unit ifChild;

interface

uses ifXBase;

type
  TChild = class(TPlainBase)
  private
    FName: string;
    FOwn: Integer;
  public
    procedure WriteInherited;
    procedure WriteShadowed;
    procedure WriteUnknown;
    procedure WriteOwnOnly;
    procedure ReadInherited;
  end;

  TGenChild = class(TGenBase<Integer>)
  public
    procedure Touch;
  end;

  TLeaf = class(TMid)
  public
    procedure WriteBoth;
  end;

implementation

procedure TLeaf.WriteBoth;
begin
  FG := 1;
  FM := 2;
end;

procedure TChild.WriteInherited;
begin
  FOwn := 1;
  FBaseField := 2;
end;

procedure TChild.WriteShadowed;
begin
  FName := 'x';
end;

procedure TChild.WriteUnknown;
begin
  NotAFieldAnywhere := 3;
end;

procedure TChild.WriteOwnOnly;
begin
  FOwn := 4;
end;

procedure TChild.ReadInherited;
var
  X: Integer;
begin
  X := FBaseField + FOwn;
end;

procedure TGenChild.Touch;
begin
  FItem := 1;
  FModified := True;
end;

end.
'@

$db = Join-Path $scratch 'if.sqlite'

Push-Location C:\TEMP
try {
  # F8: --rebuild is the ordering under test.
  $out = & $exePath index $scratch --db $db --rebuild 2>&1
  Check 'index --rebuild exits 0' ($LASTEXITCODE -eq 0)
  Check 'F2 the facts-inherited stage ran after ancestry' ((($out -join "`n") -match 'stage: ancestry') -and (($out -join "`n") -match 'stage: facts-inherited')) "stages seen: $(@($out | Select-String 'stage:.*started') -join ' | ')"

  # `sql --json` returns columns[] + POSITIONAL rows[][]; map each row onto its
  # column names so the assertions can say $row.writes_fields / $row.n.
  # A failed query (stderr dropped, empty stdout) is an EMPTY array, not @($null).
  function Sql([string]$q) {
    $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n"
    if ([string]::IsNullOrWhiteSpace($j)) { return ,@() }
    try { $o = $j | ConvertFrom-Json } catch { return ,@() }
    $cols = @($o.columns | ForEach-Object { $_.name })
    $out = @()
    foreach ($r in @($o.rows)) {
      $h = [ordered]@{}
      for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }
      $out += [pscustomobject]$h
    }
    return ,$out
  }

  # One facts row per routine, or $null when the routine has none (or several).
  function Facts([string]$qname) {
    $r = Sql "SELECT f.reads_fields, f.writes_fields FROM symbol_facts f JOIN symbols s ON s.id=f.symbol_id WHERE s.qualified_name='$qname'"
    if ($r.Count -eq 1) { return $r[0] }
    return $null
  }

  $wi = Facts 'ifChild.TChild.WriteInherited'
  Check 'F1/F3 WriteInherited writes_fields = "FOwn, FBaseField" (own first, then inherited)' (($null -ne $wi) -and ($wi.writes_fields -eq 'FOwn, FBaseField')) "writes=$($wi.writes_fields)"

  $ws = Facts 'ifChild.TChild.WriteShadowed'
  Check 'F4 shadowed FName reported ONCE (the own one)' (($null -ne $ws) -and ($ws.writes_fields -eq 'FName')) "writes=$($ws.writes_fields)"

  $wu = Facts 'ifChild.TChild.WriteUnknown'
  Check 'F5 no fabrication: unknown identifier reports nothing' (($null -ne $wu) -and [string]::IsNullOrEmpty($wu.writes_fields)) "writes=$($wu.writes_fields)"

  $wo = Facts 'ifChild.TChild.WriteOwnOnly'
  Check 'F1 own-class case untouched: WriteOwnOnly writes_fields = FOwn' (($null -ne $wo) -and ($wo.writes_fields -eq 'FOwn')) "writes=$($wo.writes_fields)"

  $ri = Facts 'ifChild.TChild.ReadInherited'
  Check 'F1 reads_fields includes inherited FBaseField' (($null -ne $ri) -and ($ri.reads_fields -match '\bFBaseField\b') -and ($ri.reads_fields -match '\bFOwn\b')) "reads=$($ri.reads_fields)"
  Check 'F1 reads_fields does not list the local X' (($null -ne $ri) -and ($ri.reads_fields -notmatch '\bX\b'))

  $gt = Facts 'ifChild.TGenChild.Touch'
  Check 'F2 GENERIC base: Touch writes_fields = "FItem, FModified"' (($null -ne $gt) -and ($gt.writes_fields -eq 'FItem, FModified')) "writes=$($gt.writes_fields)"

  # F3 THREE-level chain: the body writes FG (grand) BEFORE FM (mid), but the
  # post-pass appends by ancestor distance -- nearest first -- so TMid's FM
  # precedes TGrand's FG regardless of body order.
  $wb = Facts 'ifChild.TLeaf.WriteBoth'
  Check 'F3 three-level chain: WriteBoth writes_fields = "FM, FG" (nearest ancestor first, not body order)' (($null -ne $wb) -and ($wb.writes_fields -eq 'FM, FG')) "writes=$($wb.writes_fields)"

  # F7: a no-op incremental run STILL runs the facts-inherited stage (it is a
  # post-pass over the whole DB, not per changed file) and changes nothing.
  # (Sql returns `,$out`; assign before piping so the rows ENUMERATE -- piped
  # directly, the whole array arrives as one item and the count reads 1.)
  $allFactsSql = "SELECT s.qualified_name AS q, f.reads_fields AS r, f.writes_fields AS w FROM symbol_facts f JOIN symbols s ON s.id=f.symbol_id ORDER BY s.qualified_name"
  $rowsBefore = Sql $allFactsSql
  $factsBefore = @($rowsBefore | ForEach-Object { "$($_.q)|$($_.r)|$($_.w)" })
  $out2 = & $exePath index $scratch --db $db 2>&1
  Check 'F7 no-op incremental run exits 0' ($LASTEXITCODE -eq 0)
  Check 'F7 no-op incremental run still reports stage: facts-inherited' (($out2 -join "`n") -match 'stage: facts-inherited') "stages seen: $(@($out2 | Select-String 'stage:') -join ' | ')"
  $rowsAfter = Sql $allFactsSql
  $factsAfter = @($rowsAfter | ForEach-Object { "$($_.q)|$($_.r)|$($_.w)" })
  Check 'F7 no-op incremental run keeps EVERY facts row byte-identical (idempotent, 7 rows)' (($factsBefore.Count -eq 7) -and (($factsBefore -join "`n") -eq ($factsAfter -join "`n"))) "before=$($factsBefore.Count) after=$($factsAfter.Count)"
  Check 'F7 no-op incremental run keeps the facts (idempotent)' (((Facts 'ifChild.TChild.WriteInherited').writes_fields) -eq 'FOwn, FBaseField')

  # POSITIVE CONTROL
  $n = Sql "SELECT COUNT(*) AS n FROM symbol_facts"
  Check 'control: symbol_facts has 7 rows (one per routine)' (($n.Count -eq 1) -and ($n[0].n -eq 7)) "n=$($n[0].n)"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
