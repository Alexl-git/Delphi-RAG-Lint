<#
  run_shipped_docs_private_paths_guard.ps1 -- no local path, database file, machine name, user
  profile, e-mail address or password of this machine in a file that SHIPS (owner 2026-11-24).

  Project NAMES may stay in public text (owner ruling); paths and database files may not.

  THE FILES are read from the pack itself, so a new shipped text is covered without editing this
  list: every literal `Join-Path $repo "..."` / `(Join-Path $repo $f)` source of
  build\pack-lint-release.ps1 and every {#RepoRoot} / {#Books} / {#CastLib} source of
  installer\drag-lint.iss that is text; plus rules\, the published wiki pages docs\wiki\*.md, the
  VS Code extension readme, and WWW\help\dl\index.json when this checkout has it.

  ALLOWED: the neutral example folders (MyApp, MyTool, App, Common) and the folders of published
  or third-party tools (Delphi-RAG-lint*, YADF, GraphWiz, DelphiAST, DUnitX, FastMM4, tree-sitter-*).

  POSITIVE CONTROL: the same scanner runs on one text per pattern and must report it; NEGATIVE
  CONTROL: the neutral forms must be silent.
#>
param([string]$Repo = '')
if (-not $Repo) { $Repo = (Resolve-Path "$PSScriptRoot\..\..").Path }
$ErrorActionPreference = 'Stop'
$script:fails = 0; $script:passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" } else { $script:fails++; "FAIL $Name $Detail" }
}

$private = 'Micronite\w*|MICRONITE\w*|ORM3[\w-]*|M2022|DMTEST|DataCopy\w*|OCRPDF|Loader2025|TableTools\w*|INSPFLDR'
$patterns = [ordered]@{
  'private project path' = '(?i)\b[A-Z]:[\\/]+Projects(?>[\\/]+)(?!(MyApp|MyTool|App|Common|YADF|GraphWiz|DelphiAST|DUnitX|FastMM4)\b|Delphi-RAG-lint|tree-sitter-|\.\.\.|<|\*|["''`\s)|]|$)'
  'user profile path'    = '(?i)\bUsers(?>[\\/]+)(?!<|you\b|me\b|Public\b|user\b|%|\$|\*|\.\.\.)[a-z]\w+[\\/]'
  'user / machine name'  = '\balexanderl\b|\bHTRTEST\b|\bALEX9\b|\bMICDATA_D\b'
  'private database file' = "(?i)(?<![\w-])($private)\.(sqlite|dlrepo|fdb|gdb)\b|(?i)\bMICRONITEV6A\b"
  'e-mail address'       = '(?i)\b[A-Z0-9._%+-]+@(?!example\.)[A-Z0-9-]+\.(com|net|org|us|io|ru)\b'
  'password'             = '(?i)\b(masterkey|password=(?!\.\.\.|<|\*|hunter2\b|%|\$|["''`;\s)])\w{3,})'
}
function Find-Private([string]$Text) {
  foreach ($k in $patterns.Keys) {
    foreach ($m in [regex]::Matches($Text, $patterns[$k])) {
      $line = 1 + ($Text.Substring(0, $m.Index).Split("`n").Count - 1)
      [pscustomobject]@{ Kind = $k; Line = $line; Text = $Text.Substring($m.Index, [Math]::Min(70, $Text.Length - $m.Index)).Split("`n")[0].TrimEnd() }
    }
  }
}

