<#
  run_convert_apply_book_warn.ps1 -- '#warn' and '#check-ref' (E17, 1.26.3).

  #warn <FromPath> "<text>": block-scoped (file scope = every block); fires
  once per converted instance whose SOURCE block streams <FromPath>, never when
  it is absent; carries nothing. Placeholders: <value>, <name>, {Prop} (another
  source property of the same instance, '' when absent). warnings[]
  'line N: warning: <inst>: <text>', items[] kind book-warning
  {instance, path, value, text, rule_line}.

  #check-ref <ToPath> <Class>.<Prop>[, ...] (owner rule F7, generic): the value
  the CONVERTED block holds at <ToPath>
    - containing '\' or ':' -> ref-path-like;
    - carried by no listed Class.Prop of ANY .dfm in the project index (every
      unit, not only the converted one) -> ref-dangling;
  and, when the project index holds no .dfm property facts at all, ONE
  ref-not-checked line per run.

  convert-validate: a #warn path or {Prop} naming no member, a #check-ref ToPath
  naming no member, and a malformed directive are line N errors.
  Every written .dfm goes through DfmLoadCheck.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_book_warn_$PID"
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
. (Join-Path $PSScriptRoot 'lib\DfmLoadCheck.ps1')

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$Nf = "$WorkDir-nf"
if (Test-Path $Nf) { Remove-Item -Recurse -Force $Nf }
New-Item -ItemType Directory $WorkDir, $Nf | Out-Null
function Q([string]$n) { return (Join-Path $Nf $n) }

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Json([string]$Out) { try { return ($Out.Substring($Out.IndexOf('{')) | ConvertFrom-Json) } catch { return $null } }

$LibS = @'
unit LibS;

interface

uses
  System.Classes;

type
  TSrcDb = class(TComponent)
  private
    FDatabaseName: string;
  published
    property DatabaseName: string read FDatabaseName write FDatabaseName;
  end;

  TSrcTable = class(TComponent)
  private
    FDatabaseName: string;
    FIndexName   : string;
    FTableName   : string;
    FNote        : string;
  published
    property DatabaseName: string read FDatabaseName write FDatabaseName;
    property IndexName: string read FIndexName write FIndexName;
    property TableName: string read FTableName write FTableName;
    property Note: string read FNote write FNote;
  end;

implementation

end.
'@
$LibT = @'
unit LibT;

interface

uses
  System.Classes;

type
  TDstConn = class(TComponent)
  private
    FConnectionName: string;
  published
    property ConnectionName: string read FConnectionName write FConnectionName;
  end;

  TDstTable = class(TComponent)
  private
    FConnectionName: string;
    FIndexName     : string;
    FTableName     : string;
  published
    property ConnectionName: string read FConnectionName write FConnectionName;
    property IndexName: string read FIndexName write FIndexName;
    property TableName: string read FTableName write FTableName;
  end;

implementation

end.
'@
Write-Ascii (P 'LibS.pas') $LibS
Write-Ascii (P 'LibT.pas') $LibT
Write-Ascii (Q 'LibS.pas') $LibS
Write-Ascii (Q 'LibT.pas') $LibT

Write-Ascii (P 'WarnDM.pas') @'
unit WarnDM;

interface

uses
  System.Classes, LibS;

type
  TWarnDM = class(TDataModule)
    db: TSrcDb;
    tGood: TSrcTable;
    tPath: TSrcTable;
    tDang: TSrcTable;
    tOther: TSrcTable;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'WarnDM.dfm') @'
object WarnDM: TWarnDM
  object db: TSrcDb
    DatabaseName = 'MainDB'
  end
  object tGood: TSrcTable
    DatabaseName = 'MainDB'
    IndexName = 'IX_A'
    TableName = 'Parts'
    Note = 'n1 <name> {TableName}'
  end
  object tPath: TSrcTable
    DatabaseName = 'c:\micrnite\system'
    TableName = 'T2'
  end
  object tDang: TSrcTable
    DatabaseName = 'Nowhere'
  end
  object tOther: TSrcTable
    DatabaseName = 'otherdb'
  end
end
'@
# A SECOND unit -- never converted -- holds the only TSrcDb named OtherDB:
# the dangle check reads every .dfm of the project, not just the converted one.
Write-Ascii (P 'OtherDM.pas') @'
unit OtherDM;

interface

uses
  System.Classes, LibS;

type
  TOtherDM = class(TDataModule)
    db2: TSrcDb;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'OtherDM.dfm') @'
object OtherDM: TOtherDM
  object db2: TSrcDb
    DatabaseName = 'OtherDB'
  end
end
'@

$Book = @'
#warn Note "file-scope note on <name>: <value>"

#convert LibS.TSrcTable -> LibT.TDstTable, LibT
#link ConnectionName <- DatabaseName
#link IndexName <- IndexName
#link TableName <- TableName
#ignore Note
#warn IndexName "index <value> must exist on table {TableName} in the target database (<name>)"
#warn TableName "table <value> idx [{IndexName}]"
#check-ref ConnectionName TSrcDb.DatabaseName, TDstConn.ConnectionName

