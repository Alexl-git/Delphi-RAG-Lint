<#
  run_generic_symbol_names.ps1 -- a generic type or method is indexed under its
  BARE name; the parameter list lives in symbols.generic_params; an ancestor
  written with type arguments resolves by ARITY before any scope rule.

  WHY (stats\draglint-gaps.log 2026-09-17, both class `wrong`)
  --------------------------------------------------------------------------------
  ORM3 CLIENT: `TMicObjectBase<I: IMicObject>` was the symbol NAME, so the
  ancestor edge `TMicObjectBase` on 134 descendants never resolved and their
  inherited fields (FModified among them) were unreachable.
  library-Win64: `TObjectList<T: class> = class(TList<T>)` resolved to
  System.Classes.TList -- the NON-generic pointer list -- because the same-unit
  `TList<T>` was invisible to a bare-name resolver. Confidently wrong.

  Spec: docs\superpowers\specs\2026-09-17-extractor-batch-generics-nested-locals-inherited-fields-design.md
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_genericnames'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# unit A: the NON-generic homonyms (the System.Classes / System.Contnrs shape).
Write-Ascii (Join-Path $scratch 'gnA.pas') @'
unit gnA;

interface

type
  TList = class
    FCount: Integer;
  end;
  TObjectList = class(TList)
  end;

implementation

end.
'@

# unit B: the generics, and a generic descendant of a SAME-UNIT generic
# (the System.Generics.Collections shape). B uses A, so both TList are in scope.
Write-Ascii (Join-Path $scratch 'gnB.pas') @'
unit gnB;

interface

uses gnA;

type
  TList<T> = class
    FItems: TArray<T>;
    procedure Add(const A: T);
  end;
  TObjectList<T: class> = class(TList<T>)
  end;
  TRepo<T: class, constructor> = class
    FCount: Integer;
  end;
  TImport<S: IUnknown; I: IUnknown> = class
    FImp: Integer;
  end;
  TPair<K, V> = record
    Key: K;
    Value: V;
  end;
  IRepo<I> = interface
    procedure Put(const A: I);
  end;
  TMapFn<T> = function(const A: T): T;
  TPlain = class
    FName: string;
  end;
  TBinder = class
    function BindAs<T: TObject>(const AName: string): T;
    procedure SendList<T>(const Msg: string; List: TList<T>); overload;
    procedure SendList<T>(MsgType: Integer; const Msg: string; List: TList<T>); overload;
  end;

implementation

procedure TList<T>.Add(const A: T);
begin
end;

function TBinder.BindAs<T>(const AName: string): T;
begin
  Result := nil;
end;

procedure TBinder.SendList<T>(const Msg: string; List: TList<T>);
begin
end;

procedure TBinder.SendList<T>(MsgType: Integer; const Msg: string; List: TList<T>);
begin
end;

end.
'@

# unit C: a PROJECT unit that uses BOTH A and B (the Contnrs+Generics shape).
# TWithArgs names the generic by arity; TNoArgs is genuinely ambiguous.
Write-Ascii (Join-Path $scratch 'gnC.pas') @'
unit gnC;

interface

uses gnA, gnB;

type
  TWithArgs = class(TObjectList<TPlain>)
  end;
  TNoArgs = class(TObjectList)
  end;
  TFromPair = class
    FP: TPair<string, Integer>;
  end;
  TRepoOfPlain = class(TRepo<TPlain>)
  end;
  TImportOfTwo = class(TImport<IUnknown, IUnknown>)
  end;
  TWrongArity = class(TImport<IUnknown>)
  end;

implementation

end.
'@

