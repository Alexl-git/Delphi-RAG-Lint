; begin..end around exactly one statement that is the body of an if/else/for/while/with.
; Style rule (OFF by default); the opposite opinion of missing-begin-end. A then-branch of an
; if..else is only reported when the lone statement is not itself a conditional or loop:
; removing the brackets around a nested if would re-bind a following else (dangling else).
((if then: (block (kBegin) . (_) . (kEnd)) @warn))
((ifElse then: (block (kBegin) . (_) @s . (kEnd)) @warn)
  (#not-match? @s "(?i)^(if|for|while|with|repeat|case|try)"))
((ifElse else: (block (kBegin) . (_) . (kEnd)) @warn))
((while body: (block (kBegin) . (_) . (kEnd)) @warn))
((for body: (block (kBegin) . (_) . (kEnd)) @warn))
((with body: (block (kBegin) . (_) . (kEnd)) @warn))
((foreach body: (block (kBegin) . (_) . (kEnd)) @warn))
