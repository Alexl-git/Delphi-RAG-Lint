<#
  run_usages_rw.ps1 -- `usages --rw`: the users of a property or member, split into
  readers and writers, including a property backed by a plain private field.

  OWNER Q1 (2026-11-04, BACKLOG FIND-USERS-READ-WRITE): "separate setters and readers
  even if the property setters and getters are not methods, but plain mentions of
  private storage". MEASURED before the flag: `usages FPlain` saw only the mentions
  inside the class; `usages Plain` saw only the property sites; `usages GetOther` and
  `usages SetOther` answered 0 for an accessor every property access goes through.
  No one question gave the whole set.

  CHECKS
    1  fixture health: the index holds the property access rows (FATAL, exit 2)
    2  POSITIVE CONTROL: plain `usages` keeps its document (no `targets` key) and the
       plain FPlain answer really lacks the property site R1, which is what --rw adds
    3  property on a plain field: readers = property site + direct field mention
    4  ... writers likewise; via labels name the route
    5  qualified name excludes the same-named TBar.Plain
    6  querying the FIELD gives the same sets and names its property
    7  getter: readers only; property site + direct call. Setter: writers only.
    8  method-backed property: accessor kinds, both routes
    9  a property nobody accesses still leads to its field (declaration read from source)
   10  multi-line declaration, field read + method write
   11  non-accessor routine: calls only
   12  bare ambiguous name: one target per declaration
   13  text form counts equal the JSON array lengths
   14  no such symbol: exit 1

  Lines are located by `{ Xn }` anchors, never hard-coded.
  Usage: pwsh -File tests\autotest\run_usages_rw.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
. (Join-Path $PSScriptRoot 'exe-hint.ps1')
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_usages_rw-{0}" -f $PID)
[IO.Directory]::CreateDirectory($scratch) | Out-Null

$props = @'
unit uProps;
interface
type
  TFoo = class
  private
    FPlain: Integer;
    FOther: Integer;
    FRo: Integer;
    FMixed: Integer;
    FUnused: Integer;
    function GetOther: Integer;
    procedure SetOther(pValue: Integer);
    procedure SetMixed(pValue: Integer);
  public
    procedure Touch;
    property Plain: Integer read FPlain write FPlain;
    property Other: Integer read GetOther write SetOther;
    property Ro: Integer read FRo;
    property Mixed: Integer
      read FMixed
      write SetMixed;
    property Unused: Integer read FUnused write FUnused;
  end;
  TBar = class
  public
    Plain: string;
  end;
implementation
function TFoo.GetOther: Integer;
begin
  Result:= FOther;
end;
procedure TFoo.SetOther(pValue: Integer);
begin
  FOther:= pValue;
end;
procedure TFoo.SetMixed(pValue: Integer);
begin
  FMixed:= pValue;
end;
procedure TFoo.Touch;
begin
  FPlain:= 1; { D1 }
  FRo:= FPlain; { D2 }
  FUnused:= 2; { U1 }
  FRo:= FUnused; { U2 }
  FRo:= GetOther; { G1 }
end;
end.
'@
$user = @'
unit uUser;
interface
uses uProps;
procedure ReadIt(const pFoo: TFoo);
procedure WriteIt(const pFoo: TFoo);
procedure BarIt(const pBar: TBar);
implementation
procedure ReadIt(const pFoo: TFoo);
var
  N: Integer;
begin
  N:= pFoo.Plain; { R1 }
  N:= N + pFoo.Other; { R2 }
  N:= N + pFoo.Ro;
  N:= N + pFoo.Mixed; { R3 }
  if N > 0 then pFoo.Touch; { C1 }
end;
procedure WriteIt(const pFoo: TFoo);
begin
  pFoo.Plain:= 1; { W1 }
  pFoo.Other:= 2; { W2 }
  pFoo.Mixed:= 3; { W3 }
