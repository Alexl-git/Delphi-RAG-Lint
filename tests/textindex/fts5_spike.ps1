$exe = "third_party\dll-win64\drag-lint.exe"
# --selftest-fts5 is added in Step 3; it returns exit 0 and prints OK when
# CREATE VIRTUAL TABLE ... USING fts5(x, tokenize='trigram') + a substring MATCH work.
& $exe --selftest-fts5
if ($LASTEXITCODE -ne 0) { Write-Error "FTS5/trigram NOT available -- STOP, revisit --substring"; exit 1 }
"FTS5 + trigram OK"
