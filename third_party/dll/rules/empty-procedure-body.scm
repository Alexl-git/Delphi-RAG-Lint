; Empty procedure/function bodies are usually dead code or forgotten stubs.
; Matches defProc whose body text is just 'begin ... end' with no statements.
; NOTE: uses #match? on the body text. The pattern tolerates optional whitespace
; between begin and end but does NOT skip comments inside the block.
((defProc
   body: (_) @body) @warn
  (#match? @body "^\\s*begin\\s*end\\s*$"))
