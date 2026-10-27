; Probe for the sidecar "fix" path (autofix wave A0). NOT a shipped rule: it lives in
; this fixture's _rules\ folder, which run_fix_fixtures.ps1 passes as --rules-dir, so the
; catalog never sees it. A parenthesised lone identifier -> the identifier.
(exprParens (identifier) @x) @warn
