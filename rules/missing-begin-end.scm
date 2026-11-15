; A conditional or loop whose body is a bare single statement, not wrapped in begin..end.
; Style rule (OFF by default): always bracketing the body keeps later edits from silently
; falling outside the branch. An "else if" chain link, a nested try/case body and a body
; that already starts with begin are accepted.
((if then: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
((ifElse then: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
((ifElse else: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm|if)\\b"))
((while body: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
((for body: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
((with body: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
((foreach body: (_) @b) @warn (#not-match? @b "(?i)^(begin|try|case|asm)\\b"))
