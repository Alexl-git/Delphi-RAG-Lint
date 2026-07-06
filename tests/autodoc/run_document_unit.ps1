<#
  run_document_unit.ps1 -- whole-unit AutoDocument batch (`document --unit`).

  Uses fixtures\docunit\twopublics.pas: a unit with two PUBLIC (interface-
  section) methods -- TThing.Add (params + returns + a caller) and TThing.Reset
  (calls Add) -- plus a PRIVATE FLast field that is NOT public surface.

  Asserts the facts-only default (Stubs=False):
    * `document --unit <file> --apply` documents the two public METHODS that have
      index-grounded facts (Add, Reset -> a managed AUTO_BEGIN block each).
    * The public class TThing has NO facts, so its all-TODO comment is SKIPPED
      (facts-only): exactly two managed blocks, none above 'TThing = class'.
    * The private FLast field gets NO comment (not public surface).
    * IDEMPOTENCY: a second --apply leaves the file BYTE-IDENTICAL.
    * `--json` reports declCount = 3 (TThing + Add + Reset) and docCount = 2.

  (A kept, facts-backed decl still carries TODO summary/param PLACEHOLDERS -- the
  documenter never fabricates prose. Facts-only drops decls that are ONLY TODO
  with no facts, not the TODO placeholders inside a facts-backed comment.)

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docunit\twopublics.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docunit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'twopublics.pas'
$db     = Join-Path $scratch 'docunit.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- first --apply: both public methods documented ---
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $ec1 = $LASTEXITCODE
  Check 'apply #1: exit 0' ($ec1 -eq 0)

  $src = [IO.File]::ReadAllText($target)
  Check 'file has a triple-slash comment' ($src -match '///')

  # Facts-only default: a decl is documented only when it has a managed facts
  # block (AUTO_BEGIN). Both public METHODS carry facts (Add: called-from + calls;
  # Reset: calls Add) -> both get a managed block. The class type TThing has NO
  # facts (no params/returns/callers/callees) so it is correctly SKIPPED even
  # though it is a public interface-section decl.
  Check 'has managed facts block (AUTO_BEGIN)' ($src -match '<!-- drag-lint:auto BEGIN -->')
  $beginCount = ([regex]::Matches($src, '<!-- drag-lint:auto BEGIN -->')).Count
  Check 'exactly two managed blocks (both methods, not the class)' ($beginCount -eq 2)

  # The doc block above Add carries a Called-from/Calls facts line; above Reset a
  # Calls line -> confirms both METHODS (not the class) were the ones documented.
  Check 'Add has a facts line above its decl' ($src -match '(?s)Called from:.*?function Add\(')
  Check 'Reset has a Calls facts line above its decl' ($src -match '(?s)Calls:[^\r\n]*Add.*?procedure Reset;')

  # The class-type comment (which would be a pure all-TODO create) is NOT written:
  # there must be NO /// comment on the line directly above 'TThing = class'.
  $lines = [IO.File]::ReadAllLines($target)
  $clsIdx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'TThing\s*=\s*class') { $clsIdx = $i; break } }
  Check 'TThing class decl found' ($clsIdx -ge 0)
  Check 'facts-only: class TThing (no facts) NOT documented' ($clsIdx -ge 1 -and ($lines[$clsIdx-1] -notmatch '///'))

  # Private FLast field must NOT gain a comment (no /// on the line above it).
  $flastIdx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'FLast:\s*Integer') { $flastIdx = $i; break } }
  Check 'FLast field found' ($flastIdx -ge 0)
  Check 'private FLast NOT documented' ($flastIdx -ge 1 -and ($lines[$flastIdx-1] -notmatch '///'))

  # --- idempotency: second --apply leaves file byte-identical ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical on 2nd run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))

  # --- --json reports declCount=2, docCount=2 (fresh scratch, dry-run) ---
  $scratch2 = Join-Path C:\TEMP 'draglint_docunit_json'
  if (Test-Path $scratch2) { Remove-Item $scratch2 -Recurse -Force }
  New-Item -ItemType Directory -Path $scratch2 | Out-Null
  $target2 = Join-Path $scratch2 'twopublics.pas'
  $db2     = Join-Path $scratch2 'docunit.sqlite'
  Copy-Item $fixture $target2 -Force
  & $exePath index $scratch2 --db $db2 2>$null | Out-Null
  $rj = & $exePath document --unit $target2 --db $db2 --json 2>$null | Out-String
  $ecj = $LASTEXITCODE
  $oj = $null; try { $oj = ($rj | ConvertFrom-Json) } catch { $oj = $null }
  # declCount = 3 public interface-section documentable decls (TThing, Add, Reset);
  # docCount = 2 (Add + Reset have facts; the class TThing has none -> facts-only skip).
  Check 'json: exit 0'          ($ecj -eq 0)
  Check 'json: declCount = 3'   ($null -ne $oj -and [int]$oj.declCount -eq 3)
  Check 'json: docCount = 2'    ($null -ne $oj -and [int]$oj.docCount -eq 2)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
