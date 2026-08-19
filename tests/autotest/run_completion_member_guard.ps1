<#
  run_completion_member_guard.ps1 -- member completion after '.' must offer the
  members of the LHS's DECLARED TYPE, including inherited ones, and must find
  that type in ANY open database.

  THE DEFECTS THIS PINS (found 2026-08-18 from a live plugin log in which every
  single textDocument/completion returned "items":[]):

  A. THE KIND CHECK TESTED THE WRONG SYMBOL. BuildCompletionItems did:

         TypeResult := TTypeAtResolver.Resolve(AStore, AFile, ALine, LhsEnd);
         if TypeResult.HasResolved and
            (TypeResult.Resolved.Kind in [skClass, skRecord, skInterface]) then

     `Resolved` is the symbol AT THE CURSOR. For `AExceptionInfo.` that is the
     PARAMETER, whose kind is skParam -- never skClass. So the branch never ran
     and the item list came back empty for every variable, field and parameter.
     Member completion only ever worked when a bare TYPE NAME was typed before
     the dot (`TFoo.`), which is close to never in real code. The declared type
     was sitting in TSymbol.Signature the whole time, and the resolver already
     had TypeIdentOfSignature + FindTypeAnywhere to follow it -- the resolver
     uses exactly that cascade for `Foo.Bar` member lookups. Completion simply
     did not reuse it.

  B. COMPLETION WAS SINGLE-STORE. It was handed FStore (documented in
     LSP.Server as "kept for legacy single-store callers") while the server had
     FStores, every --db it opened. The declaring type routinely lives in
     ANOTHER index: the case that exposed this had the variable in a project
     index and its class only in library-Win64.sqlite. So even with A fixed, a
     single-store lookup still finds nothing.

  Case 2 below is the one that pins B: the type is indexed into a SEPARATE
  database from the unit that uses it. Case 1 alone would pass on a
  single-store build.

  POSITIVE CONTROL: against a build without the fix, both cases return zero
  items and every membership assertion fails.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-completion-member-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 10
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$typesDir = Join-Path $WorkDir 'types'; New-Item -ItemType Directory $typesDir | Out-Null
$usageDir = Join-Path $WorkDir 'usage'; New-Item -ItemType Directory $usageDir | Out-Null

# ---------------------------------------------------------------- fixtures --
# TFixtureThing inherits BaseOnlyMethod, so the ancestor walk is exercised too:
# a fix that lists only direct children would pass three assertions and fail
# that one, which is the difference between "follows the type" and "follows the
# type properly".
WriteAnsi (Join-Path $typesDir 'FixtureTypes.pas') @'
unit FixtureTypes;

interface

type
  TFixtureBase = class
  public
    procedure BaseOnlyMethod;
  end;

  TFixtureThing = class(TFixtureBase)
  private
    FHiddenField: Integer;
  protected
    ProtField: Integer;
  public
    ThingField: Integer;
    procedure ThingMethod;
    function ThingFunc: Integer;
    procedure SetOnly(AValue: Integer);
    { All four accessor shapes, so the SILENCE on read/write is asserted as
      deliberately as the markers on read-only and write-only. }
    property PropRead: Integer read FHiddenField;
    property PropWrite: Integer write SetOnly;
    property PropBoth: Integer read FHiddenField write FHiddenField;
  end;

  { Bait for case 4. PUBLIC, matches the 'Th' prefix, and belongs to a class
    nothing else references -- so it is reachable ONLY by an unscoped global
    prefix search. If it ever shows up in a `Local.Th` list, member completion
    has silently degraded into that search again. }
  TUnrelatedDecoy = class
  public
    ThievingDecoy: Integer;
  end;

implementation

procedure TFixtureBase.BaseOnlyMethod;
begin
end;

procedure TFixtureThing.ThingMethod;
begin
end;

procedure TFixtureThing.SetOnly(AValue: Integer);
begin
  FHiddenField := AValue;
end;

function TFixtureThing.ThingFunc: Integer;
var
  Mine: TFixtureThing;
begin
  Mine.
    ThingMethod;
  Result := 0;
end;

end.
'@

# The dot is the LAST character on its line and the member sits on the next
# line. That is legal Pascal, so the unit still parses and `Local: TFixtureThing`
# is extracted -- while giving the completion left-walk a line that genuinely
# ends in '.', which is what an editor sends the instant the dot is typed.
WriteAnsi (Join-Path $usageDir 'FixtureUsage.pas') @'
unit FixtureUsage;

