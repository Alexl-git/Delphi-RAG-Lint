<#
  run_doc_xml_escape.ps1 -- managed-block content MUST be XML-escaped.

  The facts miner emits mined content (deprecated messages, caller/callee names,
  Overrides/Implements/Raises, seealso crefs) into the fenced <remarks> managed
  block. Any raw '<', '>', '&' there makes the DocInsight XML ill-formed
  ("Bad XML documentation comment"); a raw '</remarks>' additionally breaks the
  regex-based re-parse so the managed fence fails to strip on a second run.

  Fixture docesc\esc.pas: OldEsc is `deprecated 'use A<B> & </remarks> instead'`,
  called by UseIt (so both get a managed block). Sequence:
    index -> document --unit --apply (run 1) -> RE-INDEX -> document --unit --apply (run 2)
  Asserts:
    * the managed block carries the ESCAPED message: use A&lt;B&gt; &amp; &lt;/remarks&gt;
    * the raw, unescaped message text is NOT present anywhere in the file
    * every generated ///-doc comment is WELL-FORMED XML (parses under [xml])
    * IDEMPOTENT: file bytes after run 2 == after run 1 (the literal </remarks>
      in the message is the case that regresses without escaping)

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docesc\esc.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docesc'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'esc.pas'
$db     = Join-Path $scratch 'docesc.sqlite'
Copy-Item $fixture $target -Force

# Validate that every ///-doc block in the file is well-formed XML. Strips the
# /// prefix from each doc line, wraps consecutive doc runs in a <doc> root, and
# tries to parse. A raw <, >, & or a stray close tag makes [xml] throw.
function DocXmlWellFormed([string]$path) {
  $lines = [IO.File]::ReadAllLines($path)
  $sb = New-Object System.Text.StringBuilder
  $inBlock = $false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*///') {
      $stripped = $ln -replace '^\s*///\s?',''
      if (-not $inBlock) { [void]$sb.Append('<doc>'); $inBlock = $true }
      [void]$sb.AppendLine($stripped)
    } else {
      if ($inBlock) { [void]$sb.AppendLine('</doc>'); $inBlock = $false }
    }
  }
  if ($inBlock) { [void]$sb.AppendLine('</doc>') }
  $xmlText = '<root>' + $sb.ToString() + '</root>'
  try { [void][xml]$xmlText; return $true } catch { Write-Host "  XML parse error: $($_.Exception.Message)" -ForegroundColor DarkYellow; return $false }
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- run 1: apply ---
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  Check 'apply #1: exit 0' ($LASTEXITCODE -eq 0)

  $src = [IO.File]::ReadAllText($target)
  Check 'has managed facts block (AUTO_BEGIN)' ($src -match '<!-- drag-lint:auto BEGIN -->')

  # escaped message present in the generated doc; raw message absent from the
  # generated doc lines (it legitimately remains in the source `deprecated '...'`
  # directive, so scope the raw check to ///-doc lines only).
  $docLines = (([IO.File]::ReadAllLines($target) | Where-Object { $_ -match '^\s*///' }) -join "`n")
  Check 'message is XML-escaped in managed block' ($docLines -match 'Deprecated: use A&lt;B&gt; &amp; &lt;/remarks&gt; instead')
  Check 'raw unescaped message NOT in generated doc lines' (-not ($docLines -match 'use A<B> & </remarks> instead'))

  # non-volatile parts preserved: hand-written summary + remarks prose survive
  Check 'hand-written summary preserved'      ($src -match 'Legacy entry point kept for callers not yet migrated')
  Check 'hand-written remarks prose preserved' ($src -match 'prefer NewWay for A &lt;-&gt; B mapping')

  # every generated doc comment is well-formed XML
  Check 'generated ///-doc comments are well-formed XML' (DocXmlWellFormed $target)

  $bytes1 = [IO.File]::ReadAllBytes($target)

  # --- CRITICAL re-index so the store sees post-insert line numbers ---
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- run 2: apply again; must be a byte-identical no-op ---
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $bytes2 = [IO.File]::ReadAllBytes($target)

  Check 'IDEMPOTENT: file bytes identical after run 2 vs run 1' `
    ([System.Linq.Enumerable]::SequenceEqual([byte[]]$bytes1,[byte[]]$bytes2))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
