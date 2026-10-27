; Probe for the sidecar "fix": {"delete": "statement"} path (autofix wave A0). NOT a shipped
; rule: run_fix_fixtures.ps1 passes this folder as --rules-dir. Flags every call to ProbeNoop.
((exprCall entity: (identifier) @f) @warn (#eq? @f "ProbeNoop"))
