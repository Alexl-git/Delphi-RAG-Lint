; `if A then if B then X` with no else on either level collapses to
; `if A and B then X`. Reported on the outer if. An `ifElse` (outer or inner)
; is a different node type, so the else cases never match.
((if then: (if)) @warn)

; begin/end form: the block must hold exactly ONE statement, the inner if.
; Sibling anchors are NOT reliable here (measured 2026-10-27: `(kBegin) . (if)`
; also matched `begin if B then X; Y; Z; end`, and a trailing anchor never
; constrains), so the single-statement test is a text check on the block:
; begin, the inner if with no ';' inside it, an optional ';', then end. A
; second statement breaks the match (the ';' is followed by something other
; than end). A block whose inner if holds a nested begin/end or another ';'
; is skipped (known false negative, deliberately conservative). No `$`
; anchor: the engine's regex does not match it at the end of the capture.
((if
   then: (block (kBegin) (if) (kEnd)) @blk) @warn
  (#match? @blk "(?i)^begin\\s*if\\b[^;]*;?(\\s|//[^\\r\\n]*)*end\\b"))
