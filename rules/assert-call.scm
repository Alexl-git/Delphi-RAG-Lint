; Assert() with only a condition (and no message argument) produces an
; unhelpful 'Assertion failure' at runtime. 'Single argument' is approximated
; by the absence of a comma in the argument-list text, so a two-arg
; Assert(cond, 'message') is not flagged. (A call whose sole argument itself
; contains a comma, e.g. Assert(SameText(a, b)), is conservatively skipped.)
((exprCall
  entity: (identifier) @callee
  args: (exprArgs) @args) @warn
  (#eq? @callee "Assert")
  (#not-match? @args ","))
