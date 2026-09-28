<#
  run_concat_in_loop_type_aware.ps1 -- with a STORE present, `concat-in-loop`
  must not report an accumulation whose target is PROVEN not to be a string.

  THE DEFECT (R11, plan 2026-09-24 D20-D31; measured 2026-09-27)
  --------------------------------------------------------------
  The rule is a tree-sitter query, so it cannot see a type. Two constraints
  make it type-safe WITHOUT a type (a numeric-literal operand, a `[`-opening
  array constructor -- see run_concat_in_loop_precision.ps1), but a VARIABLE
  operand is indistinguishable:

      Total := Total + Count;     -- Integer
      Sum   := Sum + D;           -- Double
      Inl   := Inl + D;           -- an INLINE var Inl: Double := 0
      Arr   := Arr + Other;       -- TArray<Integer>
      Result := Result + N;       -- a function returning Integer

  all fire, with advice ("use TStringList or string.Join") that is nonsense for
  them. On drag-lint's own source, lint-all reported 146, of which ~13 were
  such targets (Double x6, Integer x5, TArray x2).

  THE FIX, and what it deliberately does NOT do
  ---------------------------------------------
  When a store is present, each surface that merges the .scm findings -- `lint`,
  `lint-all` and the LSP -- drops a concat-in-loop finding whose target's
  declared type is PROVEN non-string (store category, or the intrinsic name
  heuristic for arrays/sets the store has no category for). A target whose type
  is UNKNOWN, or AMBIGUOUS (two routines declaring the name differently), is
  KEPT: the rule's recall on real string accumulation must not drop to buy
  precision. Without a store nothing changes (run_concat_in_loop_precision.ps1
  still pins the type-blind limitation there).

  Every "must NOT fire" case has a "MUST fire" twin in the same fixture, so a
  run that reports nothing -- or a rule that was switched off -- fails here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-concat-typeaware-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# ---------- fixture: one project, one unit ----------
