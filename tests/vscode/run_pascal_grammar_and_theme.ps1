<#
  run_pascal_grammar_and_theme.ps1 -- the Pascal TextMate grammar, the generated
  RAD Studio theme, and the colour converter that produces it.

  WHY THIS EXISTS

    Nothing coloured Pascal in VS Code until 2026-09-01: the extension
    contributed a language id but no `grammars`, VS Code ships no Pascal grammar
    among its 97 built-ins, and our LSP has no semanticTokens. The `begin`/`end`
    colour the owner could see was bracket-pair colourization reading the pairs
    in language-configuration.json -- a bracket feature, not highlighting.

    The theme is GENERATED from HKCU\Software\Embarcadero\BDS\<ver>\Editor\
    Highlight so "exactly like the IDE" is literal. Three of the four things
    that can go wrong there are SILENT, which is what this guard is for.

  THE ASSERTION THAT MATTERS MOST -- BYTE ORDER

    $00BBGGRR is a Delphi TColor: the bytes are BGR, NOT RGB. $00FFAA7F is
    #7FAAFF (light blue), not #FFAA7F (salmon). Getting it backwards does not
    look like a bug -- it produces blue keywords and salmon strings, i.e. a
    palette that looks MORE conventional than the correct one (it is very close
    to Dark+), so it would ship and stay. Check 1 pins the conversion with a
    literal expectation so an "obvious tidy-up" of the swap fails here.

    The ordering was verified three ways before it was written: the same
    registry field also stores clWhite/clRed/clLime, so it is ColorToString
    output of a TColor; System.UITypes.pas on the build box has Red = $0000FF
    and Blue = $FF0000; and `Error line`, `Illegal Char` and `Diff deletion` all
    hold $005870E3, which is red-orange under BGR and indigo under RGB.

  THE OTHER SILENT ONES

    * The value name is `Foreground Color New`. The old `Foreground Color` names
      still exist on the keys and read back EMPTY, which yields a theme with no
      colours -- presenting as "the theme did not load".
    * `Default Foreground`/`Default Background` are booleans that OVERRIDE the
      stored colour.
    * Scopes must end in `.pascal`. The "Apply RAD Studio Colours" command writes
      editor.tokenColorCustomizations GLOBALLY, and that suffix is the only thing
      stopping those rules recolouring every other language the user opens.

  POSITIVE CONTROL
    -Dir is a parameter so this can be pointed at a mutated COPY of the
    extension. That is how each check was proven capable of failing rather than
    assumed to be; see the commit message for the four mutations used.

  This is a STATIC check plus direct calls into lib/radcolors.js under node.
  It does not launch VS Code and does not tokenize -- there is no TextMate
  engine here, and adding vscode-textmate would mean a build step the extension
  deliberately avoids. Where tokenization would be needed (does {$IFDEF} beat
  the brace-comment rule) it asserts the STRUCTURAL property that decides it:
  rule order plus the negative lookahead.
