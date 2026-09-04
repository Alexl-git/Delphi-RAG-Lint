<#
  run_lsp_publish_respects_defaults.ps1 -- the LSP's publishDiagnostics must
  honour the SAME default-disabled rule set the CLI honours.

  THE DEFECT THIS PINS (FP3c):
    DRagLint.LSP.Completion.BuildDiagnostics filtered its findings with
    `Cfg.ShouldKeep(F.RuleId, False)` at both call sites. That second argument is
    "is this rule off by default", and a literal False says "nothing is off by
    default" -- so every rule the CLI hides was published to the editor anyway.

    That surface is not a corner: the live runner's 8 s budget is missed on a
    repo this size (11.9 s per project member, measured), so the LSP overlay IS
    what the IDE gutter shows. Measured on drag-lint's own source, the two
    largest default-off rules alone put 461 string-equality-comparison + 888
    nil-comparison = 1,349 spurious marks in front of a reader whose only
    defence is to stop reading marks. A linter nobody reads is the failure this
    repo's lint-clean standard exists to prevent.

  WHY THE CONTROLS ARE HERE:
    "nil-comparison is absent from the published set" is satisfied by publishing
    NOTHING, and by DELETING the rule. Neither is the fix. So:
      * an ordinary default-ON finding in the SAME file must still be published;
      * `lint --rule nil-comparison` must still report it on the CLI;
      * a drag-lint-lint.json opting the rule back in must make the LSP publish
        it again -- which proves the filter runs through ShouldKeep's
        default-disabled path rather than removing the rule from the surface.

    Every check prints what it actually matched, because two guards in session 64
    passed/failed on something other than what they claimed to be looking at.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-publish-defaults"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# ---------- fixture ----------
