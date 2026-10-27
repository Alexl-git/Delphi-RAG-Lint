; The result of these RTL / Win32 routines IS the error report: DeleteFile and friends return False on
; failure, ReleaseMutex / SetEvent / WriteFile
; signal failure through the return value, TryStrToX leaves its out-parameter undefined on False,
; Supports reports whether the interface exists. A bare statement throws that answer away.
; Deliberately NOT listed: CloseHandle, FreeLibrary, RegCloseKey, VirtualFree, UnmapViewOfFile -- release calls in
; cleanup paths whose failure nobody can act on (123 of 198 first-measure hits were bare CloseHandle).
; Complements function-result-ignored (same-unit functions), discarded-effect-free-result (store-proven
; PURE callees only - these routines have effects, so there is no double report) and
; stream-read-result-ignored (TStream.Read/Write). Only an unqualified call is judged, so a user
; method that happens to share a name (Self.DeleteFile) stays silent.
((statement
  (exprCall
    entity: (identifier) @fn) @warn)
 (#any-of? @fn "DeleteFile" "RenameFile" "RemoveDir" "CreateDir" "ForceDirectories" "SetCurrentDir" "WriteFile" "ReadFile" "ReleaseMutex" "SetEvent" "ResetEvent" "TryStrToInt" "TryStrToFloat" "TryStrToDate" "TryStrToDateTime" "TryStrToInt64" "Supports"))
