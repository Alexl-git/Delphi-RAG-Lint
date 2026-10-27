; Decimal integer literals of 7 or more digits without a `_` separator are hard
; to read; Delphi 13 accepts digit separators (1_000_000). Hex ($...) and
; literals already containing `_` do not match the all-digits regex.
((literalNumber) @warn
  (#match? @warn "^[0-9]{7,}$"))
