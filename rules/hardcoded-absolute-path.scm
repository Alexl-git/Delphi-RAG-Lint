; A hardcoded absolute path (e.g. 'C:\...') breaks on other machines and
; deployments. Read it from configuration, or compute it at runtime (TPath,
; known-folder APIs). Matches a string literal beginning with a drive letter.
((literalString) @warn
  (#match? @warn "^'[A-Za-z]:"))
