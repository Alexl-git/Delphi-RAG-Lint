$Exe = . "$PSScriptRoot\_manifest_common.ps1"
$work = Join-Path $env:TEMP ('draglint_migrate_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
    # A project tree + an out-of-tree DB dir, mirroring today's layout.
    $proj = Join-Path $work 'proj';  New-Item -ItemType Directory $proj | Out-Null
    $out  = Join-Path $work 'out' ;  New-Item -ItemType Directory $out  | Out-Null
    Set-Content -LiteralPath (Join-Path $proj 'App.dproj') -Value '<Project/>' -NoNewline
    Set-Content -LiteralPath (Join-Path $proj 'App.pas')   -Value "unit App;`r`ninterface`r`nimplementation`r`nend."

    # Build a real index at the OLD location so there is something to move.
    $olddb = Join-Path $out 'Old-App.sqlite'
    & $Exe index $proj --db $olddb | Out-Null
    Check 'fixture index built' (Test-Path $olddb)
    $before = & $Exe query --db $olddb --name App --json 2>$null | Out-String

    $cfg = Join-Path $work 'drag-lint.json'
    $j = @{ indexes = @{ outDir = $out; sections = @(
              @{ name = 'Old-App'; db = 'Old-App.sqlite'; include = @((Join-Path $proj 'App.dproj')) } ) } }
    Set-Content -LiteralPath $cfg -Value ($j | ConvertTo-Json -Depth 8)

    $newdb = Join-Path $proj '_D-RAG\App.sqlite'

    # 1. Dry run must NOT touch disk.
    $dry = & $Exe migrate-dbs --config $cfg 2>&1 | Out-String
    Check 'dry-run exits 0'          ($LASTEXITCODE -eq 0)
    Check 'dry-run names the target' ($dry -match [regex]::Escape($newdb))
    Check 'dry-run moved nothing'    ((Test-Path $olddb) -and -not (Test-Path $newdb))

    # 2. Apply moves the DB and its WAL siblings.
    $app = & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-String
    Check 'apply exits 0'        ($LASTEXITCODE -eq 0)
    Check 'db moved'             ((Test-Path $newdb) -and -not (Test-Path $olddb))
    Check 'no -wal left behind'  (-not (Test-Path "$olddb-wal"))
    Check 'gitignore written'    (Test-Path (Join-Path $proj '_D-RAG\.gitignore'))
    Check 'gitignore ignores all' ((Get-Content (Join-Path $proj '_D-RAG\.gitignore') -Raw).Trim() -eq '*')

    # 3. The moved index still answers, and the manifest now derives the path.
    $after = & $Exe query --db $newdb --name App --json 2>$null | Out-String
    Check 'moved index still answers' ($after.Trim() -eq $before.Trim())
    $plan = & $Exe index --all --dry-run --json --config $cfg 2>$null | Out-String
    Check 'manifest points at _D-RAG' ($plan -match '_D-RAG')

    # 4. Re-running is a no-op, not an error.
    & $Exe migrate-dbs --config $cfg --apply 2>&1 | Out-Null
    Check 'second apply is a no-op' ($LASTEXITCODE -eq 0)

    # 5. A locked DB aborts with exit 2 and names the file.
    $newdb2 = Join-Path $proj '_D-RAG\App.sqlite'
    $fs = [IO.File]::Open($newdb2, 'Open', 'ReadWrite', 'None')
    try {
        $j2 = @{ indexes = @{ outDir = $out; sections = @(
                  @{ name = 'Old-App'; db = $newdb2; include = @((Join-Path $proj 'App.dproj')) } ) } }
        $cfg2 = Join-Path $work 'locked.json'
        Set-Content -LiteralPath $cfg2 -Value ($j2 | ConvertTo-Json -Depth 8)
        $lock = & $Exe migrate-dbs --config $cfg2 --apply 2>&1 | Out-String
        Check 'locked db aborts with 2' ($LASTEXITCODE -eq 2)
        Check 'lock error names the file' ($lock -match 'App.sqlite')
    } finally { $fs.Close() }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($script:Failed) { exit 1 } else { exit 0 }
