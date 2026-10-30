<#
  run_mcp_answers.ps1 -- what the MCP server answers, and that it stays up
  (Gitea drag-lint #31, #33, #34; 2026-10-15).

  Checks:
    M1  (#31) find_callers answers from the call graph: 'TA.Run' lists only the
        caller of TA.Run, and 'Run' does not list a routine whose LOCAL named Run
        is written and read; `query find-callers --resolved` (the same shared
        function) keeps the local's WRITE (the author's D31) but no longer calls
        its READ a [callback]
    M3  (#33) a tool that raises is answered with isError true, and the NEXT
        call is still answered (the server did not die)
    M4  (#34) a "db" argument at an OLD schema is refused with the reason, and
        that database is NOT migrated (it is opened read-only)
    M6  (#32) get_context_bundle and `context --format json` return the content
        (slice, surface, callers, impact), keeping the summary keys
    M5  (#34) when a file changed after indexing, the answer carries the
        freshness note as a second text item (the first stays the answer)
    M7  (review 2026-10-30) rename_symbol dry_run=false still rewrites the
        sources (declaring + calling unit) with the store opened read-only, and
        leaves the index DB byte-identical; the dry run is the positive control

  M4 needs python on PATH (it ages the schema of a copy); SKIP 77 otherwise
  for that arm only. Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_mcp_answers_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null

Write-Ascii (Join-Path $src 'uLib.pas') @'
unit uLib;

interface

type
  TA = class
  public
    procedure Run;
  end;

  TB = class
  public
    procedure Run;
  end;

procedure Helper;

implementation

procedure TA.Run;
begin
end;

procedure TB.Run;
begin
end;

procedure Helper;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uUse.pas') @'
unit uUse;

interface

uses
  uLib;

procedure CallA;
procedure CallB;
procedure NoCall;

implementation

procedure CallA;
var
  A: TA;
begin
  A:= TA.Create;
  A.Run;
end;

procedure CallB;
var
  B: TB;
begin
  B:= TB.Create;
  B.Run;
end;

procedure NoCall;
var
  Run: Integer;
begin
  Run:= 1;
  if Run > 0 then Helper;
end;

end.
'@
Write-Ascii (Join-Path $src 'P.dpr') @'
program P;

uses
  uLib in 'uLib.pas',
  uUse in 'uUse.pas';

begin
end.
'@
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $src 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx

# One serve session per request list: stdin from a file, one JSON reply per line.
function Invoke-Serve([string[]]$Requests, [string]$Tag, [string]$Db = $db) {
  $in  = Join-Path $WorkDir "$Tag.in.jsonl"
  $out = Join-Path $WorkDir "$Tag.out.jsonl"
  $err = Join-Path $WorkDir "$Tag.err.txt"
  $all = @('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}') + $Requests
  [IO.File]::WriteAllText($in, (($all -join "`n") + "`n"), [Text.Encoding]::ASCII)
  $p = Start-Process $exePath -ArgumentList 'serve', '--db', "`"$Db`"" -WorkingDirectory $WorkDir `
         -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
  if (-not $p.WaitForExit(60000)) { $p.Kill(); }
  $replies = @{}
  foreach ($line in (Get-Content $out -ErrorAction SilentlyContinue)) {
    if ($line.Trim() -eq '') { continue }
    try { $j = $line | ConvertFrom-Json } catch { continue }
    if ($null -ne $j.id) { $replies[[string]$j.id] = $j }
  }
  $replies
}
function Call([int]$Id, [string]$Tool, [hashtable]$Arguments) {
  (@{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } } | ConvertTo-Json -Compress -Depth 6)
}
function Text($Reply, [int]$Item = 0) { if ($Reply -and $Reply.result -and $Reply.result.content.Count -gt $Item) { [string]$Reply.result.content[$Item].text } else { '' } }

# --- M1/M2/M3 ---------------------------------------------------------------------
$garbage = Join-Path $WorkDir 'not-a-db.sqlite'
[IO.File]::WriteAllText($garbage, 'this is not a sqlite database', [Text.Encoding]::ASCII)
$r = Invoke-Serve @(
  (Call 1 'find_callers' @{ name = 'TA.Run' }),
  (Call 2 'find_callers' @{ name = 'Run' }),
  (Call 4 'get_impact'   @{ qname = 'uLib.TA.Run'; db = $garbage }),
  (Call 5 'find_symbol'  @{ name = 'Helper' }),
  (Call 6 'get_context_bundle' @{ qname = 'uUse.CallA' })
) 'm123'
$t1 = Text $r['1']
Check 'M1 find_callers TA.Run lists CallA' ($t1 -match 'CallA') $t1
Check 'M1 ... and not CallB (the caller of TB.Run)' ($t1 -notmatch 'CallB') $t1
$t2 = Text $r['2']
Check 'M1 find_callers Run lists both real callers' (($t2 -match 'CallA') -and ($t2 -match 'CallB')) $t2
Check 'M1 ... and not NoCall, whose LOCAL Run is written and read' ($t2 -notmatch 'NoCall') $t2
$cli = & $exePath query find-callers --name Run --resolved --db $db 2>&1 | Out-String
Check 'M1 the CLI''s find-callers --resolved no longer calls the local''s read a [callback]' (($cli -match 'CallA') -and ($cli -notmatch 'NoCall[^\r\n]*\[callback\]')) $cli
Check 'M3 a tool that raises answers isError true' ($r['4'] -and $r['4'].result.isError -eq $true) ($r['4'] | ConvertTo-Json -Depth 6 -Compress)
Check 'M3 ... and the server still answers the next call' ((Text $r['5']) -match 'Helper') (Text $r['5'])
$t6 = Text $r['6']
$j6 = try { $t6 | ConvertFrom-Json } catch { $null }
Check 'M6 (#32) get_context_bundle returns the slice, not only its count' ($j6 -and ($j6.PSObject.Properties.Name -contains 'slice') -and @($j6.slice | Where-Object { $_ }).Count -gt 0 -and (@($j6.slice | ForEach-Object { $_.text }) -join ' ') -match 'A\.Run') $t6
Check 'M6 ... and keeps the summary keys' ($j6 -and $j6.resolved -eq $true -and $null -ne $j6.slice_chunks) $t6
$c6 = (& $exePath context --task 'modify uUse.CallA' --format json --db $db 2>$null | Out-String)
$k6 = try { $c6 | ConvertFrom-Json } catch { $null }
Check 'M6 the CLI context --format json carries the same content' ($k6 -and ($k6.PSObject.Properties.Name -contains 'slice') -and @($k6.slice | Where-Object { $_ }).Count -gt 0) $c6

# --- M4: old schema, refused and not migrated -------------------------------------
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
  $old = Join-Path $WorkDir 'old.sqlite'
  Copy-Item $db $old
  $py = Join-Path $WorkDir 'age.py'
  [IO.File]::WriteAllText($py, "import sqlite3,sys`ncon=sqlite3.connect(sys.argv[1])`nif len(sys.argv)>2:`n  con.execute(""UPDATE schema_meta SET value=? WHERE key='schema_version'"",(sys.argv[2],));con.commit()`nprint(con.execute(""SELECT value FROM schema_meta WHERE key='schema_version'"").fetchone()[0])`n", [Text.Encoding]::ASCII)
  $null = & $python.Source -I $py $old '22'
  $r4 = Invoke-Serve @((Call 1 'get_impact' @{ qname = 'uLib.TA.Run'; db = $old })) 'm4'
  $msg = if ($r4['1'].error) { [string]$r4['1'].error.message } else { Text $r4['1'] }
  Check 'M4 an old-schema db is refused, naming the schema' ($msg -match 'schema v22 < v\d+') $msg
  $after = (& $python.Source -I $py $old | Out-String).Trim()
  Check 'M4 ... and NOT migrated (still v22)' ($after -eq '22') "schema_version now $after"
} else {
  Write-Host 'SKIP: python not on PATH -- M4 not run' -ForegroundColor Yellow
}

# --- M7: rename_symbol still WRITES SOURCES while the store is read-only ------------
# serve opens every store read-only now (M4); rename_symbol with dry_run=false is the
# one tool that changes files. It must still apply its edits, and must not touch the
# index. Own copy of the fixture + own DB, so M5's mtime trick cannot make the
# rename refuse as stale. Positive control: the dry run leaves the files unchanged.
$src7 = Join-Path $WorkDir 'src7'
Copy-Item $src $src7 -Recurse
$db7 = Join-Path $WorkDir 'p7.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx7 = & $exePath index --project (Join-Path $src7 'P.dpr') --db $db7 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'M7 SANITY: rename fixture indexed' ($LASTEXITCODE -eq 0) $idx7
$lib7 = Join-Path $src7 'uLib.pas'; $use7 = Join-Path $src7 'uUse.pas'
$dbHash = (Get-FileHash $db7 -Algorithm SHA256).Hash
$r7d = Invoke-Serve @((Call 1 'rename_symbol' @{ qname = 'uLib.Helper'; to = 'HelperRenamed'; dry_run = $true })) 'm7d' $db7
$j7d = try { (Text $r7d['1']) | ConvertFrom-Json } catch { $null }
Check 'M7 control: the dry run lists edits and applies none' ($j7d -and $j7d.applied -eq $false -and @($j7d.edits).Count -ge 2) (Text $r7d['1'])
Check 'M7 control: ... and the sources are untouched' (-not (Select-String -Path $lib7, $use7 -Pattern 'HelperRenamed' -Quiet)) ''
$r7 = Invoke-Serve @((Call 1 'rename_symbol' @{ qname = 'uLib.Helper'; to = 'HelperRenamed'; dry_run = $false })) 'm7' $db7
$t7 = Text $r7['1']
$j7 = try { $t7 | ConvertFrom-Json } catch { $null }
Check 'M7 rename_symbol dry_run=false answers applied, no error' ($r7['1'] -and -not $r7['1'].error -and $r7['1'].result.isError -ne $true -and $j7 -and $j7.applied -eq $true -and -not $j7.error -and $j7.files_touched -ge 2) ($r7['1'] | ConvertTo-Json -Depth 6 -Compress)
Check 'M7 ... the declaring unit is rewritten' ((Get-Content $lib7 -Raw) -match 'procedure HelperRenamed;' -and (Get-Content $lib7 -Raw) -notmatch '\bHelper;') (Get-Content $lib7 -Raw)
Check 'M7 ... and so is the calling unit' ((Get-Content $use7 -Raw) -match 'then HelperRenamed;') (Get-Content $use7 -Raw)
Check 'M7 ... and the index DB is byte-identical (read-only store)' ((Get-FileHash $db7 -Algorithm SHA256).Hash -eq $dbHash) ''

# --- M5: a changed file -> the freshness note, as a second item ---------------------
(Get-Item (Join-Path $src 'uUse.pas')).LastWriteTime = (Get-Date).AddMinutes(5)
$r5 = Invoke-Serve @((Call 1 'find_symbol' @{ name = 'Helper' })) 'm5'
Check 'M5 the answer stays the first item' ((Text $r5['1'] 0) -match 'Helper') (Text $r5['1'] 0)
Check 'M5 the freshness note is a second item' ((Text $r5['1'] 1) -match 'uUse\.pas|changed|stale|refresh') ($r5['1'] | ConvertTo-Json -Depth 6 -Compress)
}
finally {
  $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