interface

procedure UseTheThing;

implementation

uses
  FixtureTypes;

type
  TOutsiderDescendant = class(TFixtureThing)
  public
    procedure Poke;
  end;

procedure UseTheThing;
var
  Local: TFixtureThing;
begin
  Local.
    ThingMethod;
end;

procedure TypeAfterDot;
var
  Local: TFixtureThing;
begin
  Local.Th
end;

procedure TrailingTextAfterCaret;
var
  Local: TFixtureThing;
  S: Integer;
begin
  S := Local.;
end;

procedure TOutsiderDescendant.Poke;
var
  Kin: TFixtureThing;
begin
  Kin.
    ThingMethod;
end;

end.
'@

$usageFile = Join-Path $usageDir 'FixtureUsage.pas'
# 0-based line of "  Local." and the character just past the dot.
$lines = [System.IO.File]::ReadAllLines($usageFile)
$dotLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].TrimEnd() -eq '  Local.') { $dotLine = $i; break } }
Check 'located the "Local." line in the fixture' ($dotLine -ge 0) "line0=$dotLine"
if ($dotLine -lt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$dotChar = $lines[$dotLine].TrimEnd().Length   # 0-based col just past '.'

function Get-CompletionLabels([string[]]$Dbs) {
  $args = @('lsp')
  foreach ($d in $Dbs) { $args += '--db'; $args += $d }
  $uri = 'file:///' + ($usageFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/completion';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $dotLine; character = $dotChar } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'shutdown'; params = @{} }

  $inF  = Join-Path $WorkDir 'lspin.txt'
  $outF = Join-Path $WorkDir 'lspout.txt'
  $errF = Join-Path $WorkDir 'lsperr.txt'
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList $args -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null

  $raw = [System.IO.File]::ReadAllText($outF)
  $labels = @()
  $script:LastDetails = @{}
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2 -and $o.result) {
      foreach ($it in $o.result.items) { $labels += $it.label; $script:LastDetails[$it.label] = $it.detail }
    }
  }
  return , $labels
}

$expected = @('ThingMethod', 'ThingFunc', 'ThingField', 'BaseOnlyMethod')

# ---- case 1: one database holding both units (pins defect A) ----
Write-Host ''
Write-Host 'CASE 1: type and usage in the SAME index (pins the kind check)' -ForegroundColor Cyan
$db1 = Join-Path $WorkDir 'both.sqlite'
& $Exe index $WorkDir --db $db1 2>&1 | Out-Null
Check 'built the combined index' (Test-Path $db1)
$got1 = Get-CompletionLabels @($db1)
Check 'completion returned items at all' ($got1.Count -gt 0) "count=$($got1.Count)"
foreach ($e in $expected) {
  Check "offers $e" ($got1 -contains $e) $(if ($got1 -contains $e) { '' } else { "got: $($got1 -join ',')" })
}

# ---- case 2: type in a DIFFERENT database (pins defect B) ----
Write-Host ''
Write-Host 'CASE 2: type in a SEPARATE index (pins the single-store lookup)' -ForegroundColor Cyan
$dbT = Join-Path $WorkDir 'types.sqlite'
$dbU = Join-Path $WorkDir 'usage.sqlite'
& $Exe index $typesDir --db $dbT 2>&1 | Out-Null
& $Exe index $usageDir --db $dbU 2>&1 | Out-Null
Check 'built both split indexes' ((Test-Path $dbT) -and (Test-Path $dbU))
# usage db FIRST: it owns the file, exactly how the plugin orders project-then-library.
$got2 = Get-CompletionLabels @($dbU, $dbT)
Check 'cross-store completion returned items' ($got2.Count -gt 0) "count=$($got2.Count)"
foreach ($e in $expected) {
  Check "offers $e across stores" ($got2 -contains $e) $(if ($got2 -contains $e) { '' } else { "got: $($got2 -join ',')" })
}

# ---- case 3: visibility ----
# A private backing field is not reachable from another unit, and offering it
# buries the members that ARE. The store keeps visibility in Modifiers, so this
# needs no extractor change. Asserted in BOTH directions: filtering everything
# would also make the "not offered" check pass.
Write-Host ''
Write-Host 'CASE 3: private members are hidden from OTHER units only' -ForegroundColor Cyan
Check 'private field not offered from another unit' (-not ($got1 -contains 'FHiddenField')) `
  $(if ($got1 -contains 'FHiddenField') { 'FHiddenField leaked across units' } else { '' })
Check 'public members still offered (filter is not swallowing everything)' `
  (($got1 -contains 'ThingField') -and ($got1 -contains 'ThingMethod'))
