# exe-hint.ps1 -- the one definition of Get-ExeStartFailureHint (lane CLIFIX C2). Dot-sourced by
# g8-common.ps1 and by every guard whose "index produced no DB" branch must say WHY the index
# process never ran. Not a guard itself.
function Get-ExeStartFailureHint([int]$Code) {
  # 0xC000007B (STATUS_INVALID_IMAGE_FORMAT, -1073741701): the loader refused the exe -- missing or
  # wrong-bitness companion DLLs beside it. Reporting that as "index produced no DB" sends the reader
  # hunting in the indexer for a process that never started. '' for any other code.
  if ($Code -eq -1073741701) {
    return 'exe failed to start (0xC000007B): missing or wrong-bitness companion DLLs (tree-sitter*.dll, sqlite3.dll) beside the exe?'
  }
  # 0xC0000135 (STATUS_DLL_NOT_FOUND, -1073741515): the same cause when the loader finds no companion DLL at
  # all on its search path (seen 2026-11-08, wave 147: the machine no longer supplies a wrong-bitness copy).
  if ($Code -eq -1073741515) {
    return 'exe failed to start (0xC0000135): missing companion DLLs (tree-sitter*.dll, sqlite3.dll) beside the exe?'
  }
  return ''
}
