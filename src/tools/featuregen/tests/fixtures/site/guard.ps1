# fixture of tests\autotest\run_docs_sync_guard.ps1
$Other = 1
$UndocumentedOnPurpose = [ordered]@{
  'selftest'            = 'umbrella self-test; not a surface verb.'
  'dump-thing'          = 'diagnostic dump.'
}
$After = 2