$unit = @(
  'unit ConcatTyped;'
  ''
  'interface'
  ''
  'type'
  '  TMystery = TUnresolvedElsewhere;'
  ''
  'procedure Run(const AItems: TArray<string>; const AOther: TArray<Integer>; D: Double; Count: Integer);'
  'function SumInts(const AItems: TArray<Integer>): Integer;'
  'function JoinAll(const AItems: TArray<string>): string;'
  'procedure Ambig1;'
  'procedure Ambig2;'
  ''
  'implementation'
  ''
  'procedure Run(const AItems: TArray<string>; const AOther: TArray<Integer>; D: Double; Count: Integer);'
  'var'
  '  S: string;'
  '  Total: Integer;'
  '  Sum: Double;'
  '  Arr: TArray<Integer>;'
  '  M, Y: TMystery;'
  '  Item: string;'
  'begin'
  '  S := ''''; Total := 0; Sum := 0; Arr := nil;'
  '  for Item in AItems do'
  '  begin'
  '    S := S + Item;'
  '    Total := Total + Count;'
  '    Sum := Sum + D;'
  '    Arr := Arr + AOther;'
  '    M := M + Y;'
  '  end;'
  '  var Inl: Double := 0;'
  '  var InlS: string := '''';'
  '  for Item in AItems do'
  '  begin'
  '    Inl := Inl + D;'
  '    InlS := InlS + Item;'
  '  end;'
  '  Writeln(S, Total, Sum, Length(Arr), Inl, InlS);'
  'end;'
  ''
  'function SumInts(const AItems: TArray<Integer>): Integer;'
  'var'
  '  N: Integer;'
  'begin'
  '  Result := 0;'
  '  for N in AItems do'
  '    Result := Result + N;'
  'end;'
  ''
  'function JoinAll(const AItems: TArray<string>): string;'
  'var'
  '  Piece: string;'
  'begin'
  '  Result := '''';'
  '  for Piece in AItems do'
  '    Result := Result + Piece;'
  'end;'
  ''
  'procedure Ambig1;'
  'var'
  '  Acc: string;'
  '  K: Integer;'
  '  W: string;'
  'begin'
  '  Acc := ''''; W := ''x'';'
  '  for K := 1 to 3 do'
  '    Acc := Acc + W;'
  '  Writeln(Acc);'
  'end;'
  ''
  'procedure Ambig2;'
  'var'
  '  Acc: Integer;'
  '  K: Integer;'
  'begin'
  '  Acc := 0;'
  '  for K := 1 to 3 do'
  '    Writeln(Acc);'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'ConcatTyped.pas'
[IO.File]::WriteAllText($pas, $unit + "`r`n", [Text.Encoding]::ASCII)
$dpr = @('program App;', '', 'uses', "  ConcatTyped in 'ConcatTyped.pas';", '', 'begin', 'end.') -join "`r`n"
$dprPath = Join-Path $WorkDir 'App.dpr'
[IO.File]::WriteAllText($dprPath, $dpr + "`r`n", [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'App.sqlite'

$lines = [IO.File]::ReadAllLines($pas)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$ln = [ordered]@{
  StringVar   = LineOf 'S := S + Item;'
  IntegerVar  = LineOf 'Total := Total + Count;'
  DoubleVar   = LineOf 'Sum := Sum + D;'
  ArrayVar    = LineOf 'Arr := Arr + AOther;'
  UnknownVar  = LineOf 'M := M + Y;'
  IntResult   = LineOf 'Result := Result + N;'
  StrResult   = LineOf 'Result := Result + Piece;'
  Ambiguous   = LineOf 'Acc := Acc + W;'
  InlineDbl   = LineOf 'Inl := Inl + D;'
  InlineStr   = LineOf 'InlS := InlS + Item;'
}
Check 'all ten fixture statements located' (@($ln.Values) -notcontains -1) (($ln.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

& $Exe index --project $dprPath --db $db 2>&1 | Out-Null
Check 'fixture indexed' ((Test-Path $db) -and $LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function FiredText([string[]]$Out) {
  $r = @()
  foreach ($line in $Out) { if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:') { $r += [int]$Matches[1] } }
  return ,@($r | Sort-Object -Unique)
}

# ---------- LSP driver (publishDiagnostics lines for concat-in-loop) ----------
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function FiredLsp([string]$PasFile, [string]$Db) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [IO.File]::ReadAllText($PasFile)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $in = Join-Path $WorkDir 'lsp-in.txt'; $so = Join-Path $WorkDir 'lsp-out.txt'; $se = Join-Path $WorkDir 'lsp-err.txt'
  [IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object Text.UTF8Encoding($false)))
  $null = Start-Process $Exe -ArgumentList @('lsp', '--db', "`"$Db`"") -WorkingDirectory $WorkDir `
            -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait -PassThru
  $out = if (Test-Path $so) { [IO.File]::ReadAllText($so) } else { '' }
  $r = @()
  foreach ($body in ($out -split 'Content-Length: \d+\r\n\r\n')) {
    if ($body.Trim() -eq '') { continue }
    try { $m = $body | ConvertFrom-Json } catch { continue }
    if ($m.method -ne 'textDocument/publishDiagnostics') { continue }
    foreach ($d in @($m.params.diagnostics)) { if ($d.code -eq 'concat-in-loop') { $r += ([int]$d.range.start.line + 1) } }
  }
  return ,@($r | Sort-Object -Unique)
}

$surfaces = [ordered]@{
  'lint --db'     = FiredText @(& $Exe lint $pas --db $db 2>$null)
  'lint-all --db' = FiredText @(& $Exe lint-all --db $db --rule concat-in-loop 2>$null)
  'lsp --db'      = FiredLsp $pas $db
}

foreach ($s in $surfaces.GetEnumerator()) {
  $fired = $s.Value
  Write-Host ''
  Write-Host ("{0}: fired on lines [{1}]" -f $s.Key, ($fired -join ', ')) -ForegroundColor Cyan
  Check "$($s.Key): string target S := S + Item MUST fire (positive control)"                 ($fired -contains $ln.StringVar)
  Check "$($s.Key): string Result := Result + Piece MUST fire (positive control, Result path)" ($fired -contains $ln.StrResult)
  Check "$($s.Key): UNKNOWN type M := M + Y MUST fire (recall kept)"                           ($fired -contains $ln.UnknownVar)
  Check "$($s.Key): AMBIGUOUS name Acc (string here, Integer elsewhere) MUST fire"             ($fired -contains $ln.Ambiguous)
  Check "$($s.Key): Integer Total := Total + Count must NOT fire"                              (-not ($fired -contains $ln.IntegerVar))
  Check "$($s.Key): Double Sum := Sum + D must NOT fire"                                       (-not ($fired -contains $ln.DoubleVar))
  Check "$($s.Key): TArray<Integer> Arr := Arr + AOther must NOT fire"                         (-not ($fired -contains $ln.ArrayVar))
  Check "$($s.Key): Integer function Result := Result + N must NOT fire"                       (-not ($fired -contains $ln.IntResult))
  Check "$($s.Key): INLINE string var InlS := InlS + Item MUST fire (positive control)"         ($fired -contains $ln.InlineStr)
  Check "$($s.Key): INLINE Double var Inl := Inl + D must NOT fire"                            (-not ($fired -contains $ln.InlineDbl))
}

Write-Host ''
Write-Host 'Without a store nothing changes (the .scm rule stays type-blind there)' -ForegroundColor Cyan
$noStore = FiredText @(& $Exe lint $pas 2>$null)
Check 'lint (no --db): Integer Total := Total + Count still fires' ($noStore -contains $ln.IntegerVar) ("fired=[" + ($noStore -join ', ') + "]")

Write-Host ''
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
