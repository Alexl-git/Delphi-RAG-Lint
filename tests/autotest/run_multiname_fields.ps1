<#
  run_multiname_fields.ps1 -- lane gaps/multiname
  (docs\INBOX-multi-name-field-list-first-name-only.md, part 2).

  WHAT WAS MISSING. A record/class field list that declares several names with
  one type -- `A1, A2, A3: string;` -- emitted a field symbol for the FIRST name
  only: the declField handler read ChildByField('name'), which returns the first
  of the delimited1 name list. Every shape was affected (record, class, generic
  type, a later visibility section, a variant `case` part). A LAST field with no
  trailing `;` (declFieldNoSemi, `N3, N4: string end`) emitted nothing at all.
  var / class var / params / locals were already per-name (controls below).

  CASES
    positive  one field row per name, names 2..n starting at their own
              identifier, every name carrying the shared type text.
    no-semi   the last field without `;` emits a row per name.
    controls  single-name fields unchanged (W1, FSingle start at the decl);
              var / class var / params keep one row per name.
    refs      a usage of a 2nd/3rd name now has a declaration to land on.

  RED (deployed 1.36 engine, 2026-10-28): A2, A3, G2, P2, V2, FB, FG2, PubB and
  N1..N4 absent except the first name of each list (N3/N4: none).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-multiname-fields-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$src = @'
unit MultiNameFix;

interface

type
  TRec = record
    A1, A2, A3: string;
    G1, G2: TArray<string>;
    procedure M;
  public
    P1, P2: Integer;
  var
    Q1, Q2: Integer;
    case Integer of
      0: (V1, V2: Integer);
      1: (W1: Double);
  end;

  TCls = class
  private
    FSingle: Integer;
    FA, FB: Integer;
    FG1, FG2: TArray<string>;
  public
    procedure Run(X1, X2: Integer; const S1, S2: string);
  public
    class var CV1, CV2: Integer;
  public
    PubA, PubB: string;
  end;

  TNoSemi = record
    N1, N2: Integer;
    N3, N4: string
  end;

var
  GVar1, GVar2: Integer;

implementation

procedure TRec.M;
begin
  A2 := A3;
end;

procedure TCls.Run(X1, X2: Integer; const S1, S2: string);
begin
  FB := X2 + FG2[0].Length;
end;

end.
'@

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'MultiNameFix.pas'
[IO.File]::WriteAllText($pas, ($src -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'mn.sqlite'

$ver = & $Exe --version 2>&1 | Select-Object -First 1
Write-Host "engine: $ver exe=$Exe"
& $Exe index $WorkDir --db $db *> (Join-Path $WorkDir 'index.log')
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$json = & $Exe sql --query "select kind, qualified_name, start_line, start_col, signature from symbols where kind in ('field','var') order by start_line, start_col" --db $db --json 2>$null | Out-String
$doc = $json | ConvertFrom-Json
$cols = @($doc.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
$rows = foreach ($r in $doc.rows) {
  $o = [ordered]@{}
  for ($k = 0; $k -lt $cols.Count; $k++) { $o[$cols[$k]] = $r[$k] }
  [pscustomobject]$o
}
Check 'symbol rows were read' (@($rows).Count -gt 0) ("rows=" + @($rows).Count)

# kind, short qname, line, col, signature
$expect = @(
  @('field','TRec.A1',7,5,'string'),        @('field','TRec.A2',7,9,'string'),        @('field','TRec.A3',7,13,'string'),
  @('field','TRec.G1',8,5,'TArray<string>'), @('field','TRec.G2',8,9,'TArray<string>'),
  @('field','TRec.P1',11,5,'Integer'),      @('field','TRec.P2',11,9,'Integer'),
  @('var','TRec.Q1',13,5,'Integer'),        @('var','TRec.Q2',13,9,'Integer'),
  @('field','TRec.V1',15,11,'Integer'),     @('field','TRec.V2',15,15,'Integer'),
  @('field','TRec.W1',16,11,'Double'),
  @('field','TCls.FSingle',21,5,'Integer'),
  @('field','TCls.FA',22,5,'Integer'),      @('field','TCls.FB',22,9,'Integer'),
  @('field','TCls.FG1',23,5,'TArray<string>'), @('field','TCls.FG2',23,10,'TArray<string>'),
  @('var','TCls.CV1',27,15,'Integer'),      @('var','TCls.CV2',27,20,'Integer'),
  @('field','TCls.PubA',29,5,'string'),     @('field','TCls.PubB',29,11,'string'),
  @('field','TNoSemi.N1',33,5,'Integer'),   @('field','TNoSemi.N2',33,9,'Integer'),
  @('field','TNoSemi.N3',34,5,'string'),    @('field','TNoSemi.N4',34,9,'string'),
  @('var','GVar1',38,3,'Integer'),          @('var','GVar2',38,10,'Integer')
)
foreach ($e in $expect) {
  $q = 'MultiNameFix.' + $e[1]
  $hit = @($rows | Where-Object { $_.qualified_name -eq $q })
  $got = if ($hit.Count -eq 1) { "{0} {1}:{2} '{3}'" -f $hit[0].kind, $hit[0].start_line, $hit[0].start_col, $hit[0].signature } else { "count=$($hit.Count)" }
  $ok = ($hit.Count -eq 1) -and ($hit[0].kind -eq $e[0]) -and ([int]$hit[0].start_line -eq $e[2]) -and
        ([int]$hit[0].start_col -eq $e[3]) -and ($hit[0].signature -eq $e[4])
  Check ("{0} = {1} {2}:{3} '{4}'" -f $e[1], $e[0], $e[2], $e[3], $e[4]) $ok "got: $got"
}
$fieldCount = @($rows | Where-Object { $_.kind -eq 'field' }).Count
Check 'exactly 21 field rows (no duplicates)' ($fieldCount -eq 21) "got: $fieldCount"

# Positive control on params (already per-name before the fix).
$pj = & $Exe sql --query "select count(*) from symbols where kind='param' and qualified_name like 'MultiNameFix.TCls.Run.%'" --db $db --json 2>$null | Out-String | ConvertFrom-Json
Check 'params X1,X2,S1,S2 = 4 rows' ([int]$pj.rows[0][0] -ge 4) ("got: " + $pj.rows[0][0])

# Refs: a usage of a later name lands on a declaration.
foreach ($n in 'A2', 'A3', 'FB', 'FG2') {
  $u = & $Exe usages --name $n --db $db --json 2>$null | Out-String | ConvertFrom-Json
  $uses = @($u.reads).Count + @($u.writes).Count
  Check "usages $n has 1 declaration and >=1 use" ((@($u.declarations).Count -eq 1) -and ($uses -ge 1)) ("decl=" + @($u.declarations).Count + " uses=$uses")
}

if ($script:Failed) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
}
finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
