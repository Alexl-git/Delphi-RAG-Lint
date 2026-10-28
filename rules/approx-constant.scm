; A numeric literal whose leading digits match a well-known constant with at
; least 3 decimals: pi 3.141/3.142.., e 2.718.., sqrt(2) 1.414.., ln(2)
; 0.693.., golden ratio 1.618... Anchored at the start so 12.718 never matches;
; two-decimal 3.14 / 2.71 are too common to flag.
; Known FP shape: a genuine measured value that happens to start with these digits.
; Pi to >= 6 decimals (3.14159x): the fix swaps the literal for System.Pi (risky: the trailing
; digits change). Listed FIRST -- when two patterns match one node the first supplies the
; finding and its fix; the generic pattern below excludes the same shape anyway.
((literalNumber) @warn @pi
  (#match? @pi "^3\\.14159[0-9]+$"))

((literalNumber) @warn
  (#not-match? @warn "^3\.14159[0-9]+$")
  (#match? @warn "^(3\.14[12]|2\.718|1\.414|0\.693|1\.618)[0-9]*([eE][-+]?[0-9]+)?$"))