# The reported case: a PROTECTED member offered inside a plain procedure of an
# unrelated unit. Legal only in a descendant, and UseTheThing is not one.
Check 'protected NOT offered in a non-descendant context' (-not ($got1 -contains 'ProtField')) `
  $(if ($got1 -contains 'ProtField') { 'ProtField leaked into a standalone procedure' } else { '' })

# ...but a descendant in that same foreign unit MUST still see it, or the rule
# has just become "hide protected always", which is the opposite error.
$descDot = -1
$ul = [System.IO.File]::ReadAllLines($usageFile)
for ($i = 0; $i -lt $ul.Count; $i++) { if ($ul[$i].TrimEnd() -eq '  Kin.') { $descDot = $i; break } }
Check 'located the descendant "Kin." probe' ($descDot -ge 0) "line0=$descDot"
if ($descDot -ge 0) {
  $sf = $usageFile; $sl = $dotLine; $sc = $dotChar
  $dotLine = $descDot; $dotChar = $ul[$descDot].TrimEnd().Length
  $gotD = Get-CompletionLabels @($db1)
  $dotLine = $sl; $dotChar = $sc; $usageFile = $sf
  Check 'protected IS offered inside a descendant' ($gotD -contains 'ProtField') "got: $($gotD -join ',')"
  Check 'private still hidden even in a descendant' (-not ($gotD -contains 'FHiddenField'))
}

# Completing INSIDE the declaring unit must still see its own privates. The
# fixture already contains `Mine.` in TFixtureThing's own implementation, so
# this is the ordinary local-variable path with AFile == the declaring file.
$selfProbe = Join-Path $typesDir 'FixtureTypes.pas'
$chk = [System.IO.File]::ReadAllLines($selfProbe)
$selfDot = -1
for ($i = 0; $i -lt $chk.Count; $i++) { if ($chk[$i].TrimEnd() -eq '  Mine.') { $selfDot = $i; break } }
Check 'located the same-unit "Mine." probe' ($selfDot -ge 0) "line0=$selfDot"
if ($selfDot -ge 0) {
  $savedFile = $usageFile; $savedLine = $dotLine; $savedChar = $dotChar
  $usageFile = $selfProbe; $dotLine = $selfDot; $dotChar = $chk[$selfDot].TrimEnd().Length
  $got3 = Get-CompletionLabels @($dbT)
  $usageFile = $savedFile; $dotLine = $savedLine; $dotChar = $savedChar
  Check 'own privates ARE offered inside the declaring unit' ($got3 -contains 'FHiddenField') `
    "count=$($got3.Count) got: $($got3 -join ',')"
}

# ---- case 4: typing after the dot must STAY member completion ----
# The reported failure: `Local.` was correct, then one keystroke turned it into
# a global prefix search -- unscoped and unfiltered -- so a protected field of
# the right class and a private field of an UNRELATED class were both offered.
Write-Host ''
Write-Host 'CASE 4: a typed prefix after the dot stays scoped to the type' -ForegroundColor Cyan
$typeDot = -1
$ul4 = [System.IO.File]::ReadAllLines($usageFile)
for ($i = 0; $i -lt $ul4.Count; $i++) { if ($ul4[$i].TrimEnd() -eq '  Local.Th') { $typeDot = $i; break } }
Check 'located the "Local.Th" probe' ($typeDot -ge 0) "line0=$typeDot"
if ($typeDot -ge 0) {
  $sl = $dotLine; $sc = $dotChar
  $dotLine = $typeDot; $dotChar = $ul4[$typeDot].TrimEnd().Length
  $got4 = Get-CompletionLabels @($db1)
  $dotLine = $sl; $dotChar = $sc
  Check 'still returns members' ($got4.Count -gt 0) "count=$($got4.Count)"
  Check 'narrowed to the typed prefix' (($got4 | Where-Object { $_ -notlike 'Th*' }).Count -eq 0) `
    "off-prefix: $(($got4 | Where-Object { $_ -notlike 'Th*' }) -join ',')"
  Check 'offers ThingMethod / ThingFunc / ThingField' `
    (($got4 -contains 'ThingMethod') -and ($got4 -contains 'ThingFunc') -and ($got4 -contains 'ThingField'))
  # The exact shape of the reported defect: an unrelated type's member leaking
  # in via a global prefix search.
  Check 'does NOT leak the unrelated ThievingDecoy' (-not ($got4 -contains 'ThievingDecoy')) `
    $(if ($got4 -contains 'ThievingDecoy') { 'global prefix search is still in play' } else { '' })
  Check 'does NOT leak protected/private on a prefix match' `
    ((-not ($got4 -contains 'FHiddenField')) -and (-not ($got4 -contains 'ProtField')))
}

