; A routine named Is.. / Has.. / Can.. promises a yes/no answer; returning anything else
; surprises the caller. Procedures (no result type) are not flagged.
((declProc
  name: (identifier) @n
  type: (_) @t) @warn
 (#match? @n "^(Is|Has|Can)[A-Z]")
 (#not-match? @t "(?i)^(System\.)?(Boolean|ByteBool|WordBool|LongBool)$"))
