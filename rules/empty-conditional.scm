; A 'then' or 'else' branch that is just a stray semicolon is a no-op -- the
; classic 'if X then ;' bug where the real body is mis-indented below.
; Empty then:  the 'if' node ends right after 'then' (kThen is its last child).
((if (kThen) @warn .))
; Empty else:  the 'ifElse' node ends right after 'else' (kElse is its last child).
((ifElse (kElse) @warn .))
