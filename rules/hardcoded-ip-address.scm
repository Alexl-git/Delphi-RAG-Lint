; A hardcoded IPv4 address ties the code to one host/network. Read it from
; configuration. (Heuristic: version strings like '1.2.3.4' share the syntax, so
; this is info-level -- suppress with // drag-lint:ignore where intended.)
((literalString) @warn
  (#match? @warn "^'([0-9]{1,3}\\.){3}[0-9]{1,3}"))
