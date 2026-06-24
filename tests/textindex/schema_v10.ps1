$exe = "third_party\dll-win64\drag-lint.exe"
$sb  = "$env:TEMP\dl_schema_v10"; Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $sb | Out-Null
Set-Content "$sb\a.pas" "unit A; interface implementation const C = 'hello world'; end."
& $exe index $sb --db "$sb\idx.sqlite" | Out-Null
# --selftest-schema (added below) prints the table names that exist.
$out = & $exe --selftest-schema --db "$sb\idx.sqlite"
foreach ($t in 'string_literals','string_fts','string_fts_tri') {
  if ($out -notmatch $t) { Write-Error "missing table $t"; exit 1 }
}
"schema v10 OK"
