<#
  run_lsp_reader_guard.ps1 -- the LSP server is a READER of every --db it is
  handed (PLAN-multi-client-index-safety, ruling 2, T1/T3).

  THE DEFECT THIS PINS. TLSPServer.Create looped over every --db and did
  `TSQLiteSymbolStore.Create(Path)` (writable) then `.Migrate` (DDL). So every
  editor held a WRITABLE, MIGRATED connection to the real project index and to
  the 2.98 GB library index -- and an editor running an OLDER engine migrated
  the database it was only supposed to read. The owner's ruling: only the IDE
  writes; every other client reads.

  A true SQLITE_OPEN_READONLY cannot be used (WAL needs write access to -shm);
  `PRAGMA query_only` is the mechanism, and the journal mode the connection
  names must be the one the file ALREADY has, because FireDAC runs
  `PRAGMA journal_mode = <param>` on every connect (W1, HeaderSaysWal).

  CASES (each measured on a RECREATED fixture):

    C1  WAL project DB     -> a full session (didOpen, hover, definition,
                              references, completion, workspace/symbol,
                              shutdown, exit) leaves the file byte-identical,
                              leaves no -wal behind, and STILL ANSWERS -- a
                              reader that answers nothing is not a reader
    C2  rollback-journal   -> header byte 18 stays 1: the read-only connect
        DB                    does not convert the file to WAL (RED before the
                              header-match fix reached Connect)
    C3  STALE schema (v12) -> named FIRST on the command line, so first-match
                              cannot skip it: the server REFUSES it on stderr
                              (names the schema gap), leaves it byte-identical,
                              and still serves the current DB behind it
    PC  positive control   -> `index` on the same v12 file DOES change its md5,
                              so the byte-identity sentinel can see a migrate;
                              without this C3 passes with a sentinel that
                              cannot fail
    S   static             -> every `.Migrate` in DRagLint.LSP.Server.pas is
                              attributed to BuildEphemeralStore (the %TEMP%
                              single-unit store, which is legitimately
                              writable); the --db loop opens read-only. With a
                              positive control that the attribution scan can
                              see a `.Migrate` planted in the constructor.

  RED FIRST against 1.12.0-alpha: C2 (header 1 -> 2), C3 (v12 md5 changes,
  no refusal on stderr) and S fail; C1 and PC pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Source  = "$PSScriptRoot\..\..\src\lsp\DRagLint.LSP.Server.pas",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-reader-guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
function Md5([string]$Path) { (Get-FileHash -Algorithm MD5 -Path $Path).Hash }
function WriteAscii($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 12
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}
# SQLite header offset 18: 2 = WAL, 1 = rollback journal (sqlite.org/fileformat2).
function HeaderWriteVersion([string]$Db) {
  $fs = [System.IO.File]::Open($Db, 'Open', 'Read', 'ReadWrite')
  try { $buf = New-Object byte[] 19; $n = $fs.Read($buf, 0, 19); if ($n -lt 19) { return -1 }; return [int]$buf[18] }
  finally { $fs.Dispose() }
}
function SidecarBytes([string]$Db) {
  $w = "$Db-wal"; if (Test-Path $w) { return (Get-Item $w).Length } else { return 0 }
}

