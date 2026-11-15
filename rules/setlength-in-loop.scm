; SetLength(A, Length(A) + 1) inside a loop copies the whole array on every pass (quadratic).
; Grow geometrically (capacity doubling) or count first and size once.
((exprCall) @warn
  (#match? @warn "(?i)^SetLength\\s*\\(\\s*([A-Za-z_][\\w.]*)\\s*,\\s*Length\\s*\\(\\s*\\1\\s*\\)\\s*\\+\\s*1\\s*\\)$"))
