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
; O2 (1.45): a Sleep inside a method of a class the index PROVES descends from TThread
; (type_ancestors, project index) is not on the UI thread and stays silent.
; #not-enclosing-class-descends? passes whenever the proof is missing -- no index, a class the
; index cannot follow to TThread, a plain routine -- so those runs fire exactly as before.
; Still not covered: an anonymous thread body inside a UI method.
((exprCall entity: (identifier) @fn) @warn
 (#eq? @fn "Sleep")
 (#not-enclosing-class-descends? @warn "TThread"))
