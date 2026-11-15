; 'on E: SomeException do ;' -- an exception handler with an empty body silently
; swallows that specific exception. Log it or re-raise. The '.' anchor asserts
; 'do' is the handler's last child, so there is no handler-body statement.
; A comment is a child node too, so 'on E do // why' + ';' ended in the comment
; and the first pattern missed it: a comment -- a dl:ok marker included --
; silenced the rule, and the marker was then reported unused (INBOX
; review-marker-unused-on-handler, v151 RMU). The other patterns let one to four
; comments follow 'do'. Spelled out because '(comment)+' between two anchors
; matched only a single comment in this engine (measured, v151 RMU).
((exceptionHandler (kDo) @warn .))
((exceptionHandler (kDo) @warn . (comment) .))
((exceptionHandler (kDo) @warn . (comment) . (comment) .))
((exceptionHandler (kDo) @warn . (comment) . (comment) . (comment) .))
((exceptionHandler (kDo) @warn . (comment) . (comment) . (comment) . (comment) .))
