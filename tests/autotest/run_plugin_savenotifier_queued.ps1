<#
  run_plugin_savenotifier_queued.ps1 -- deep review F6 (2026-10-25).

  THE DEFECT THIS PINS. SaveNotifier's tier-1 path went through the job queue
  (PLAN-lint-tree P4), but its per-file FALLBACK -- no active project, or no
  unique manifest owner -- still called SpawnIndexerFile: a DETACHED
  CreateProcessW of `index <file> --db <db> --deep`. That ignored the
  ide-release engine hold, never coalesced (Save All = N engines on one DB),
  never read an exit code, and copied the command line with StrPCopy into a
  fixed array[0..1023] of WideChar (stack overflow inside the IDE on a long
  path).

  WHY A SOURCE GUARD. The wiring is an OTA AfterSave callback; the job SHAPE is
  pinned headless in tests\IndexJobTests.dpr (cases 7a-7k). What only the
  source can show is that the fallback reaches the queue and no detached spawn
  is left in the unit. A bypass is invisible at runtime.

  Runs from anywhere, pwsh 7.
#>
[CmdletBinding()]
param([string]$Unit = "$PSScriptRoot\..\..\src\delphi-plugin\DragLint.Plugin.SaveNotifier.pas")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

# The body from AHeader up to the next `end; // <tag>`; '' when absent so every
# body assertion fails loudly instead of passing on an empty string.
function Get-Body([string]$src, [string]$header, [string]$tag) {
  $start = $src.IndexOf($header)
  if ($start -lt 0) { return '' }
  $end = $src.IndexOf("end; // $tag", $start)
  if ($end -lt 0) { return '' }
  return $src.Substring($start, $end - $start)
}

# Returns the list of check results for one copy of the source, so the positive
# control can run the SAME checks over a broken copy.
function Test-Source([string]$text) {
  $after = Get-Body $text 'procedure TDragLintSaveNotifier.AfterSave;' 'procedure'
  $queue = Get-Body $text 'procedure QueueFileReindexJob(' 'procedure'
  [ordered]@{
    'AfterSave exists (guard anchored to something real)' = ($after -ne '')
    'QueueFileReindexJob exists'                         = ($queue -ne '')
    'no CreateProcessW anywhere in the unit'             = (-not $text.Contains('CreateProcessW'))
    'no DETACHED_PROCESS anywhere in the unit'           = (-not $text.Contains('DETACHED_PROCESS'))
    'no StrPCopy anywhere in the unit'                   = (-not $text.Contains('StrPCopy'))
    'no fixed WideChar command buffer'                   = (-not ($text -match 'array\s*\[\s*0\s*\.\.\s*\d+\s*\]\s+of\s+WideChar'))
    'the old name SpawnIndexerFile is gone'              = (-not $text.Contains('SpawnIndexerFile'))
    'the AfterSave fallback calls QueueFileReindexJob'   = ($after -ne '' -and $after.Contains('QueueFileReindexJob('))
    'the fallback builds the shared file job'            = ($queue -ne '' -and $queue.Contains('BuildFileIndexJob('))
    'the fallback enqueues onto the job queue'           = ($queue -ne '' -and $queue.Contains('JobQueue.Enqueue('))
    'the fallback reads the exit code in OnDone'         = ($queue -ne '' -and $queue -match 'OnDone\s*:=' -and $queue.Contains('AExit'))
  }
}

Write-Host ''
Write-Host '=== the SaveNotifier per-file fallback goes through the job queue ===' -ForegroundColor Cyan

$path = (Resolve-Path $Unit).Path
$text = [IO.File]::ReadAllText($path)
$r = Test-Source $text
foreach ($k in $r.Keys) { Check $k $r[$k] }

# --- POSITIVE CONTROL -------------------------------------------------------
# A copy with the old detached spawn planted back must FAIL the bypass checks,
# and one with the enqueue removed must FAIL the queue check.
$planted = $text.Replace('JobQueue.Enqueue(Job);',
  "StrPCopy(CmdLineBuf, CmdLine); CreateProcessW(nil, CmdLineBuf, nil, nil, False, CREATE_NO_WINDOW or DETACHED_PROCESS, nil, nil, SI, PI);")
$planted = $planted.Replace('QueueFileReindexJob(ExePath', 'SpawnIndexerFile(ExePath')
$p = Test-Source $planted
Check 'POSITIVE CONTROL: the plant actually changed the copy' ($planted -ne $text)
Check 'POSITIVE CONTROL: a planted CreateProcessW fails its check' (-not $p['no CreateProcessW anywhere in the unit'])
Check 'POSITIVE CONTROL: a planted StrPCopy fails its check' (-not $p['no StrPCopy anywhere in the unit'])
Check 'POSITIVE CONTROL: a planted SpawnIndexerFile call fails its check' (-not $p['the old name SpawnIndexerFile is gone'])
Check 'POSITIVE CONTROL: removing the enqueue fails the queue check' (-not $p['the fallback enqueues onto the job queue'])
$buf = Test-Source ($text + "`r`nvar X: array[0..1023] of WideChar;")
Check 'POSITIVE CONTROL: a planted fixed WideChar buffer fails its check' (-not $buf['no fixed WideChar command buffer'])

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
