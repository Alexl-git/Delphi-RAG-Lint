; A folder name WITHOUT trailing path delimiter joined to a file or folder name with +:
;   Datei := ExtractFileDir(P) + 'export.csv'          (result: 'C:\Tempexport.csv')
; Folder sources that never end in a delimiter: ExtractFileDir, ExcludeTrailingPathDelimiter,
; ExcludeTrailingBackslash and the TPath.Get...Path folders (documents, home, library, cache, public,
; pictures, downloads). A literal that starts with a delimiter is fine and not reported.
; Two shapes: (1) the call itself is the left operand; (2) a local that was assigned such a folder
; earlier in the same routine and is then used as left operand with a literal (the finding sits on
; the routine). Shape (2) is skipped when the routine also uses IncludeTrailing... anywhere.
((exprBinary
   lhs: (exprCall entity: (_) @fn)
   operator: (kAdd)
   rhs: (literalString) @lit) @warn
  (#match? @fn "(?i)^((System[.]SysUtils[.])?ExtractFileDir|(System[.]SysUtils[.])?ExcludeTrailing(PathDelimiter|Backslash)|(System[.]IOUtils[.])?TPath[.]Get(Documents|Home|Library|Cache|Public|Pictures|Downloads|SharedDocuments|Music|Movies|Camera)Path)$")
  (#match? @lit "^'[^\\\\/']"))
((defProc
   body: (_) @body) @warn
  (#match? @body "(?is)^(?!.*\\bIncludeTrailing(PathDelimiter|Backslash)\\b).*\\b(\\w+)\\s*:=\\s*(ExtractFileDir|ExcludeTrailing(PathDelimiter|Backslash)|(TPath[.])?Get(Documents|Home|Library|Cache|Public|Pictures|Downloads|SharedDocuments)Path)\\b[^;]*;.*?\\b\\2\\s*\\+\\s*'[^\\\\/']"))
