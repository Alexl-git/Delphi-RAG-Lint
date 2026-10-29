; LoadLibrary with a bare DLL name searches the application and current directories
; before System32 -- the classic DLL-hijack shape (CWE-427). A rooted path (contains \ or /)
; or a KnownDLLs system library is safe. dbghelp.dll is deliberately NOT in the allow list.
((exprCall
   entity: (identifier) @fn
   args: (exprArgs . (literalString) @lib)) @warn
  (#any-of? @fn "LoadLibrary" "LoadLibraryA" "LoadLibraryW" "LoadLibraryEx" "LoadLibraryExA" "LoadLibraryExW" "SafeLoadLibrary")
  (#not-match? @lib "[\\\\/]")
  (#not-match? @lib "(?i)^'(kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|comctl32|comdlg32|ntdll|shlwapi|psapi|version|crypt32|wininet|winhttp|setupapi)(\\.dll)?'$"))
