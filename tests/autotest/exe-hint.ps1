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
  return ''
}