#>
[CmdletBinding()]
param(
  [string]$Dir = "$PSScriptRoot\..\..\editors\vscode\drag-lint"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$grammarPath = Join-Path $Dir 'syntaxes\pascal.tmLanguage.json'
$themePath   = Join-Path $Dir 'themes\delphi-ide.color-theme.json'
$libPath     = Join-Path $Dir 'lib\radcolors.js'
$pkgPath     = Join-Path $Dir 'package.json'
foreach ($p in @($grammarPath, $themePath, $libPath, $pkgPath)) {
  if (-not (Test-Path $p)) { Write-Host "FATAL: not found: $p" -ForegroundColor Red; exit 2 }
}

$grammarRaw = Get-Content $grammarPath -Raw
$grammar    = $grammarRaw | ConvertFrom-Json
$theme      = Get-Content $themePath -Raw | ConvertFrom-Json
$pkg        = Get-Content $pkgPath -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
Write-Host 'CHECK 1 -- TColor conversion is BGR, and the traps are honoured' -ForegroundColor Cyan

$probe = Join-Path ([IO.Path]::GetTempPath()) ("draglint-radcolors-probe-" + [Guid]::NewGuid().ToString('N') + '.js')
$probeSrc = @'
const c = require(process.argv[2]);
const out = {
  bgr:      c.delphiColorToHex('$00FFAA7F'),
  named:    c.delphiColorToHex('clRed'),
  namedLim: c.delphiColorToHex('clLime'),
  system:   c.delphiColorToHex('$FF000005'),
  empty:    c.delphiColorToHex(''),
  // Trap 3: the Default flag wins over a perfectly good stored colour.
  defaults: c.elementFromValues({
    'Foreground Color New': '$00FFAA7F',
    'Default Foreground': 'True',
    'Background Color New': '$00322F2D',
    'Default Background': 'False',
    'Italic': 'True'
  }),
  // Trap 1: the OLD value name must not be read. An element carrying only the
  // legacy name has no colour, and must come back with none.
  legacyName: c.elementFromValues({ 'Foreground Color': '$00FFAA7F' }),
  scopes: c.SCOPE_MAP.map(e => e[1]).reduce((a, b) => a.concat(b), [])
};
process.stdout.write(JSON.stringify(out));
'@
Set-Content -LiteralPath $probe -Value $probeSrc -Encoding ASCII
try {
  $json = & node $probe $libPath 2>&1
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: node probe failed: $json" -ForegroundColor Red; exit 2 }
  $r = $json | ConvertFrom-Json
} finally {
  Remove-Item -LiteralPath $probe -ErrorAction SilentlyContinue
}

Check 'BGR: $00FFAA7F -> #7FAAFF (NOT #FFAA7F)' ($r.bgr -eq '#7FAAFF') "got $($r.bgr)"
Check 'named TColor: clRed -> #FF0000'          ($r.named -eq '#FF0000') "got $($r.named)"
Check 'named TColor: clLime -> #00FF00'         ($r.namedLim -eq '#00FF00') "got $($r.namedLim)"
Check 'system colour $FF000005 has no RGB'      ($null -eq $r.system) "got $($r.system)"
Check 'empty value has no RGB'                  ($null -eq $r.empty) "got $($r.empty)"
Check 'Default Foreground=True overrides the stored colour' ($null -eq $r.defaults.fg) "got $($r.defaults.fg)"
Check 'Default Background=False keeps the stored colour'    ($r.defaults.bg -eq '#2D2F32') "got $($r.defaults.bg)"
Check 'Italic=True survives as a fontStyle'                 ($r.defaults.fontStyle -eq 'italic') "got '$($r.defaults.fontStyle)'"
Check 'the LEGACY "Foreground Color" name is not read'      ($null -eq $r.legacyName.fg) "got $($r.legacyName.fg)"

# ---------------------------------------------------------------------------
Write-Host 'CHECK 2 -- every scope ends in .pascal (or global customizations bleed)' -ForegroundColor Cyan

# Scope-shaped values only: lowercase dotted identifiers. That excludes the
# grammar's display name ("Object Pascal") without needing to special-case it.
$grammarScopes = @([regex]::Matches($grammarRaw, '"name"\s*:\s*"([a-z][a-z0-9._-]*)"') |
  ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Check 'grammar declares scope-shaped names' ($grammarScopes.Count -ge 10) "found $($grammarScopes.Count)"
$badGrammar = @($grammarScopes | Where-Object { -not $_.EndsWith('.pascal') })
Check 'every grammar scope ends in .pascal' ($badGrammar.Count -eq 0) ("offenders=" + ($badGrammar -join ','))

$mapScopes = @($r.scopes | Sort-Object -Unique)
$badMap = @($mapScopes | Where-Object { -not $_.EndsWith('.pascal') })
Check 'every SCOPE_MAP scope ends in .pascal' ($badMap.Count -eq 0) ("offenders=" + ($badMap -join ','))

# ---------------------------------------------------------------------------
Write-Host 'CHECK 3 -- the theme only colours scopes the grammar actually emits' -ForegroundColor Cyan

$themeScopes = @()
foreach ($tc in $theme.tokenColors) {
  if ($tc.scope -is [string]) { $themeScopes += $tc.scope } else { $themeScopes += @($tc.scope) }
}
$themeScopes = @($themeScopes | Sort-Object -Unique)
Check 'theme carries tokenColors' ($themeScopes.Count -ge 10) "found $($themeScopes.Count)"

# A theme rule for a scope no grammar produces is dead: it reads as configured
# and colours nothing, which is indistinguishable from "the theme works" until
# someone looks at that construct.
$dead = @($themeScopes | Where-Object { $grammarScopes -notcontains $_ })
Check 'no theme scope is unreachable from the grammar' ($dead.Count -eq 0) ("dead=" + ($dead -join ','))
$deadMap = @($mapScopes | Where-Object { $grammarScopes -notcontains $_ })
Check 'no SCOPE_MAP scope is unreachable from the grammar' ($deadMap.Count -eq 0) ("dead=" + ($deadMap -join ','))

Check 'theme sets an editor background (the point of the theme path)' `
  ([bool]$theme.colors.'editor.background') "got $($theme.colors.'editor.background')"

# ---------------------------------------------------------------------------
Write-Host 'CHECK 4 -- {$...} is a DIRECTIVE, and beats the brace-comment rule' -ForegroundColor Cyan

$top = @($grammar.patterns | ForEach-Object { $_.include })
$iDir = [Array]::IndexOf($top, '#directives')
$iCom = [Array]::IndexOf($top, '#comments')
Check 'grammar includes #directives and #comments' (($iDir -ge 0) -and ($iCom -ge 0)) "directives=$iDir comments=$iCom"
Check '#directives is tried BEFORE #comments' (($iDir -ge 0) -and ($iDir -lt $iCom)) "directives=$iDir comments=$iCom"

$dirScopes = @($grammar.repository.directives.patterns | ForEach-Object { $_.name } | Sort-Object -Unique)
Check 'directives use a directive scope, not a comment scope' `
  (($dirScopes -contains 'keyword.control.directive.pascal') -and -not ($dirScopes -join ',').Contains('comment.')) `
  ("scopes=" + ($dirScopes -join ','))

# Order alone is one line away from being wrong, so the comment rule carries its
# own guard: it must refuse to start at '{$'.
$braceComment = @($grammar.repository.comments.patterns | Where-Object { $_.name -eq 'comment.block.pascal' })
Check 'the brace-comment rule exists' ($braceComment.Count -eq 1)
if ($braceComment.Count -eq 1) {
  Check 'brace comment will not start at "{$" (negative lookahead)' `
    ($braceComment[0].begin -eq '\{(?!\$)') "begin=$($braceComment[0].begin)"
}

# ---------------------------------------------------------------------------
Write-Host 'CHECK 5 -- the manifest actually wires the grammar and the theme up' -ForegroundColor Cyan

$g = @($pkg.contributes.grammars)
Check 'package.json contributes a grammar' ($g.Count -ge 1)
if ($g.Count -ge 1) {
  Check 'grammar is bound to language "pascal"' ($g[0].language -eq 'pascal') "got $($g[0].language)"
  Check 'grammar scopeName matches the grammar file' `
    (($g[0].scopeName -eq 'source.pascal') -and ($grammar.scopeName -eq 'source.pascal')) `
    ("manifest=$($g[0].scopeName) file=$($grammar.scopeName)")
  Check 'grammar path exists' (Test-Path (Join-Path $Dir ($g[0].path -replace '^\./', ''))) $g[0].path
}

$t = @($pkg.contributes.themes)
Check 'package.json contributes a theme' ($t.Count -ge 1)
if ($t.Count -ge 1) {
  Check 'theme path exists' (Test-Path (Join-Path $Dir ($t[0].path -replace '^\./', ''))) $t[0].path
}

# The generator is a dev tool and is excluded from the .vsix, but the module it
# shares with the extension must NOT be -- extension.js requires it at runtime,
# and a missing lib/ turns both colour commands into "cannot find module".
$ignore = Get-Content (Join-Path $Dir '.vscodeignore') -Raw -ErrorAction SilentlyContinue
Check 'lib/ is not excluded from the .vsix' (-not ($ignore -match '(?m)^\s*lib/')) 'lib/ must ship'

# ---------------------------------------------------------------------------
Write-Host 'CHECK 6 -- these files are CRLF and 7-bit ASCII' -ForegroundColor Cyan

# run_encoding_guard.ps1 scans .pas/.ps1/.bat/... and explicitly does NOT scan
# editors\ -- its own exclusion note calls that a blind spot for any file "of
# our own" landing there. These four are ours, and the Write tool emits LF, so
# they would drift silently. Policed here instead.
foreach ($f in @($grammarPath, $themePath, $libPath, (Join-Path $Dir 'scripts\gen-theme.js'))) {
  if (-not (Test-Path $f)) { Check ("exists: " + (Split-Path $f -Leaf)) $false; continue }
  $bytes = [IO.File]::ReadAllBytes($f)
  $lf = 0; $cr = 0; $hi = 0
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10) { $lf++; if ($i -eq 0 -or $bytes[$i - 1] -ne 13) { $cr = -1 } }
    elseif ($bytes[$i] -gt 127) { $hi++ }
  }
  $name = Split-Path $f -Leaf
  Check ("$name is CRLF (no lone LF)") ($cr -ne -1) "lines=$lf"
  Check ("$name is 7-bit ASCII") ($hi -eq 0) "high bytes=$hi"
}

# ---------------------------------------------------------------------------
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