#convert LibS.TSrcDb -> LibT.TDstConn, LibT
#link ConnectionName <- DatabaseName
'@
Write-Ascii (P 'warn.rules') $Book

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
Check 'V the load checker is available (lib\DfmLoadCheck.ps1)' (Test-DfmLoadsChecker)

# ---- convert-validate ------------------------------------------------------------
$v = (& $Exe convert-validate --rules (P 'warn.rules') --from LibS.TSrcTable --to LibT.TDstTable --db $db 2>&1) -join "`n"
Check 'P1 --print-parsed shows the two new directives' `
  (((& $Exe convert-validate --rules (P 'warn.rules') --print-parsed 2>&1) -join "`n") -match 'line 8: warn IndexName "index <value> must exist' ) ''
Check 'P2 the book validates against TSrcTable -> TDstTable' ($v -match '(?m)^OK\r?$') $v
Write-Ascii (P 'bad.rules') @'
#convert LibS.TSrcTable -> LibT.TDstTable, LibT
#warn NoSuchProp "x <value>"
#warn TableName "on {NoSuchProp}"
#warn TableName no quotes here
#warn TableName
#check-ref NoSuchTarget TSrcDb.DatabaseName
#check-ref ConnectionName NotDotted
#check-ref ConnectionName
'@
$v = (& $Exe convert-validate --rules (P 'bad.rules') --from LibS.TSrcTable --to LibT.TDstTable --db $db 2>&1) -join "`n"
Check 'P3 exit 1 on a bad book' ($LASTEXITCODE -eq 1) $v
Check 'P4 a #warn path naming no member is a line error' ($v -match 'line 2: warn FromPath not found in --from tree: NoSuchProp') $v
Check 'P5 a {Prop} naming no member is a line error' ($v -match 'line 3: warn placeholder \{NoSuchProp\} not found in --from tree') $v
Check 'P6 a malformed #warn is a line error (no quotes; no text)' (($v -match 'line 4: #warn needs <FromPath> "<text>"') -and ($v -match 'line 5: #warn needs <FromPath> "<text>"')) $v
Check 'P7 a #check-ref ToPath naming no member is a line error' ($v -match 'line 6: check-ref ToPath not found in --to tree: NoSuchTarget') $v
Check 'P8 a malformed #check-ref is a line error' (($v -match 'line 7: #check-ref target "NotDotted" is not <Class>\.<Prop>') -and ($v -match 'line 8: #check-ref needs <ToPath>')) $v

# ---- convert-apply -----------------------------------------------------------------
$o = (& $Exe convert-apply --unit (P 'WarnDM.pas') --rules (P 'warn.rules') --db $db --format json 2>&1) -join "`n"
$j = Json $o
Check 'A0 dry run: apply/1 JSON, ok' (($null -ne $j) -and $j.ok) $o
$bw = @($j.items | Where-Object kind -eq 'book-warning')
$w  = @($j.warnings)
Check 'W1 #warn with the property PRESENT fires, placeholders expanded: <value>, {TableName}, <name>' `
  (@($w | Where-Object { $_ -match '^line \d+: warning: tGood: index IX_A must exist on table Parts in the target database \(tGood\)$' }).Count -eq 1) ($w -join ' | ')
Check 'W2 #warn with the property ABSENT does not fire (tPath, tDang, tOther have no IndexName)' `
  (@($bw | Where-Object { $_.path -eq 'IndexName' }).Count -eq 1) (($bw | ForEach-Object text) -join ' | ')
Check 'W3 an absent {Prop} expands to empty: tPath "table T2 idx []"' `
  (@($w | Where-Object { $_ -match ': tPath: table T2 idx \[\]$' }).Count -eq 1) ($w -join ' | ')
Check 'W4 a FILE-SCOPE #warn applies in every block whose instance streams it (tGood Note), once; ONE-PASS expansion: a value holding <name> / {TableName} is not re-expanded' `
  ((@($w | Where-Object { $_ -match ': tGood: file-scope note on tGood: n1 <name> \{TableName\}$' }).Count -eq 1) -and (@($bw | Where-Object path -eq 'Note').Count -eq 1)) ($w -join ' | ')