end;
procedure BarIt(const pBar: TBar);
begin
  pBar.Plain:= 'x'; { B1 }
end;
end.
'@
$argsUnit = @'
unit uArgs;
interface
type
  TArgs = class
  private
    FCnt: Integer;
    FVar: Integer;
    FOut: Integer;
    FVal: Integer;
    FMix: Integer;
    FUnr: Integer;
    FLong: Integer;
  public
    procedure Run;
  end;
procedure TakeVar(var A: Integer; const B: Integer; out C: Integer);
procedure TakeTwo(A, B: Integer; var D, E: Integer);
implementation
procedure TakeVar(var A: Integer; const B: Integer; out C: Integer);
begin
end;
procedure TakeTwo(A, B: Integer; var D, E: Integer);
begin
end;
procedure TArgs.Run;
begin
  Inc(FCnt); { A1 }
  Dec(FCnt, 2); { A2 }
  TakeVar(FVar, FVal, FOut); { A3 }
  TakeTwo(FVal, FVal,
    FMix, FMix); { A4 }
  Nobody(FUnr); { A5 }
  FVal:= FCnt + 1; { A6 }
  TakeVar(FLong + 1, FVal, FVal); { A7 }
end;
end.
'@
$dpr = "program App;`r`nuses uProps in 'uProps.pas', uUser in 'uUser.pas', uArgs in 'uArgs.pas';`r`nbegin`r`nend.`r`n"
[IO.File]::WriteAllText("$scratch\uProps.pas", ($props -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText("$scratch\uUser.pas",  ($user  -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText("$scratch\uArgs.pas",  ($argsUnit -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
[IO.File]::WriteAllText("$scratch\App.dpr", $dpr, [Text.Encoding]::ASCII)
function LineOf([string]$file, [string]$tag) {
  $i = 0
  foreach ($l in [IO.File]::ReadAllLines("$scratch\$file")) { $i++; if ($l -like "*{ $tag }*") { return $i } }
  throw "anchor $tag not in $file"
}
$D1 = LineOf 'uProps.pas' 'D1'; $D2 = LineOf 'uProps.pas' 'D2'; $U1 = LineOf 'uProps.pas' 'U1'; $U2 = LineOf 'uProps.pas' 'U2'; $G1 = LineOf 'uProps.pas' 'G1'
$R1 = LineOf 'uUser.pas' 'R1'; $R2 = LineOf 'uUser.pas' 'R2'; $R3 = LineOf 'uUser.pas' 'R3'; $C1 = LineOf 'uUser.pas' 'C1'
$W1 = LineOf 'uUser.pas' 'W1'; $W2 = LineOf 'uUser.pas' 'W2'; $W3 = LineOf 'uUser.pas' 'W3'; $B1 = LineOf 'uUser.pas' 'B1'

$db = "$scratch\fx.sqlite"
$ixOut = & $exePath index --project "$scratch\App.dpr" --db $db 2>&1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $db)) {
  Write-Host "FATAL: fixture did not index: $($ixOut | Select-Object -Last 3)" -ForegroundColor Red
  Get-ExeStartFailureHint $LASTEXITCODE | Write-Host
  exit 2
}

# ---- 1: fixture health
$health = (& $exePath sql --db $db --query "select count(*) n from member_accesses" --json 2>$null) -join "`n" | ConvertFrom-Json
if ([int]$health.rows[0][0] -lt 6) { Write-Host "FATAL: fixture has too few member_accesses rows" -ForegroundColor Red; exit 2 }
Check '1 fixture has the property access rows' $true

function Rw([string]$name) {
  $raw = (& $exePath usages --name $name --rw --json --db $db 2>$null) -join "`n"
  $script:rwExit = $LASTEXITCODE
  try { return ($raw | ConvertFrom-Json) } catch { return $null }
}
# A row key: <file leaf>:<line>/<via>. The via is part of the contract.
function Keys($rows) { @($rows | ForEach-Object { '{0}:{1}/{2}' -f (Split-Path $_.path -Leaf), $_.line, $_.via }) | Sort-Object }
function Same($actual, [string[]]$expected) { (($actual -join ' ') -eq ((@($expected) | Sort-Object) -join ' ')) }
function T($doc, [string]$qname) { @($doc.targets | Where-Object { $_.qname -eq $qname })[0] }

# ---- 2: positive control
$plain = (& $exePath usages --name FPlain --json --db $db 2>$null) -join "`n" | ConvertFrom-Json
Check '2a plain usages keeps its document' (($null -eq $plain.targets) -and ($null -ne $plain.reads)) 'plain document changed'
$plainLines = @($plain.reads | ForEach-Object { '{0}:{1}' -f (Split-Path $_.file -Leaf), $_.line })
Check '2b plain FPlain lacks the property site R1 (what --rw adds)' ($plainLines -notcontains "uUser.pas:$R1") "plain reads: $plainLines"

# ---- 3-5: property on a plain field
$doc = Rw 'TFoo.Plain'
$t = if ($doc) { T $doc 'uProps.TFoo.Plain' } else { $null }
Check '3a one target, kind property' (($null -ne $t) -and ($t.kind -eq 'property') -and (@($doc.targets).Count -eq 1)) "doc: $($doc | ConvertTo-Json -Depth 3 -Compress)"
Check '3b accessors named as fields' (($t.read_accessor -eq 'FPlain') -and ($t.read_accessor_kind -eq 'field') -and ($t.write_accessor -eq 'FPlain') -and ($t.write_accessor_kind -eq 'field')) "got $($t.read_accessor)/$($t.read_accessor_kind) $($t.write_accessor)/$($t.write_accessor_kind)"
$k = Keys $t.readers
Check '3c readers = property site + private field mention' (Same $k @("uUser.pas:$R1/property", "uProps.pas:$D2/field")) "got: $k"
$k = Keys $t.writers
Check '4 writers = property site + private field mention' (Same $k @("uUser.pas:$W1/property", "uProps.pas:$D1/field")) "got: $k"
Check '5 TBar.Plain site not attributed to TFoo.Plain' ((Keys $t.writers) -notcontains "uUser.pas:$B1/property") "got: $(Keys $t.writers)"

# ---- 6: the field
$doc = Rw 'TFoo.FPlain'
$t = if ($doc) { T $doc 'uProps.TFoo.FPlain' } else { $null }
Check '6a field names its property' (@($t.backs_properties) -contains 'uProps.TFoo.Plain') "got: $($t.backs_properties)"
$k = Keys $t.readers
Check '6b field readers include the property site' (Same $k @("uUser.pas:$R1/property", "uProps.pas:$D2/field")) "got: $k"
$k = Keys $t.writers
Check '6c field writers include the property site' (Same $k @("uUser.pas:$W1/property", "uProps.pas:$D1/field")) "got: $k"

# ---- 7: accessors
$doc = Rw 'TFoo.GetOther'
$t = if ($doc) { T $doc 'uProps.TFoo.GetOther' } else { $null }
$k = Keys $t.readers
Check '7a getter: property site + direct call are readers' (Same $k @("uUser.pas:$R2/property", "uProps.pas:$G1/getter")) "got: $k"
Check '7b getter has no writers' (@($t.writers).Count -eq 0) "got: $(Keys $t.writers)"
$doc = Rw 'TFoo.SetOther'
$t = if ($doc) { T $doc 'uProps.TFoo.SetOther' } else { $null }
$k = Keys $t.writers
Check '7c setter: property site is a writer' (Same $k @("uUser.pas:$W2/property")) "got: $k"
Check '7d setter has no readers' (@($t.readers).Count -eq 0) "got: $(Keys $t.readers)"

# ---- 8: method-backed property
$doc = Rw 'TFoo.Other'
$t = if ($doc) { T $doc 'uProps.TFoo.Other' } else { $null }
Check '8a accessor kinds are method' (($t.read_accessor -eq 'GetOther') -and ($t.read_accessor_kind -eq 'method') -and ($t.write_accessor -eq 'SetOther') -and ($t.write_accessor_kind -eq 'method')) "got $($t.read_accessor)/$($t.read_accessor_kind) $($t.write_accessor)/$($t.write_accessor_kind)"
$k = Keys $t.readers
Check '8b readers: property site + direct getter call' (Same $k @("uUser.pas:$R2/property", "uProps.pas:$G1/getter")) "got: $k"
$k = Keys $t.writers
Check '8c writers: property site' (Same $k @("uUser.pas:$W2/property")) "got: $k"

# ---- 9: property nobody accesses
$doc = Rw 'TFoo.Unused'
$t = if ($doc) { T $doc 'uProps.TFoo.Unused' } else { $null }
Check '9a accessor read from the declaration' (($t.read_accessor -eq 'FUnused') -and ($t.write_accessor -eq 'FUnused')) "got $($t.read_accessor) $($t.write_accessor)"
$k = Keys $t.readers
Check '9b field mention is a reader' (Same $k @("uProps.pas:$U2/field")) "got: $k"
$k = Keys $t.writers
Check '9c field mention is a writer' (Same $k @("uProps.pas:$U1/field")) "got: $k"

# ---- 10: multi-line declaration
$doc = Rw 'TFoo.Mixed'
$t = if ($doc) { T $doc 'uProps.TFoo.Mixed' } else { $null }
Check '10a multi-line accessors' (($t.read_accessor -eq 'FMixed') -and ($t.read_accessor_kind -eq 'field') -and ($t.write_accessor -eq 'SetMixed') -and ($t.write_accessor_kind -eq 'method')) "got $($t.read_accessor)/$($t.read_accessor_kind) $($t.write_accessor)/$($t.write_accessor_kind)"
$k = Keys $t.readers
Check '10b readers' (@($k) -contains "uUser.pas:$R3/property") "got: $k"
$k = Keys $t.writers
Check '10c writers' (@($k) -contains "uUser.pas:$W3/property") "got: $k"

# ---- 11: non-accessor routine
$doc = Rw 'TFoo.Touch'
$t = if ($doc) { T $doc 'uProps.TFoo.Touch' } else { $null }
Check '11a a plain routine has calls' ((Keys $t.calls) -contains "uUser.pas:$C1/direct") "got: $(Keys $t.calls)"
Check '11b ...and no readers or writers' ((@($t.readers).Count -eq 0) -and (@($t.writers).Count -eq 0)) "r=$(Keys $t.readers) w=$(Keys $t.writers)"

# ---- 12: bare ambiguous name
$doc = Rw 'Plain'
$q = @($doc.targets | ForEach-Object { $_.qname }) | Sort-Object
Check '12a bare name: one target per declaration' (($q -join ' ') -eq 'uProps.TBar.Plain uProps.TFoo.Plain') "got: $q"
$t = if ($doc) { T $doc 'uProps.TBar.Plain' } else { $null }
Check '12b TBar.Plain owns its own write' ((Keys $t.writers) -contains "uUser.pas:$B1/direct") "got: $(Keys $t.writers)"

# ---- 13: text agrees with JSON
$doc = Rw 'TFoo.Plain'
$t = if ($doc) { T $doc 'uProps.TFoo.Plain' } else { $null }
$txt = (& $exePath usages --name TFoo.Plain --rw --db $db 2>$null) -join "`n"
Check '13a text counts = JSON' (($txt -match ('readers \({0}\)' -f @($t.readers).Count)) -and ($txt -match ('writers \({0}\)' -f @($t.writers).Count))) "text: $txt"
Check '13b text names the site and the route' ($txt -match ('uUser\.pas:{0}.*property' -f $R1)) "text: $txt"

# ---- 14: miss
$doc = Rw 'NoSuchThing'
Check '14 no such symbol: exit 1' ($script:rwExit -eq 1) "exit=$($script:rwExit)"

# ---- 15-22: Inc/Dec and var/out arguments (reclassified at query time, no extractor change)
$A1 = LineOf 'uArgs.pas' 'A1'; $A2 = LineOf 'uArgs.pas' 'A2'; $A3 = LineOf 'uArgs.pas' 'A3'; $A4 = LineOf 'uArgs.pas' 'A4'
$A5 = LineOf 'uArgs.pas' 'A5'; $A6 = LineOf 'uArgs.pas' 'A6'; $A7 = LineOf 'uArgs.pas' 'A7'
function RowLines($rows) { @($rows | ForEach-Object { [int]$_.line }) | Sort-Object }
function SameL($actual, [int[]]$expected) { ((@($actual) -join ' ') -eq ((@($expected) | Sort-Object) -join ' ')) }
$t = T (Rw 'TArgs.FCnt') 'uArgs.TArgs.FCnt'
Check '15a POSITIVE CONTROL: Inc/Dec arguments are writers' (SameL (RowLines $t.writers) @($A1, $A2)) "writers: $(RowLines $t.writers)"
Check '15b ...and their arg label is inc-dec' ((@($t.writers | Where-Object { $_.arg -eq 'inc-dec' }).Count) -eq 2) 'no inc-dec label'
Check '15c the read in a longer expression stays a reader (A6); Inc sites are not readers' (SameL (RowLines $t.readers) @($A6)) "readers: $(RowLines $t.readers)"
$t = T (Rw 'TArgs.FVar') 'uArgs.TArgs.FVar'
Check '16 var argument of a resolved call: reader AND writer' ((SameL (RowLines $t.readers) @($A3)) -and (SameL (RowLines $t.writers) @($A3)) -and ($t.writers[0].arg -eq 'var-arg')) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$t = T (Rw 'TArgs.FOut') 'uArgs.TArgs.FOut'
Check '17 out argument: writer only' ((SameL (RowLines $t.writers) @($A3)) -and (@($t.readers).Count -eq 0) -and ($t.writers[0].arg -eq 'out-arg')) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$t = T (Rw 'TArgs.FVal') 'uArgs.TArgs.FVal'
Check '18 const / by-value arguments stay readers; writers are the := (A6) and the out argument (A7, third position)' ((SameL (RowLines $t.readers) @($A3, ($A4 - 1), $A7)) -and (SameL (RowLines $t.writers) @($A6, $A7))) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$t = T (Rw 'TArgs.FMix') 'uArgs.TArgs.FMix'
Check '19 second-line argument of a var parameter: reader and writer' ((SameL (RowLines $t.readers) @($A4)) -and (SameL (RowLines $t.writers) @($A4))) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$t = T (Rw 'TArgs.FUnr') 'uArgs.TArgs.FUnr'
Check '20 argument of an UNRESOLVED call stays a reader (not guessed)' ((SameL (RowLines $t.readers) @($A5)) -and (@($t.writers).Count -eq 0)) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$t = T (Rw 'TArgs.FLong') 'uArgs.TArgs.FLong'
Check '21 var argument inside a longer expression (FLong + 1) stays a reader' ((SameL (RowLines $t.readers) @($A7)) -and (@($t.writers).Count -eq 0)) "r=$(RowLines $t.readers) w=$(RowLines $t.writers)"
$txt = (& $exePath usages --name TArgs.FVar --rw --db $db 2>$null) -join "`n"
Check '22 text names the argument kind and the note states the coverage' (($txt -match '\[arg var-arg\]') -and ($txt -match 'RESOLVED call')) "text: $txt"

[IO.Directory]::Delete($scratch, $true)
if ($script:fail) { Write-Host 'run_usages_rw: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_usages_rw: PASS' -ForegroundColor Green
exit 0
