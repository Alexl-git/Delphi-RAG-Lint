; Sleep() on the main VCL thread freezes the UI. Use TTimer or TThread.Sleep
; in a background thread instead. Sleep(0) as a yield hint is also flagged --
; prefer Application.ProcessMessages or TThread.Yield if that is the intent.
;
; SCOPE. This query matches ANY bare `Sleep(` call -- it cannot see threads, and
; a tree-sitter query has no type or ancestry information to see them with. The
; scoping therefore lives in the sidecar json as `require_file_text`, which
; keeps the rule out of files where a VCL UI cannot exist at all:
;
;   "vcl."        the unit references a VCL unit
;   "{$r *.dfm}"  the unit IS a form / frame / data module, whatever style of
;                 uses clause it has (legacy code says `uses Forms`, not `Vcl.Forms`)
;
; WHY. Unscoped, the rule fired 11 times in one DUnitX unit of DataCopy's test
; project -- a headless folder-watcher test whose uses clause names no VCL unit
; and which has no message loop to block. Those findings were never true, and
; the word VCL appeared only in the message.
;
; WHAT THIS DELIBERATELY DOES NOT DO. A Sleep on a background thread inside a
; VCL unit still fires; excluding it needs to know the enclosing class descends
; from TThread, which is ancestry a query cannot see. That is a separate, larger
; change and is NOT pretended to be fixed here.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "Sleep"))
