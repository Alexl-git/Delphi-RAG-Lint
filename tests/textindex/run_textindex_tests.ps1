# End-to-end text-constant index harness. Run from the repo root.
# NOTE: the SQL fixture is named MSexceptions.sql (not exceptions.sql) on
# purpose: the indexer's default walk filter (SqlOnlyMS=True) only indexes
# .sql files whose name starts with "MS" -- the migration-script convention
# where Firebird CREATE EXCEPTION messages actually live. Plain ad-hoc .sql
# is skipped by default (use --no-sql-ms to index every .sql).
$exe = "third_party\dll-win64\drag-lint.exe"
$sb  = "$env:TEMP\dl_textindex"; Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "tests\textindex" $sb -Recurse
$db = "$sb\idx.sqlite"
& $exe index $sb --db $db | Out-Null
$fail = 0
function Check($name,$cond){ if($cond){"PASS $name"} else {"FAIL $name"; $script:fail++} }

$phrase = & $exe query --text "folder not found" --db $db --json | ConvertFrom-Json
Check "phrase finds .pas resourcestring" ($phrase.kind -contains 'resourcestring')
Check "phrase finds .dfm caption"        (($phrase | Where-Object { $_.source -eq 'dfm' }).Count -ge 1)
Check "phrase finds .sql exception"      (($phrase | Where-Object { $_.source -eq 'sql' }).Count -ge 1)
Check "phrase hits are message text only" (($phrase.Count -ge 3) -and (($phrase | Where-Object { $_.text -ne 'Folder not found' }).Count -eq 0))

$const = & $exe query --text "save as" --db $db --json | ConvertFrom-Json
Check "phrase finds .pas const"          (($const | Where-Object { $_.kind -eq 'const' }).Count -ge 1)

$any = & $exe query --text "folder found" --any-order --db $db --json | ConvertFrom-Json
Check "any-order matches" ($any.Count -ge 1)

$sub = & $exe query --text "older" --substring --db $db --json | ConvertFrom-Json
Check "substring 'older' matches 'Folder'" ($sub.Count -ge 1)

$dfm = & $exe query --text "folder" --source dfm --db $db --json | ConvertFrom-Json
Check "source filter dfm" (($dfm.Count -ge 1) -and (($dfm | Where-Object { $_.source -ne 'dfm' }).Count -eq 0))

# negative: the *.pas variable/method named Folder must never appear as a hit
$allFolder = & $exe query --text "folder" --substring --db $db --json | ConvertFrom-Json
Check "no var/method 'Folder' as a hit" (($allFolder | Where-Object { $_.text -eq 'Folder' }).Count -eq 0)

if ($fail -gt 0) { Write-Error "$fail textindex test(s) failed"; exit 1 } else { "textindex: all pass" }