$db = Join-Path $scratch 'gn.sqlite'

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  function Get-Rows([string]$name) {
    $j = (& $exePath query --name $name --db $db --json --exact 2>$null) -join "`n"
    try { return ,@($j | ConvertFrom-Json) } catch { return ,@() }
  }
  # `sql --json` returns columns[] + POSITIONAL rows[][]; map each row onto its
  # column names so the assertions can say $row.n / $row.t / $row.ancestor_name.
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

  # --- G1: bare name + generic_params, every generic kind --------------------
  $tl = Get-Rows 'TList'
  Check 'G1 query --name TList --exact returns BOTH TList rows (bare name)' ($tl.Count -eq 2) "rows=$($tl.Count)"
  $gen = @($tl | Where-Object { $_.qualified_name -match '(?i)^gnB\.TList$' })
  Check 'G1 gnB.TList qualified_name is bare' ($gen.Count -eq 1) "qnames=$(($tl | % qualified_name) -join ', ')"
  if ($gen.Count -eq 1) {
    Check 'G1 gnB.TList generic_params = T' ($gen[0].generic_params -eq 'T') "generic_params=$($gen[0].generic_params)"
  }
  $pair = Get-Rows 'TPair'
  Check 'G1 record TPair bare, generic_params = "K, V"' (($pair.Count -eq 1) -and ($pair[0].generic_params -eq 'K, V')) "gp=$($pair[0].generic_params)"
  $repo = Get-Rows 'IRepo'
  Check 'G1 interface IRepo bare, generic_params = I' (($repo.Count -eq 1) -and ($repo[0].generic_params -eq 'I')) "gp=$($repo[0].generic_params)"
  $fn = Get-Rows 'TMapFn'
  Check 'G1 proc type TMapFn bare, generic_params = T' (($fn.Count -eq 1) -and ($fn[0].generic_params -eq 'T')) "gp=$($fn[0].generic_params)"
  $ol = @(Get-Rows 'TObjectList' | Where-Object { $_.qualified_name -match '(?i)^gnB\.' })
  Check 'G1 constraint kept as written: TObjectList generic_params = "T: class"' (($ol.Count -eq 1) -and ($ol[0].generic_params -eq 'T: class')) "gp=$($ol[0].generic_params)"
  $ba = Get-Rows 'BindAs'
  Check 'G1 generic METHOD BindAs bare, generic_params = "T: TObject"' (($ba.Count -ge 1) -and ($ba[0].generic_params -eq 'T: TObject')) "rows=$($ba.Count) gp=$($ba[0].generic_params)"
  Check 'G1 no symbol name still carries <' ((Sql "SELECT COUNT(*) AS n FROM symbols WHERE name LIKE '%<%' OR qualified_name LIKE '%<%'")[0].n -eq 0)

  # --- G2: non-generic rows untouched -----------------------------------------
  $pl = Get-Rows 'TPlain'
  Check 'G2 TPlain generic_params is null/empty' (($pl.Count -eq 1) -and [string]::IsNullOrEmpty($pl[0].generic_params))
  $sl = Get-Rows 'SendList'
  Check 'G2 SendList overload pair still TWO rows with distinct signatures' (($sl.Count -eq 2) -and ($sl[0].signature -ne $sl[1].signature)) "rows=$($sl.Count)"

  # --- G3: edge carries the type args ----------------------------------------
  $edge = Sql "SELECT ta.ancestor_name, ta.ancestor_type_args FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.qualified_name='gnB.TObjectList' AND ta.ordinal=0"
  Check 'G3 gnB.TObjectList edge: ancestor_name=TList, ancestor_type_args=T' (($edge.Count -eq 1) -and ($edge[0].ancestor_name -eq 'TList') -and ($edge[0].ancestor_type_args -eq 'T')) "edge=$($edge | ConvertTo-Json -Compress)"
  $edgeNA = Sql "SELECT ta.ancestor_type_args FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.qualified_name='gnA.TObjectList'"
  Check 'G3 gnA.TObjectList edge has NULL type args' (($edgeNA.Count -eq 1) -and [string]::IsNullOrEmpty($edgeNA[0].ancestor_type_args))

  # --- G6: same-unit generic wins over the used non-generic homonym ----------
  $r6 = Sql "SELECT a.qualified_name AS t FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id LEFT JOIN symbols a ON a.id=ta.ancestor_symbol_id WHERE s.qualified_name='gnB.TObjectList'"
  Check 'G6 gnB.TObjectList -> gnB.TList (not gnA.TList)' (($r6.Count -eq 1) -and ($r6[0].t -eq 'gnB.TList')) "resolved_to=$($r6[0].t)"

  # --- G4: arity filter across units -----------------------------------------
  $r4 = Sql "SELECT a.qualified_name AS t FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id LEFT JOIN symbols a ON a.id=ta.ancestor_symbol_id WHERE s.qualified_name='gnC.TWithArgs'"
  Check 'G4 gnC.TWithArgs (TObjectList<TPlain>) -> gnB.TObjectList by arity' (($r4.Count -eq 1) -and ($r4[0].t -eq 'gnB.TObjectList')) "resolved_to=$($r4[0].t)"

  # --- G5/G9: no args + two candidates still DECLINES (absence over wrong) ----
  $r5 = Sql "SELECT ta.ancestor_symbol_id AS id FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.qualified_name='gnC.TNoArgs'"
  Check 'G5/G9 gnC.TNoArgs (TObjectList, no args, two uses-named candidates) stays unresolved' (($r5.Count -eq 1) -and ($null -eq $r5[0].id)) "id=$($r5[0].id)"

  # --- G7: query input carrying <...> matches ---------------------------------
  $q7 = (& $exePath query --name 'TList<T>' --db $db --json --exact 2>$null) -join "`n"
  $rows7 = @(); try { $rows7 = @($q7 | ConvertFrom-Json) } catch { }
  Check 'G7 query --name "TList<T>" finds gnB.TList (arity-preferred)' (($rows7.Count -ge 1) -and (@($rows7 | ? { $_.qualified_name -eq 'gnB.TList' }).Count -eq 1)) "rows=$($rows7.Count)"

  # --- G8: display assembles name<params>; json carries the field -------------
  $txt = (& $exePath query --name TPair --db $db --exact 2>$null) -join "`n"
  Check 'G8 text table shows TPair<K, V>' ($txt -match 'TPair<K, V>')
  $anc = (& $exePath query ancestors --name TWithArgs --db $db 2>$null) -join "`n"
  Check 'G8 ancestors climbs TWithArgs -> TObjectList<T: class> -> TList<T>' (($anc -match 'TObjectList<T: class>') -and ($anc -match 'TList<T>')) "out=$anc"

  # --- G4 arity counts PARAMETERS, not constraint commas (final review #1) ----
  # 'T: class, constructor' is ONE parameter; 'S: IUnknown; I: IUnknown' is TWO.
  # Before the fix the first counted 2 and TRepo<TPlain> (1 arg) could never
  # resolve; the second counted 1 and TImport<IUnknown, IUnknown> (2 args) never.
  $repo = Get-Rows 'TRepo'
  Check 'A1 gnB.TRepo generic_params = "T: class, constructor" (as written)' (($repo.Count -eq 1) -and ($repo[0].generic_params -eq 'T: class, constructor')) "gp=$($repo[0].generic_params)"
  $imp = Get-Rows 'TImport'
  Check 'A1 gnB.TImport generic_params = "S: IUnknown; I: IUnknown" (as written)' (($imp.Count -eq 1) -and ($imp[0].generic_params -eq 'S: IUnknown; I: IUnknown')) "gp=$($imp[0].generic_params)"
  $rA = Sql "SELECT ta.ancestor_symbol_id AS id, a.qualified_name AS t FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id LEFT JOIN symbols a ON a.id=ta.ancestor_symbol_id WHERE s.qualified_name='gnC.TRepoOfPlain'"
  Check 'A2 gnC.TRepoOfPlain (TRepo<TPlain>, 1 arg) -> gnB.TRepo (arity 1, constraint comma ignored)' (($rA.Count -eq 1) -and ($null -ne $rA[0].id) -and ($rA[0].t -eq 'gnB.TRepo')) "resolved_to=$($rA[0].t)"
  $rB = Sql "SELECT ta.ancestor_symbol_id AS id, a.qualified_name AS t FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id LEFT JOIN symbols a ON a.id=ta.ancestor_symbol_id WHERE s.qualified_name='gnC.TImportOfTwo'"
  Check 'A3 gnC.TImportOfTwo (TImport<IUnknown, IUnknown>, 2 args) -> gnB.TImport (arity 2, ; separates groups)' (($rB.Count -eq 1) -and ($null -ne $rB[0].id) -and ($rB[0].t -eq 'gnB.TImport')) "resolved_to=$($rB[0].t)"
  # POSITIVE CONTROL for the arity decline: 1 arg against arity 2 stays unresolved.
  $rC = Sql "SELECT ta.ancestor_symbol_id AS id FROM type_ancestors ta JOIN symbols s ON s.id=ta.symbol_id WHERE s.qualified_name='gnC.TWrongArity'"
  Check 'A4 control: gnC.TWrongArity (TImport<IUnknown>, 1 arg vs arity 2) stays UNRESOLVED' (($rC.Count -eq 1) -and ($null -eq $rC[0].id)) "id=$($rC[0].id)"

  # --- G7 per-segment strip: 'Unit.TClass<T>.Method' finds the METHOD (#3) ----
  $q3 = (& $exePath query --name 'gnB.TBinder.BindAs<T>' --db $db --json --exact 2>$null) -join "`n"
  $rows3 = @(); try { $rows3 = @($q3 | ConvertFrom-Json) } catch { }
  Check 'Q1 query --name "gnB.TBinder.BindAs<T>" returns the METHOD row (gnB.TBinder.BindAs), not the class' (($rows3.Count -eq 1) -and ($rows3[0].qualified_name -eq 'gnB.TBinder.BindAs') -and ($rows3[0].kind -notmatch '(?i)class')) "rows=$($rows3.Count) qn=$($rows3[0].qualified_name) kind=$($rows3[0].kind)"
  # The discriminating input: the <...> sits on a MIDDLE segment. The old
  # first-'<'/last-'>' split dropped '.Add' and returned the CLASS.
  $q3m = (& $exePath query --name 'gnB.TList<T>.Add' --db $db --json --exact 2>$null) -join "`n"
  $rows3m = @(); try { $rows3m = @($q3m | ConvertFrom-Json) } catch { }
  Check 'Q1 query --name "gnB.TList<T>.Add" returns the METHOD gnB.TList.Add (per-segment strip), not the class' (($rows3m.Count -eq 1) -and ($rows3m[0].qualified_name -eq 'gnB.TList.Add') -and ($rows3m[0].kind -notmatch '(?i)class')) "rows=$($rows3m.Count) qn=$($rows3m[0].qualified_name) kind=$($rows3m[0].kind)"
  $q3c = (& $exePath query --name 'gnB.TList<T>' --db $db --json --exact 2>$null) -join "`n"
  $rows3c = @(); try { $rows3c = @($q3c | ConvertFrom-Json) } catch { }
  Check 'Q2 query --name "gnB.TList<T>" still returns the class gnB.TList' (($rows3c.Count -eq 1) -and ($rows3c[0].qualified_name -eq 'gnB.TList') -and ($rows3c[0].kind -match '(?i)class')) "rows=$($rows3c.Count) qn=$($rows3c[0].qualified_name) kind=$($rows3c[0].kind)"

  # --- impl range of a GENERIC class's method body is stamped (#5c) -----------
  $impl = Sql "SELECT impl_start_line FROM symbols WHERE qualified_name='gnB.TList.Add'"
  Check 'I1 gnB.TList.Add (procedure TList<T>.Add impl) has a non-null impl_start_line' (($impl.Count -eq 1) -and ($null -ne $impl[0].impl_start_line) -and ([int]$impl[0].impl_start_line -gt 0)) "impl_start_line=$($impl[0].impl_start_line)"

  # --- POSITIVE CONTROL: the guard can fail -----------------------------------
  $ctl = Sql "SELECT COUNT(*) AS n FROM symbols WHERE name='TPair'"
  Check 'control: TPair exists exactly once (delete it from the fixture and G1 goes red)' ($ctl[0].n -eq 1)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
