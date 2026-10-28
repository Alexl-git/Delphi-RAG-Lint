; A routine named Is.. / Has.. / Can.. promises a yes/no answer; returning anything else
; surprises the caller. Procedures (no result type) are not flagged. Only the DECLARATION is\r\n; reported: a definition (declProc nested in a defProc) is skipped, so a unit-level routine does\r\n; not fire twice (interface + implementation).
((declProc
  name: (identifier) @n
  type: (_) @t) @warn
 (#match? @n "^(Is|Has|Can)[A-Z]")
 (#not-match? @t "(?i)^(System\.)?(Boolean|ByteBool|WordBool|LongBool)$")
 (#not-in? @warn "defProc"))
