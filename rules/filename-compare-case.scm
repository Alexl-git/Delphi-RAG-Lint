; File and path names compared with = or <>. Windows file names are case-insensitive and a path may
; differ by delimiter or relative parts, so `ExtractFileName(F) = 'Config.ini'` misses 'CONFIG.INI'.
; One operand is the result of a file-name routine (ExtractFileName/-Path/-Dir/-Ext/-Drive,
; ExpandFileName, TPath.GetFileName/GetDirectoryName/GetExtension/GetFullPath ...). Comparison with
; the empty string is a presence test, not a name comparison, and is not reported.
((exprBinary
   lhs: (exprCall entity: (_) @fn)
   operator: [(kEq) (kNeq)]
   rhs: (_) @other) @warn
  (#match? @fn "(?i)^((System[.]SysUtils[.])?(ExtractFileName|ExtractFilePath|ExtractFileDir|ExtractFileExt|ExtractFileDrive|ExpandFileName|ExpandUNCFileName)|(System[.]IOUtils[.])?TPath[.](GetFileName|GetFileNameWithoutExtension|GetDirectoryName|GetExtension|GetFullPath))$")
  (#not-match? @other "^''$"))
((exprBinary
   lhs: (_) @other2
   operator: [(kEq) (kNeq)]
   rhs: (exprCall entity: (_) @fn2)) @warn
  (#match? @fn2 "(?i)^((System[.]SysUtils[.])?(ExtractFileName|ExtractFilePath|ExtractFileDir|ExtractFileExt|ExtractFileDrive|ExpandFileName|ExpandUNCFileName)|(System[.]IOUtils[.])?TPath[.](GetFileName|GetFileNameWithoutExtension|GetDirectoryName|GetExtension|GetFullPath))$")
  (#not-match? @other2 "^''$"))
