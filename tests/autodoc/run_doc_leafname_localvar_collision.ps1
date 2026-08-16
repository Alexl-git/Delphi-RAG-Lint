<#
  run_doc_leafname_localvar_collision.ps1 -- the unresolved-name caller bucket
  must not claim refs that are really uses of a same-named LOCAL VARIABLE.

  INBOX-autodoc-caller-list-fabricates-callers-for-common-method-names. The
  bucket is gated by LeafNameIsUnambiguous, which counted only CALL TARGETS: it
  answered "is there exactly one routine with this name", when what the bucket
  needs is "could an unresolved ref carrying this name be something other than a
  call to me". A variable binder makes it ambiguous just as surely as a second
  method does, and much more often.

  Measured on the self-index before the fix: TreeSitter.TTSNodeHelper.Child is
  declared ONCE as a method, so the gate said "unambiguous", while 23 distinct
  local variables named Child exist in the same index. find-callers --resolved
  returned 0 callers, yet the generated Called from: list carried 59 entries.

  The earlier `Create` fix (many constructors sharing a name) is a different
  shape and is unaffected; this is its sibling -- ONE method colliding with MANY
  variable bindings.

  Fixture (fixtures\leafname):
    TWalker.Child   unique method name, NO resolved caller, 5 local vars named
                    Child in uLeafUse   -> must get NO Called from: list
    TWalker.Anchor  unique method name, ONE real resolved caller (DriveAnchor)
                    -> MUST still get its Called from: list

  ANCHOR IS THE POSITIVE CONTROL AND IT IS THE WHOLE POINT. Asserting only "the
  59 fabricated callers are gone" passes just as well if caller lists stopped
  being generated at all -- which is exactly what over-tightening this gate
  would do, and it would be silent. Anchor fails loudly in that case.

  Note the resolved-anchor escape at the call site is unchanged: when even one
  caller resolves, the bucket is still added and the ' ?' marker tells the
  reader which entries are weak. This suppression applies ONLY to the wholly
  unresolved case, which is the one that renders a pure guess as if verified.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\leafname')).Path

$scratch = Join-Path C:\TEMP 'draglint_leafname'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch -Force
$db = Join-Path $scratch 'leaf.sqlite'

Push-Location C:\TEMP
try {
  $idx = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'SANITY: both fixture units indexed with no errors' `
        (($idx -match 'uLeafDecl\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors') -and
         ($idx -match 'uLeafUse\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')) $idx

  # Child has no resolved caller; Anchor has exactly one.
  $rc = & $exePath query find-callers --name Child  --resolved --db $db 2>&1 | Out-String
  $ra = & $exePath query find-callers --name Anchor --resolved --db $db 2>&1 | Out-String
  Check 'SANITY: Child has NO resolved caller (the dangerous shape)' `
        ($rc -notmatch 'uLeafUse\.') $rc
  Check 'SANITY: Anchor HAS a resolved caller (DriveAnchor)' `
        ($ra -match 'DriveAnchor') $ra

  # NOT --json. The JSON form emits only a per-symbol SUMMARY (qname/file/line/
  # action/edits) and never the block text, so a "does not contain Called from"
  # assertion against it passes no matter what the engine generated. Read the
  # rendered edit instead.
  $docChild  = & $exePath document --qname 'uLeafDecl.TWalker.Child'  --db $db 2>&1 | Out-String
  $docAnchor = & $exePath document --qname 'uLeafDecl.TWalker.Anchor' --db $db 2>&1 | Out-String

  Check 'SANITY: the generator actually produced an edit for each (not a no-op)' `
        (($docChild -match 'insert after line') -and ($docAnchor -match 'insert after line')) `
        "child=$docChild anchor=$docAnchor" 

  Check 'Child gets NO "Called from:" list (5 local vars make the name ambiguous)' `
        ($docChild -notmatch 'Called from') $docChild
  Check 'POSITIVE CONTROL: Anchor STILL gets its "Called from:" list' `
        ($docAnchor -match 'Called from') $docAnchor
  Check 'POSITIVE CONTROL: and it names the real caller' `
        ($docAnchor -match 'DriveAnchor') $docAnchor
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
