; Calls to unbounded C-style PChar string routines -- no length protection.
; Use System.AnsiStrings equivalents or the string/TStringHelper APIs instead.
((exprCall entity: (identifier) @fn) @warn
 (#any-of? @fn "StrCopy" "StrCat" "StrPCopy" "StrMove" "StrPos" "StrLen"))