# Two findings, chosen so the assertion and its control cannot be satisfied by
# the same behaviour:
#   line 15  `if AObj = nil then`  -> nil-comparison   (OFF by default)
#   line 19  an empty except block -> empty-except     (ON by default)
if (Test-Path $WorkDir) { Get-ChildItem $WorkDir -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$DefDir   = Join-Path $WorkDir 'default'
$OptInDir = Join-Path $WorkDir 'optin'
New-Item -ItemType Directory -Force $DefDir   | Out-Null
New-Item -ItemType Directory -Force $OptInDir | Out-Null

$src = @(
  'unit FixtureNilCmp;'
  ''
  'interface'
  ''
  'type'
  '  TFoo = class'
  '  public'
  '    procedure Go(const AObj: TObject);'
  '  end;'
  ''
  'implementation'
  ''
  'procedure TFoo.Go(const AObj: TObject);'
  'begin'
  '  if AObj = nil then'
  '    Exit;'
  '  try'
  '    AObj.ToString;'
  '  except'
  '  end;'
  'end;'
  ''
  'end.'
) -join "`r`n"
$DefFix   = Join-Path $DefDir   'FixtureNilCmp.pas'
$OptInFix = Join-Path $OptInDir 'FixtureNilCmp.pas'
[System.IO.File]::WriteAllText($DefFix  , $src + "`r`n", [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($OptInFix, $src + "`r`n", [System.Text.Encoding]::ASCII)
# The opt-in half only: config discovery walks UP from the file, so this reaches
# the optin copy and not the default one.
[System.IO.File]::WriteAllText((Join-Path $OptInDir 'drag-lint-lint.json'),
  '{ "enabled": ["nil-comparison"] }' + "`r`n", [System.Text.Encoding]::ASCII)

# ---------- drive the server headlessly ----------
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function PublishedCodes([string]$PasFile, [string]$Tag) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($PasFile)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
    (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  )
  $dir = Split-Path $PasFile
  $in  = Join-Path $dir 'lsp-in.txt'
  $so  = Join-Path $dir 'lsp-out.txt'
  $se  = Join-Path $dir 'lsp-err.txt'
  [System.IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  $p = Start-Process $Exe -ArgumentList 'lsp' -WorkingDirectory $dir `
         -RedirectStandardInput $in -RedirectStandardOutput $so -RedirectStandardError $se `
         -NoNewWindow -Wait -PassThru
  $out = ''
  if (Test-Path $so) { $out = [System.IO.File]::ReadAllText($so) }
  $codes = @([regex]::Matches($out, '"code":"([a-z0-9\-]+)"') | ForEach-Object { $_.Groups[1].Value })
  Write-Host ("  ({0}) exit={1}, published: {2}" -f $Tag, $p.ExitCode, $(if ($codes.Count) { ($codes | Sort-Object -Unique) -join ', ' } else { '<none>' })) -ForegroundColor DarkGray
  return $codes
}

Write-Host 'LSP publishDiagnostics vs the default-disabled set' -ForegroundColor Cyan
$def = PublishedCodes $DefFix 'defaults'

# The whole point. nil-comparison is OFF by default on every CLI verb.
Check 'nil-comparison is NOT published by default' `
  ($def -notcontains 'nil-comparison') `
  ("published=[" + (($def | Sort-Object -Unique) -join ',') + "]")

# CONTROL 1 -- "publish nothing" must not satisfy the check above. The fixture's
# other finding is default-ON and sits four lines away in the same routine.
Check 'CONTROL: the default-ON finding in the same file IS still published' `
  ($def -contains 'empty-except') `
  ("looked for empty-except in [" + (($def | Sort-Object -Unique) -join ',') + "]")

# ---------- CLI parity, both directions ----------
Write-Host ''
Write-Host 'CLI parity -- the LSP must match what the CLI already does' -ForegroundColor Cyan
$cliDefault = (& $Exe lint $DefFix 2>&1) -join "`n"
Check 'CLI `lint` also hides nil-comparison by default (this is the parity being enforced)' `
  ($cliDefault -notmatch 'nil-comparison') `
  ($(($cliDefault -split "`r?`n" | Where-Object { $_ -match ':\s+\[' }) -join ' | '))

# CONTROL 2 -- the rule must still EXIST and still be reachable. A fix that
# deleted the rule, or dropped it from the .scm corpus, would pass every check
# above and fail this one.
$cliOptIn = (& $Exe lint $DefFix --rule nil-comparison 2>&1) -join "`n"
Check 'CONTROL: `--rule nil-comparison` still reports it on the CLI' `
  ($cliOptIn -match 'nil-comparison') `
  ($(($cliOptIn -split "`r?`n" | Where-Object { $_ -match 'nil-comparison' } | Select-Object -First 1)))

# CONTROL 3 -- the strongest one. Opting the rule back in via config must make
# the LSP publish it again. That can only happen if the suppression runs through
# ShouldKeep's default-disabled argument, which "enabled" overrides -- a
# hard-coded skip of the rule id would stay silent here.
Write-Host ''
Write-Host 'Opt-in -- a project config must be able to turn it back on' -ForegroundColor Cyan
$opt = PublishedCodes $OptInFix 'optin'
Check 'CONTROL: drag-lint-lint.json "enabled":["nil-comparison"] republishes it' `
  ($opt -contains 'nil-comparison') `
  ("published=[" + (($opt | Sort-Object -Unique) -join ',') + "]")
Check 'CONTROL: the opt-in run still carries the default-ON finding too' `
  ($opt -contains 'empty-except') `
  ("published=[" + (($opt | Sort-Object -Unique) -join ',') + "]")

# ---------- the one list, not three ----------
# The fix is only durable if there is a single definition to add the next
# default-off rule to. If someone re-introduces a hand-written copy in the CLI,
# the LSP silently stops matching it again -- exactly how this defect arose.
Write-Host ''
Write-Host 'STATIC: one definition of the default-off set' -ForegroundColor Cyan
$catalog = "$PSScriptRoot\..\..\src\lint\DRagLint.Lint.RuleCatalog.pas"
$cli     = "$PSScriptRoot\..\..\src\cli\DRagLint.CLI.pas"
$lsp     = "$PSScriptRoot\..\..\src\lsp\DRagLint.LSP.Completion.pas"
$catTxt  = if (Test-Path $catalog) { [System.IO.File]::ReadAllText($catalog) } else { '' }
$cliTxt  = if (Test-Path $cli)     { [System.IO.File]::ReadAllText($cli)     } else { '' }
$lspTxt  = if (Test-Path $lsp)     { [System.IO.File]::ReadAllText($lsp)     } else { '' }

Check 'BUILTIN_RULES_OFF_BY_DEFAULT is declared in the rule catalog' `
  ($catTxt -match 'BUILTIN_RULES_OFF_BY_DEFAULT\s*:\s*TArray<string>\s*=') `
  "src\lint\DRagLint.Lint.RuleCatalog.pas"
Check 'the LSP consumes it' ($lspTxt -match 'BUILTIN_RULES_OFF_BY_DEFAULT') `
  ($(($lspTxt -split "`r?`n" | Where-Object { $_ -match 'BUILTIN_RULES_OFF_BY_DEFAULT' } | Select-Object -First 1).Trim()))
Check 'the CLI consumes it' ($cliTxt -match 'BUILTIN_RULES_OFF_BY_DEFAULT') `
  ($(($cliTxt -split "`r?`n" | Where-Object { $_ -match 'BUILTIN_RULES_OFF_BY_DEFAULT' } | Select-Object -First 1).Trim()))
# No literal id may be appended to a default-disabled set. Every surface has to
# loop over one of the two shared constants, or the next rule that ships OFF gets
# added to some verbs and not others -- which is how `lint`, `lint-all`,
# `lint-project` and the LSP came to answer the same question four ways.
#
# The check is written against the ASSIGNMENT, not against the rule ids: a bare
# 'nil-comparison' elsewhere in the CLI is legitimate (--rule comparisons, the
# autofix tables, the type-aware supersede logic), and a guard that flagged those
# would be failing against correct code.
$literalAppends = @()
foreach ($ln in ($cliTxt -split "`r?`n")) {
  if ($ln -match "DefDisabled\s*:=\s*DefDisabled\s*\+\s*\[\s*'") { $literalAppends += $ln.Trim() }
}
Check 'no literal rule id is appended to DefDisabled anywhere in the CLI' `
  ($literalAppends.Count -eq 0) `
  ($(if ($literalAppends.Count) { "`n        " + ($literalAppends -join "`n        ") } else { 'all appends go through a shared constant' }))

# Guard the guard: the scan above is only meaningful if the loops it demands are
# actually present. Otherwise deleting every append satisfies it.
$loopCount = @([regex]::Matches($cliTxt, 'for var \w+: string in (BUILTIN|PROJECT)_RULES_OFF_BY_DEFAULT')).Count
Check 'the CLI verbs loop over the shared constants instead (scan is not vacuous)' `
  ($loopCount -ge 3) "loops=$loopCount -- lint and lint-project contribute two each; lint-all concatenates"
# The CATALOGUE must agree with the engine. `rules --json` is what a user reads
# to find out what runs, and what the IDE Options page ticks its checkboxes from;
# an .scm sidecar that simply forgets "enabled": false used to advertise a rule
# as ON that every lint verb hides. nil-comparison was exactly that.
Write-Host ''
Write-Host 'CATALOGUE: `rules --json` agrees with the engine' -ForegroundColor Cyan
$ids = @([regex]::Match($catTxt, "BUILTIN_RULES_OFF_BY_DEFAULT\s*:\s*TArray<string>\s*=\s*\[(?<b>[^\]]*)\]").Groups['b'].Value |
         ForEach-Object { [regex]::Matches($_, "'([a-z0-9\-]+)'") } | ForEach-Object { $_.Groups[1].Value })
Check 'the constant parsed out of the catalog source is non-empty' ($ids.Count -ge 10) "ids=$($ids.Count)"
$catalogJson = (& $Exe rules --json 2>$null) -join "`n" | ConvertFrom-Json
$rows = if ($catalogJson.rules) { $catalogJson.rules } else { $catalogJson }
$onAnyway = @($rows | Where-Object { $ids -contains $_.id -and $_.default_enabled } | ForEach-Object { "$($_.id)($($_.source))" })
$seen     = @($rows | Where-Object { $ids -contains $_.id } | ForEach-Object { $_.id })
Check 'every id in the constant is present in the catalogue (not a typo)' `
  ($seen.Count -eq $ids.Count) ("matched " + $seen.Count + " of " + $ids.Count + "; missing=[" + (($ids | Where-Object { $seen -notcontains $_ }) -join ',') + "]")
Check 'none of them is advertised as default_enabled=true' ($onAnyway.Count -eq 0) `
  ("advertised ON: [" + ($onAnyway -join ',') + "]")

Check 'the LSP no longer passes a literal False for default-disabled' `
  ($lspTxt -notmatch 'ShouldKeep\(\s*F\.RuleId\s*,\s*False\s*\)') `
  ($(($lspTxt -split "`r?`n" | Where-Object { $_ -match 'ShouldKeep\(' } | ForEach-Object { $_.Trim() }) -join ' | '))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
