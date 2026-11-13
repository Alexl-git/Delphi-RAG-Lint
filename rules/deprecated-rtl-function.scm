; Obsolete RTL routines -- prefer modern encoding/conversion equivalents.
; OemToAnsi/AnsiToOem: use TEncoding. StrPas: use string() cast directly.
((exprCall entity: (identifier) @fn) @warn
 (#any-of? @fn "OemToAnsi" "AnsiToOem" "StrPas"
   "GetWindowLong" "SetWindowLong" "GetClassLong" "SetClassLong"))
; v151 WID-SCM: GetWindowLong / SetWindowLong / GetClassLong / SetClassLong are the
; 32-bit-only accessors (they truncate pointer-sized values on Win64: use the *Ptr
; variant). TThread.Resume / Suspend are deprecated since Delphi 2010 (use Start /
; a TEvent). The receiver must be named like a thread: a bare Resume/Suspend member
; on an arbitrary object (TTimer-like, queues) is not this API.
((exprDot
   lhs: (identifier) @obj
   rhs: (identifier) @warn)
 (#any-of? @warn "Resume" "Suspend")
 (#match? @obj "(?i)(thread|worker)"))
