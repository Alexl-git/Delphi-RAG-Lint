# LSP codeAction integration test
# Verifies: LSP textDocument/codeAction handler is implemented and wired in.
#
# The handler: extracts finding diagnostics for a given range, filters to
# suppressible rules, creates TextEdits via TReviewMarkers.InsertInto,
# and returns CodeAction objects with a WorkspaceEdit (fixed to map URIs to
# TextEdit arrays, per LSP spec).
#
# WHAT THIS RUNNER IS, STATED HONESTLY: a SOURCE-SHAPE guard. Every check below
# is a regex over .pas text, so it asserts that the wiring LOOKS right, not that
# it works -- it would stay green if the handler returned null for every request.
#
# The behavioural half now exists: run_lsp_codeaction_endtoend.ps1 starts the
# server, completes an initialize handshake, issues a real
# textDocument/codeAction, and carries a negative control (a diagnostic from
# another source must yield NO action).
#
# One check was REMOVED here rather than kept: `Check '... compiles' $true` could
# not fail under any circumstance, which this repo treats as worse than no check
# at all -- the build's own exit code already covers it.

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'

if (-not (Test-Path $exe)) {
  Write-Output "lsp-codeaction: FATAL -- no drag-lint at $exe"
  exit 1
}

$pass = 0
$fail = 0

function Check($name, $cond) {
  if ($cond) {
    $script:pass++
    Write-Output "PASS  $name"
  } else {
    $script:fail++
    Write-Output "FAIL  $name"
  }
}

# Test 1: Verify the executable exists and has the LSP handler built in.
# We check this by verifying that the codeActionProvider capability was
# declared in HandleInitialize (compile-time verification).
Check 'LSP server executable exists' (Test-Path $exe)

# Test 2: Verify key implementation details are in place:
# - HandleCodeAction is wired into the Run() dispatch loop
# - BuildCodeActions creates WorkspaceEdit with correct structure (URI -> TextEdit[])
# - TReviewMarkers is imported and used in the handler
# These are verified by reading the source files (static analysis).
$serverPath = Join-Path $PSScriptRoot '..\..\src\lsp\DRagLint.LSP.Server.pas'
$completionPath = Join-Path $PSScriptRoot '..\..\src\lsp\DRagLint.LSP.Completion.pas'

$serverSource = Get-Content $serverPath -Raw
$completionSource = Get-Content $completionPath -Raw

Check 'HandleCodeAction is wired in Run dispatch' ($serverSource -match "textDocument/codeAction.*HandleCodeAction")
Check 'codeActionProvider is enabled in Initialize' ($serverSource -match "codeActionProvider.*TJSONBool.Create\(True\)")
Check 'BuildCodeActions creates ChangesMap (URI->TextEdit[] structure)' ($completionSource -match "ChangesMap")
Check 'ReviewMarker import present in Completion' ($completionSource -match 'DRagLint\.Lint.*\.ReviewMarker')
Check 'TReviewMarkers.InsertInto is called' ($completionSource -match 'TReviewMarkers\.InsertInto')

Write-Output ''
Write-Output "lsp-codeaction: $pass pass / $fail fail / $($pass + $fail) total"
if ($fail -gt 0) { exit 1 } else { exit 0 }
