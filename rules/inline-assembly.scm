; An inline 'asm ... end' block is not portable across compilers and target
; platforms (Win32/Win64/ARM) and is opaque to the optimizer and to analysis.
; Prefer a Pascal implementation where possible.
((asm) @warn)
