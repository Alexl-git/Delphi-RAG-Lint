; A hex literal containing both upper-case and lower-case letter digits, e.g.
; $AbCd or $12aB. All-one-case hex and digits-only hex are fine.
; The dollar sign is written as [$] -- an escaped \$ does not survive the
; engine's predicate regex handling.
((literalNumber) @warn
  (#match? @warn "^[$][0-9a-fA-F_]*([a-f][0-9a-fA-F_]*[A-F]|[A-F][0-9a-fA-F_]*[a-f])"))
