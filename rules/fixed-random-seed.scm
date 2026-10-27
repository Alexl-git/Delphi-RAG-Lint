; RandSeed := <literal> makes the Random sequence predictable (CWE-336, MSC32-C).
; Legitimate in tests and simulations that need reproducibility -- the rule is info for that
; reason. Randomize and a non-literal seed are silent.
((assignment
   lhs: (identifier) @name
   rhs: (literalNumber) @val) @warn
  (#eq? @name "RandSeed"))
