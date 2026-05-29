; Integer literals that are not in a small set of 'innocent' values
; (0, 1, -1, 2, 10, 16, 32, 64, 100, 128, 256, 1000) may be magic
; numbers that deserve a named constant.
; NOTE: matches all literalNumber nodes including floats; the regex
; filter restricts to decimal integers not in the allow-list.
; Hex literals ($FF etc.) pass through if they are not in the list.
((literalNumber) @magic
  (#not-match? @magic "^(0|1|2|10|16|32|64|100|128|256|1000|-1)$"))
