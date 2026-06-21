; 'on E: SomeException do ;' -- an exception handler with an empty body silently
; swallows that specific exception. Log it or re-raise. The '.' anchor asserts
; 'do' is the handler's last child, so there is no handler-body statement.
((exceptionHandler (kDo) @warn .))