$it = @($bw | Where-Object { $_.instance -eq 'tGood' -and $_.path -eq 'IndexName' }) | Select-Object -First 1
Check 'W5 items[] book-warning carries instance, path, value, text, rule_line' `
  (($null -ne $it) -and ($it.value -eq 'IX_A') -and ($it.rule_line -eq 8) -and ($it.text -match 'index IX_A') -and ($it.field -eq 'warnings')) ($it | ConvertTo-Json -Compress)

$pl = @($j.items | Where-Object kind -eq 'ref-path-like')
$dg = @($j.items | Where-Object kind -eq 'ref-dangling')
Check 'R1 a path-like value warns: tPath ConnectionName c:\micrnite\system' `
  ((@($pl).Count -eq 1) -and ($pl[0].instance -eq 'tPath') -and ($pl[0].value -eq 'c:\micrnite\system') -and `
   ($pl[0].text -eq "line 11: warning: tPath: ConnectionName 'c:\micrnite\system' looks like a file path, not a TSrcDb.DatabaseName / TDstConn.ConnectionName name (#check-ref line 10)"))(($pl | ConvertTo-Json -Compress))
Check 'R2 a dangling name warns: tDang Nowhere (and tPath, whose path names no database either)' `
  ((@($dg).Count -eq 2) -and (@($dg | Where-Object { $_.instance -eq 'tDang' -and $_.value -eq 'Nowhere' -and $_.text -match "^line \d+: warning: tDang: ConnectionName 'Nowhere' matches no TSrcDb\.DatabaseName / TDstConn\.ConnectionName in the project's \.dfm files -- the reference dangles \(#check-ref line 10\)$" }).Count -eq 1)) (($dg | ConvertTo-Json -Compress))
Check 'R3 positive control: a matching name in the SAME unit does not warn (tGood MainDB)' `
  (-not (@($pl + $dg) | Where-Object instance -eq 'tGood')) ''
Check 'R4 a matching name in ANOTHER unit does not warn, case-insensitively (tOther otherdb ~ OtherDM OtherDB)' `
  (-not (@($pl + $dg) | Where-Object instance -eq 'tOther')) ''
Check 'R5 no ref-not-checked when the index has .dfm facts' (@($j.items | Where-Object kind -eq 'ref-not-checked').Count -eq 0) ''

$r = (& $Exe convert-apply --unit (P 'WarnDM.pas') --rules (P 'warn.rules') --db $db --apply --no-backup 2>&1) -join "`n"
Check 'A1 --apply exits 0' ($LASTEXITCODE -eq 0) $r
$t = [IO.File]::ReadAllText((P 'WarnDM.dfm'))
Check 'A2 #warn carries nothing: no Note written, IndexName carried by its #link' `
  (-not ($t -match 'Note =') -and ($t -match "IndexName = 'IX_A'") -and ($t -match "ConnectionName = 'c:\\micrnite\\system'")) $t
$fails = Test-DfmLoads @((P 'WarnDM.dfm'))
Check 'L the converted .dfm LOADS' ($fails.Count -eq 0) ($fails -join ' | ')

# ---- not checked: an index with no .dfm property facts ----------------------------
# Two units whose .dfm objects stream NO property -> no dfm-prop facts (the
# shape a pre-0.58 index has everywhere); the ConnectionName
# comes from a #default. ONE ref-not-checked for the whole batch run.
foreach ($u in 'NfA', 'NfB') {
  Write-Ascii (Q "$u.pas") (@"
unit $u;

interface

uses
  System.Classes, LibS;

type
  T$u = class(TDataModule)
    t1: TSrcTable;
    t2: TSrcTable;
  end;

implementation

{`$R *.dfm}

end.
"@)
  Write-Ascii (Q "$u.dfm") (@"
object ${u}: T$u
  object t1: TSrcTable
  end
  object t2: TSrcTable
  end
end
"@)
}
Write-Ascii (Q 'nf.rules') @'
#convert LibS.TSrcTable -> LibT.TDstTable, LibT
#default ConnectionName = 'Somewhere'
#check-ref ConnectionName TSrcDb.DatabaseName
'@
$db2 = Q 'nf.sqlite'
$idx = & $Exe index $Nf --db $db2 2>&1
Check 'N0 the no-facts index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db2)) ($idx -join ' | ')
$o = (& $Exe convert-apply --unit (Q 'NfA.pas') --unit (Q 'NfB.pas') --rules (Q 'nf.rules') --db $db2 --format json 2>&1) -join "`n"
$jb = Json $o
$nc = @($jb.units | ForEach-Object { $_.items } | Where-Object kind -eq 'ref-not-checked')
Check 'N1 ONE ref-not-checked for a 2-unit, 4-instance run' `
  (($nc.Count -eq 1) -and ($nc[0].text -eq 'line 3: warning: #check-ref not checked -- the project index holds no .dfm property facts (reindex it with this engine)')) (($nc | ConvertTo-Json -Compress) + ' || ' + $o.Substring(0, [Math]::Min(400, $o.Length)))
Check 'N2 ... and no ref-dangling guessed instead' (@($jb.units | ForEach-Object { $_.items } | Where-Object kind -eq 'ref-dangling').Count -eq 0) ''

$ij = Json ((& $Exe info --json 2>&1) -join "`n")
Check 'I info --json: capabilities.book_warn and check_ref are JSON true' `
  (($null -ne $ij) -and ($ij.capabilities.book_warn -eq $true) -and ($ij.capabilities.check_ref -eq $true) -and ($ij.capabilities.book_warn -is [bool])) ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_book_warn_$PID", "C:\TEMP\draglint_convert_apply_book_warn_$PID-nf")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