# ---- controls ---------------------------------------------------------------
$bad = [ordered]@{
  'private project path'  = 'index --project C:\Projects\DB\X\CLIENT\App.dproj', '"db": "C:\\Projects\\.drag-lint\\library-Win64.sqlite"', 'file: C:/Projects/SomeTool/uA.pas'
  'user profile path'     = 'node "C:/Users/somebody/.claude/x.js"'
  'user / machine name'   = 'copy to HTRTEST'
  'private database file' = 'wrote into Micronite2027.sqlite', 'Verified against MICRONITEV6A.FDB', 'ORM3-Interfaces.sqlite'
  'e-mail address'        = 'write to someone@company.com'
  'password'              = 'User=SYSDBA;Password=s3cret'
}
foreach ($k in $bad.Keys) {
  foreach ($s in $bad[$k]) { Check "control: reported as $k -- $s" (@(Find-Private $s | Where-Object Kind -eq $k).Count -ge 1) }
}
foreach ($s in 'C:\Projects\MyApp\CLIENT\MyApp.dproj', 'C:\Projects\MyTool\_D-RAG\MyTool.sqlite', 'C:\drag-lint-index\library-Win32.sqlite',
               'Measured on ORM3 CLIENT: 14 of 117', 'Micronite, our quality software', 'C:\Users\<you>\AppData', 'Password=...;DriverID=FB', 'C:\Projects\YADF\YADF.dproj', 'a `.fdb` file') {
  Check "control: silent -- $s" (@(Find-Private $s).Count -eq 0) ((Find-Private $s | ForEach-Object Kind) -join ',')
}

# ---- the shipped files ------------------------------------------------------
$textExt = '.md', '.html', '.rules', '.castlib', '.json', '.scm', '.txt'
$rel = New-Object System.Collections.Generic.List[string]
$pack = [IO.File]::ReadAllText((Join-Path $Repo 'build\pack-lint-release.ps1'))
foreach ($m in [regex]::Matches($pack, 'Join-Path\s+\$repo\s+"([^"$]+)"')) { $rel.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($pack, "foreach \(\`$[af] in ([^)]+)\)")) {
  foreach ($n in [regex]::Matches($m.Groups[1].Value, "'([^']+\.(md|html))'")) {
    $n1 = $n.Groups[1].Value
    if (Test-Path -LiteralPath (Join-Path $Repo $n1)) { $rel.Add($n1) } else { $rel.Add("docs\" + $n1) }
  }
}
$iss = [IO.File]::ReadAllText((Join-Path $Repo 'installer\drag-lint.iss'))
foreach ($m in [regex]::Matches($iss, '(?m)^Source: "\{#RepoRoot\}\\([^"]+)"')) { $rel.Add($m.Groups[1].Value) }
foreach ($m in [regex]::Matches($iss, '(?m)^Source: "\{#Books\}\\([^"]+)"')) { $rel.Add("convrules\" + $m.Groups[1].Value) }
foreach ($x in 'rules\*', 'docs\wiki\*.md', 'editors\vscode\drag-lint\README.md', 'WWW\help\dl\index.json') { $rel.Add($x) }
$files = @($rel | Sort-Object -Unique | ForEach-Object { Get-ChildItem -Path (Join-Path $Repo $_) -File -ErrorAction SilentlyContinue } |
  Where-Object { $_.Extension -in $textExt } | ForEach-Object FullName | Sort-Object -Unique)
foreach ($must in 'README.md', 'CHANGELOG.md', 'INSTALL.md', 'docs\AI-USAGE.md', 'docs\converter\convrules-editor-manual.md', 'docs\PARSING-LAYERS.html',
                  'convrules\sample.rules', 'convrules\vendor\README.md', 'docs\examples\convrules\casts.castlib', 'rules\README.md', 'docs\wiki\Wiki-Blocks-Authoring.md', 'installer\drag-lint.starter.json') {
  Check "the list holds $must" ($files -contains (Join-Path $Repo $must))
}
$hits = foreach ($f in $files) {
  foreach ($h in Find-Private ([IO.File]::ReadAllText($f))) { "{0}:{1} {2}: {3}" -f $f.Substring($Repo.Length + 1), $h.Line, $h.Kind, $h.Text }
}
$hits = @($hits)
Check ("no private path / database / machine name in {0} shipped text files" -f $files.Count) ($hits.Count -eq 0) ("`n  " + (($hits | Select-Object -First 40) -join "`n  "))
"run_shipped_docs_private_paths_guard: $script:passes passed, $script:fails failed"
if ($script:fails -gt 0) { exit 1 }
exit 0
