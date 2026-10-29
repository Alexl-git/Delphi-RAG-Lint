; `if A then if B then X` with no else on either level collapses to
; `if A and B then X`. Reported on the outer if. An `ifElse` (outer or inner)
; is a different node type, so the else cases never match.
((if condition: (_) @a then: (if condition: (_) @b then: (_) @s)) @warn)

; begin/end form: the block must hold exactly ONE statement, the inner if.
; Sibling anchors are NOT reliable here (measured 2026-10-27: `(kBegin) . (if)`
; also matched `begin if B then X; Y; Z; end`, and a trailing anchor never
; constrains), so the single-statement test is a text check on the block:
; begin, the inner if with no ';' inside it, an optional ';', then end. A
; second statement breaks the match (the ';' is followed by something other
; than end). A block whose inner if holds a nested begin/end or another ';'
; is skipped (known false negative, deliberately conservative). The final end must
; be the block's own: `$` does not match at the end of the capture in this engine
; (the text it sees carries trailing punctuation), so end\b[^A-Za-z0-9_]*(?![\s\S])
; pins it. Without that an 'end' INSIDE the first statement (a string literal, a
; comment) passed, and the fix dropped every later statement in the block.
((if
   condition: (_) @a2
   then: (block (kBegin) (if condition: (_) @b2 then: (_) @s2) (kEnd)) @blk) @warn
  (#match? @blk "(?i)^begin\\s*if\\b[^;]*;?(\\s|//[^\\r\\n]*)*end\\b[^A-Za-z0-9_]*(?![\\s\\S])"))
