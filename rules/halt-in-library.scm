; Halt / ExitProcess / TerminateProcess(GetCurrentProcess, ..) in a UNIT ends the whole process
; from code no caller can see, skipping finalization. Only the main program may decide that:
; require_ancestor "unit" keeps the .dpr (root `program`) silent. Terminating ANOTHER process
; (TerminateProcess with a different handle) is not flagged. Application.Terminate has its own
; rule (application-terminate-in-library).
([
  (exprCall entity: (identifier) @fn)
  (statement (identifier) @fn)
 ] @warn
 (#any-of? @fn "Halt" "ExitProcess"))
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (exprCall entity: (identifier) @h))) @warn
 (#eq? @fn "TerminateProcess")
 (#eq? @h "GetCurrentProcess"))
; GetCurrentProcess is parenless in practice: the first argument is a bare identifier.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (identifier) @h)) @warn
 (#eq? @fn "TerminateProcess")
 (#eq? @h "GetCurrentProcess"))
