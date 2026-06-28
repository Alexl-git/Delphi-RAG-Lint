; Sleep() on the main VCL thread freezes the UI. Use TTimer or TThread.Sleep
; in a background thread instead. Sleep(0) as a yield hint is also flagged --
; prefer Application.ProcessMessages or TThread.Yield if that is the intent.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "Sleep"))