if (-not (Test-Path $Exe))    { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Source)) { Write-Host "FATAL: source not found: $Source" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
New-Item -ItemType Directory "$WorkDir\projsrc" | Out-Null

# ---------------------------------------------------------------- fixture ---
$projText = @'
unit ProjUnit;

interface

type
  TProjectThing = class
  public
    procedure ProjectOwnMethod(ACount: Integer);
  end;

procedure DriveProject;

implementation

procedure TProjectThing.ProjectOwnMethod(ACount: Integer);
begin
end;

procedure DriveProject;
var
  PThing: TProjectThing;
begin
  PThing := TProjectThing.Create;
  PThing.ProjectOwnMethod(1);
end;

end.
'@
$projFile = Join-Path $WorkDir 'projsrc\ProjUnit.pas'
WriteAscii $projFile $projText
$projLines = $projText -split "`r?`n"
$declLine  = [Array]::FindIndex($projLines, [Predicate[string]]{ param($x) $x -like '*procedure TProjectThing.ProjectOwnMethod(*' })
$declCol   = $projLines[$declLine].IndexOf('.ProjectOwnMethod') + 3
$callLine  = [Array]::FindIndex($projLines, [Predicate[string]]{ param($x) $x -like '*PThing.ProjectOwnMethod(1);*' })
$dotCol    = $projLines[$callLine].IndexOf('.') + 1

$pristine = Join-Path $WorkDir 'pristine.sqlite'
$o0 = (& $Exe index "$WorkDir\projsrc" --db $pristine 2>&1 | Out-String)
Check 'V1 fixture index exits 0' ($LASTEXITCODE -eq 0) ($o0 -split "`r?`n" | Select-Object -Last 1)
Check 'V2 fixture has NO pending -wal' ((SidecarBytes $pristine) -eq 0) "wal bytes=$(SidecarBytes $pristine)"
Check 'V3 fixture is WAL (header byte 18 = 2)' ((HeaderWriteVersion $pristine) -eq 2) "byte18=$(HeaderWriteVersion $pristine)"
$files0 = (& python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('SELECT COUNT(*) FROM files').fetchone()[0])" $pristine).Trim()
Check 'V4 fixture is POPULATED (files rows > 0), not merely present' ([int]$files0 -gt 0) "files=$files0"

# A full editor session: everything a client sends in the first minute.
function Invoke-Session([string[]]$Dbs, [string]$Tag) {
  $uri  = 'file:///' + ($projFile -replace '\\', '/')
  $msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didOpen';
                    params = @{ textDocument = @{ uri = $uri; languageId = 'pascal'; version = 1; text = $projText } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $declLine; character = $declCol } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'textDocument/definition';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $declLine; character = $declCol } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 4; method = 'textDocument/references';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $declLine; character = $declCol }; context = @{ includeDeclaration = $true } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 5; method = 'textDocument/completion';
                    params = @{ textDocument = @{ uri = $uri }; position = @{ line = $callLine; character = $dotCol } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 6; method = 'workspace/symbol'; params = @{ query = 'Proj' } }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'textDocument/didSave'; params = @{ textDocument = @{ uri = $uri } } }
  $msgs += Frame @{ jsonrpc = '2.0'; id = 7; method = 'shutdown'; params = @{} }
  $msgs += Frame @{ jsonrpc = '2.0'; method = 'exit'; params = @{} }

  $inF = Join-Path $WorkDir "$Tag-in.txt"; $outF = Join-Path $WorkDir "$Tag-out.txt"; $errF = Join-Path $WorkDir "$Tag-err.txt"
  [System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
  $argv = @('lsp'); foreach ($d in $Dbs) { $argv += @('--db', $d) }
  $p = Start-Process $Exe -ArgumentList $argv -WorkingDirectory $WorkDir `
         -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
         -NoNewWindow -Wait -PassThru
  $raw = [System.IO.File]::ReadAllText($outF)
  $err = [System.IO.File]::ReadAllText($errF)
  $hover = '<NO REPLY>'
  foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 2) { $hover = if ($null -eq $o.result) { '' } else { [string]$o.result.contents.value } }
  }
  return @{ Raw = $raw; Err = $err; Hover = $hover; Exit = $p.ExitCode }
}

# ---- C1: a WAL project DB survives a full session byte-identical -------------
Write-Host ''
Write-Host 'C1: WAL project DB -- full session, byte-identical, still answering' -ForegroundColor Cyan
$c1 = Join-Path $WorkDir 'c1.sqlite'
Copy-Item $pristine $c1
$md5 = Md5 $c1
$r1 = Invoke-Session @($c1) 'c1'
Check 'C1 hover answers from the project DB (a reader still reads)' ($r1.Hover -match 'ProjUnit\.TProjectThing\.ProjectOwnMethod') "got: [$($r1.Hover)]"
Check 'C1 file byte-identical after the session' ((Md5 $c1) -eq $md5) "before=$md5 after=$(Md5 $c1)"
Check 'C1 no -wal left behind' ((SidecarBytes $c1) -eq 0) "wal bytes=$(SidecarBytes $c1)"
Check 'C1 header still WAL' ((HeaderWriteVersion $c1) -eq 2)
Check 'C1 stderr reports no open failure' ($r1.Err -notmatch 'could not open') $r1.Err

# ---- C2: a rollback-journal DB is not converted to WAL by a reader -----------
Write-Host ''
Write-Host 'C2: rollback-journal DB -- the read-only connect names the mode the file already has' -ForegroundColor Cyan
$c2 = Join-Path $WorkDir 'c2.sqlite'
Copy-Item $pristine $c2
& python -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); print(c.execute('PRAGMA journal_mode=DELETE').fetchone()[0]); c.close()" $c2 | Out-Null
Check 'C2 precondition: header byte 18 = 1 (rollback journal)' ((HeaderWriteVersion $c2) -eq 1) "byte18=$(HeaderWriteVersion $c2)"
$md5 = Md5 $c2
$r2 = Invoke-Session @($c2) 'c2'
Check 'C2 hover still answers' ($r2.Hover -match 'ProjUnit\.TProjectThing\.ProjectOwnMethod') "got: [$($r2.Hover)]"
Check 'C2 header STILL 1 -- the reader did not rewrite the journal mode' ((HeaderWriteVersion $c2) -eq 1) "byte18=$(HeaderWriteVersion $c2)"
Check 'C2 file byte-identical' ((Md5 $c2) -eq $md5) "before=$md5 after=$(Md5 $c2)"

# ---- C3: a STALE-schema DB, named FIRST, is refused and left alone ----------
Write-Host ''
Write-Host 'C3: stale (v12) DB named FIRST -- refused on stderr, byte-identical, current DB still served' -ForegroundColor Cyan
$pyV12 = Join-Path $WorkDir 'make_v12.py'
WriteAscii $pyV12 @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.executescript("""
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO schema_meta(key, value) VALUES ('schema_version', '12');
CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE,
  mtime_unix INTEGER NOT NULL, sha256 TEXT NOT NULL,
  parsed_at INTEGER NOT NULL, language TEXT NOT NULL);
INSERT INTO files(path, mtime_unix, sha256, parsed_at, language) VALUES ('C:\\nowhere\\Stale.pas', 1, 'x', 1, 'delphi');
CREATE TABLE symbols (id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  parent_id INTEGER REFERENCES symbols(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name TEXT NOT NULL, qualified_name TEXT NOT NULL,
  signature TEXT, modifiers TEXT, section TEXT, heritage TEXT,
  is_virtual INTEGER, start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL,
  impl_start_line INTEGER, impl_end_line INTEGER);
CREATE TABLE refs (id INTEGER PRIMARY KEY,
  symbol_id INTEGER REFERENCES symbols(id) ON DELETE SET NULL,
  file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, name_text TEXT NOT NULL,
  start_line INTEGER NOT NULL, start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL, end_col INTEGER NOT NULL);
""")
c.commit()
c.close()
'@
$pyGet = Join-Path $WorkDir 'meta_get.py'
WriteAscii $pyGet @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
r = c.execute("SELECT value FROM schema_meta WHERE key = ?", (sys.argv[2],)).fetchone()
print('' if r is None else r[0])
c.close()
'@
$v12 = Join-Path $WorkDir 'v12.sqlite'
& python $pyV12 $v12
Check 'C3 precondition: v12 fixture created, POPULATED (one files row)' (($LASTEXITCODE -eq 0) -and (Test-Path $v12))
$c3cur = Join-Path $WorkDir 'c3-current.sqlite'
Copy-Item $pristine $c3cur
$md5v12 = Md5 $v12
$md5cur = Md5 $c3cur
$r3 = Invoke-Session @($v12, $c3cur) 'c3'
Check 'C3 stderr REFUSES the stale DB by name' (($r3.Err -match 'index schema v12 < v\d+') -and ($r3.Err -match [regex]::Escape((Split-Path $v12 -Leaf)))) $r3.Err
Check 'C3 stderr says a reader does not migrate' ($r3.Err -match '(?i)refus|not migrat|reader') ''
Check 'C3 the stale DB is byte-identical (NOT migrated by the editor)' ((Md5 $v12) -eq $md5v12) "before=$md5v12 after=$(Md5 $v12)"
Check 'C3 the stale DB still says schema 12' ((& python $pyGet $v12 'schema_version').Trim() -eq '12') "schema_version=$((& python $pyGet $v12 'schema_version').Trim())"
Check 'C3 the CURRENT DB behind it is still served (hover answers)' ($r3.Hover -match 'ProjUnit\.TProjectThing\.ProjectOwnMethod') "got: [$($r3.Hover)]"
Check 'C3 the current DB is byte-identical too' ((Md5 $c3cur) -eq $md5cur)

# ---- PC: the sentinel can see a migrate -------------------------------------
Write-Host ''
Write-Host 'PC: POSITIVE CONTROL -- a real write (index) on the v12 file DOES move the md5' -ForegroundColor Cyan
$v12w = Join-Path $WorkDir 'v12-writable.sqlite'
& python $pyV12 $v12w
$md5w = Md5 $v12w
$pcOut = (& $Exe index "$WorkDir\projsrc" --db $v12w 2>&1 | Out-String)
Check 'PC index on the v12 file exits 0 (it migrates, as a writer should)' ($LASTEXITCODE -eq 0) ($pcOut -split "`r?`n" | Select-Object -Last 1)
Check 'PC md5 CHANGED -- so byte-identity above is a real assertion' ((Md5 $v12w) -ne $md5w) "before=$md5w after=$(Md5 $v12w)"

# ---- S: static -- .Migrate reachable only from the ephemeral store -----------
Write-Host ''
Write-Host 'S: STATIC -- every .Migrate in the LSP server belongs to BuildEphemeralStore; the --db loop opens read-only' -ForegroundColor Cyan
function Find-MigrateSites([string[]]$Lines) {
  $cur = '(before any routine)'
  $sites = @()
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $l = $Lines[$i]
    if ($l -match '^(function|procedure|constructor|destructor)\s+([A-Za-z_][A-Za-z0-9_.]*)') { $cur = $Matches[2] }
    if ($l -match '\.Migrate\b') { $sites += [pscustomobject]@{ Routine = $cur; Line = ($i + 1) } }
  }
  return $sites
}
$synthetic = @(
  'constructor TLSPServer.Create(const ADbPaths: TArray<string>);',
  'begin',
  '  S:= TSQLiteSymbolStore.Create(Path);',
  '  S.Migrate;',
  'end;',
  'function TLSPServer.BuildEphemeralStore(const APath: string; AStamp: TDateTime): Boolean;',
  'begin',
  '  S.Migrate;',
  'end;'
)
$ctl = @(Find-MigrateSites $synthetic)
Check 'S0 POSITIVE CONTROL: the scan attributes a .Migrate planted in the constructor' `
      (($ctl.Count -eq 2) -and ($ctl[0].Routine -eq 'TLSPServer.Create') -and ($ctl[1].Routine -eq 'TLSPServer.BuildEphemeralStore')) `
      (($ctl | ForEach-Object { "$($_.Routine)@$($_.Line)" }) -join ', ')
$srcLines = [System.IO.File]::ReadAllLines($Source)
$sites = @(Find-MigrateSites $srcLines)
Check 'S1 the scan found .Migrate sites at all (the ephemeral store still migrates its own %TEMP% db)' ($sites.Count -gt 0) ''
$outside = @($sites | Where-Object { $_.Routine -ne 'TLSPServer.BuildEphemeralStore' })
Check 'S2 no .Migrate outside BuildEphemeralStore (the --db loop does not migrate)' ($outside.Count -eq 0) `
      (($outside | ForEach-Object { "$($_.Routine)@$($_.Line)" }) -join ', ')
# The --db loop's open: inside the TArray constructor, a Create(Path, ...True)
$ctorFrom = [Array]::FindIndex($srcLines, [Predicate[string]]{ param($x) $x -match '^constructor TLSPServer\.Create\(const ADbPaths' })
$ctorTo   = $ctorFrom
while ($ctorTo -lt $srcLines.Count -and $srcLines[$ctorTo] -notmatch '^end;') { $ctorTo++ }
$ctorBody = ($srcLines[$ctorFrom..$ctorTo] -join "`n")
Check 'S3 found the --db constructor' ($ctorFrom -ge 0) "from=$ctorFrom to=$ctorTo"
Check 'S4 the --db constructor opens each store READ-ONLY (Create(Path, ...True))' ($ctorBody -match 'TSQLiteSymbolStore\.Create\(\s*Path\s*,[^)]*True\s*\)') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