# ---- case 6: the caret is not at end of line ----
# Every other fixture puts the dot last on its line, so `text before the caret`
# and `the whole line` are the same string and an off-by-one in that slice is
# invisible. Real editing almost never looks like that: `S := Local.;` has a
# semicolon to the right of the caret, and including it made the dot test read
# a ';' and return an empty list -- in 22ms, so it looked like "no members"
# rather than like a bug.
Write-Host ''
Write-Host 'CASE 6: caret mid-line, with text to its right' -ForegroundColor Cyan
$midIdx = -1
$ul6 = [System.IO.File]::ReadAllLines($usageFile)
for ($i = 0; $i -lt $ul6.Count; $i++) { if ($ul6[$i].TrimEnd() -eq '  S := Local.;') { $midIdx = $i; break } }
Check 'located the "S := Local.;" probe' ($midIdx -ge 0) "line0=$midIdx"
if ($midIdx -ge 0) {
  # caret sits between the '.' and the ';'  -> 0-based offset of the ';'
  $caret = $ul6[$midIdx].IndexOf('.') + 1
  $sf = $usageFile; $sl = $dotLine; $sc = $dotChar
  $dotLine = $midIdx; $dotChar = $caret
  $got6 = Get-CompletionLabels @($db1)
  $usageFile = $sf; $dotLine = $sl; $dotChar = $sc
  Check 'returns members despite the trailing semicolon' ($got6.Count -gt 0) "count=$($got6.Count)"
  Check 'offers ThingMethod mid-line' ($got6 -contains 'ThingMethod') "got: $($got6 -join ',')"
  Check 'still visibility-filtered mid-line' `
    ((-not ($got6 -contains 'FHiddenField')) -and (-not ($got6 -contains 'ProtField')))
}

# ---- case 5: the detail line reports what constrains use, and nothing else ----
# Visibility and property accessors are the two things that decide whether a
# member can be used at the call site. Everything else is already visible in the
# signature, so a marker on a plain public read/write member would be noise.
Write-Host ''
Write-Host 'CASE 5: detail carries visibility + accessor qualifiers' -ForegroundColor Cyan
$sd = $usageFile; $sl = $dotLine; $sc = $dotChar
$usageFile = $selfProbe; $dotLine = $selfDot; $dotChar = $chk[$selfDot].TrimEnd().Length
$null = Get-CompletionLabels @($dbT)
$det = $script:LastDetails
$usageFile = $sd; $dotLine = $sl; $dotChar = $sc

Check 'private field marked [private]'    ($det['FHiddenField'] -like '`[private`]*')   "got: $($det['FHiddenField'])"
Check 'protected field marked [protected]' ($det['ProtField']   -like '`[protected`]*') "got: $($det['ProtField'])"
Check 'read-only property marked'  ($det['PropRead']  -match 'read-only')  "got: $($det['PropRead'])"
Check 'write-only property marked' ($det['PropWrite'] -match 'write-only') "got: $($det['PropWrite'])"
# The explicit request: read/write gets NO report.
Check 'read/write property carries NO accessor marker' `
  (($det['PropBoth'] -notmatch 'read-only') -and ($det['PropBoth'] -notmatch 'write-only')) `
  "got: $($det['PropBoth'])"
Check 'public field carries no qualifier at all' ($det['ThingField'] -notlike '`[*') "got: $($det['ThingField'])"

# ---- guard the guard: the fixture must not be trivially satisfiable ----
Write-Host ''
Write-Host 'NEGATIVE CONTROL' -ForegroundColor Cyan
Check 'does not offer a member that exists nowhere' (-not ($got1 -contains 'NoSuchMemberZZ'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
