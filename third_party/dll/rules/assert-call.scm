; Assert() calls without a second message argument are hard to debug.
; Ensure the second argument provides a descriptive failure message.
((exprCall
  entity: (identifier) @callee) @warn
  (#eq? @callee "Assert"))
