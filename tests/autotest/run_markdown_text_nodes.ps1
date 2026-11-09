# E-PARITY-GRAPHIFY (wave 147, lane B2): Markdown text nodes.
#
# A project index admits the *.md files beside its project file (top level only)
# as text nodes: string_literals rows source='md', kind 'md-heading' / 'md-text',
# owner_name = the enclosing heading. Fenced code is not a text node, and no
# compiler-directive preprocessing touches Markdown. Directory walks are
# unchanged (no .md). graph --format json|html carries text_nodes plus
# text_edges (a text node -> the unit declaring a `backticked` name it mentions).
#
# (-like is not used on text with backticks: a backtick escapes in a wildcard.)
# RED on 1.46.0-alpha (no Markdown parser): checks 1-7 fail. Check 8 and 9 are
# controls that hold on both engines (walks never admit .md; lint never anchors
# a finding in a .md) -- they would fail if the walk exclusion or a lint path
# that reads every file were broken.
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe"; exit 2 }

$Root = Join-Path $env:TEMP ('dl-md-nodes-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$Src  = Join-Path $Root 'src'
[IO.Directory]::CreateDirectory((Join-Path $Src 'docs')) | Out-Null
$Ascii = [Text.Encoding]::ASCII
function Put([string]$Path, [string[]]$Lines) { [IO.File]::WriteAllText($Path, ($Lines -join "`r`n") + "`r`n", $Ascii) }

Put (Join-Path $Src 'MdDemo.dpr') @('program MdDemo;', 'uses', '  uMdA in ''uMdA.pas'';', 'begin', '  TWidget.Create.Run;', 'end.')
Put (Join-Path $Src 'uMdA.pas') @('unit uMdA;', 'interface', 'type', '  TWidget = class', '    procedure Run;', '  end;',
  'implementation', 'procedure TWidget.Run;', 'begin', 'end;', 'end.')
Put (Join-Path $Src 'README.md') @('---', 'title: FrontMatterTitle', '---', '# Widget guide', '',
  'The `TWidget` class lives in `uMdA` and', 'wraps the RunAll flow.', '',
  '```pascal', 'SecretInFence := 1;', '```', '',
  '## Notes', '', 'A literal {$IFDEF NEVER} in prose.', '', 'AfterIfdef stays a text node.', '',
  '- ListItemOne', '- ListItemTwo mentions `NoSuchSymbolAnywhere`')
Put (Join-Path $Src 'docs\deep.md') @('# DeepDocHeading', '', 'DeepDocText')

$Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail"; $script:Fail++ }
}
function Rows([string]$Db, [string]$Query) {
  $J = (& $Exe sql --db $Db --query $Query --json 2>$null) -join "`n" | ConvertFrom-Json
  $Names = @($J.columns | ForEach-Object { $_.name })
  $Out = @()
  foreach ($R in @($J.rows)) {
    $O = [ordered]@{}
    for ($i = 0; $i -lt $Names.Count; $i++) { $O[$Names[$i]] = $R[$i] }
    $Out += [pscustomobject]$O
  }
  return ,$Out
}

try {
  $Db = Join-Path $Root 'proj.sqlite'
  & $Exe index --project (Join-Path $Src 'MdDemo.dpr') --db $Db 2>&1 | Out-Null
  if (-not (Test-Path $Db)) { Write-Host 'FATAL: index --project produced no DB'; exit 2 }

  $Files = Rows $Db "SELECT path, language FROM files"
  Check '0 control: the project unit is indexed' (@($Files | Where-Object { $_.path -like '*uMdA.pas' }).Count -eq 1)
  $Md = @($Files | Where-Object { $_.path -like '*README.md' })
  Check '1 README.md beside the project is a file row, language markdown' (($Md.Count -eq 1) -and ($Md[0].language -eq 'markdown')) ("got: " + ($Files | ConvertTo-Json -Compress))

  $Lits = Rows $Db "SELECT kind, owner_name, text, start_line FROM string_literals WHERE source = 'md' ORDER BY start_line"
  $H = @($Lits | Where-Object { $_.kind -eq 'md-heading' -and $_.text -eq 'Widget guide' })
  Check '2 heading node (line 4)' (($H.Count -eq 1) -and ($H[0].start_line -eq 4)) ("got: " + ($Lits | ConvertTo-Json -Compress))
  $P = @($Lits | Where-Object { $_.kind -eq 'md-text' -and $_.text.Contains('`TWidget` class lives in `uMdA` and wraps the RunAll flow.') })
  Check '3 paragraph node joins its lines, owned by its heading' (($P.Count -eq 1) -and ($P[0].owner_name -eq 'Widget guide') -and ($P[0].start_line -eq 6))
  Check '4 fenced code and front matter are not text nodes' ((@($Lits | Where-Object { $_.text -like '*SecretInFence*' -or $_.text -like '*FrontMatterTitle*' }).Count -eq 0) -and ($Lits.Count -gt 0))
  $After = @($Lits | Where-Object { $_.text -eq 'AfterIfdef stays a text node.' -and $_.owner_name -eq 'Notes' })
  Check '5 no directive preprocessing: text after {$IFDEF NEVER} survives' ($After.Count -eq 1)
  Check '5b list items are their own nodes' (@($Lits | Where-Object { $_.text -eq 'ListItemOne' }).Count -eq 1)
  Check '6 a .md in a subfolder is not admitted' (@($Files | Where-Object { $_.path -like '*deep.md' }).Count -eq 0)

  $Q = (& $Exe query --text 'AfterIfdef' --source md --db $Db 2>$null) -join "`n"
  Check '7a query --text --source md finds the node' ($Q -match 'README\.md:17:')

  $G = (& $Exe graph --db $Db --format json 2>$null) -join "`n"
  $GJ = $null
  try { $GJ = $G.Substring($G.IndexOf('{')) | ConvertFrom-Json } catch { }
  $TN = @(); $TE = @()
  if ($GJ) { $TN = @($GJ.text_nodes); $TE = @($GJ.text_edges) }
  Check '7b graph json has the README text nodes' (@($TN | Where-Object { $_.file -eq 'README.md' -and $_.line -eq 6 }).Count -eq 1) ("got: " + $G.Substring(0, [Math]::Min(400, $G.Length)))
  $E1 = @($TE | Where-Object { $_.to -eq 'uMdA' -and $_.name -eq 'TWidget' })
  $E2 = @($TE | Where-Object { $_.to -eq 'uMdA' -and $_.name -eq 'uMdA' })
  Check '7c text_edges link `TWidget` and `uMdA` to unit uMdA' (($E1.Count -eq 1) -and ($E2.Count -eq 1)) ("edges: " + ($TE | ConvertTo-Json -Compress))
  Check '7d an unknown backticked name makes no edge' (@($TE | Where-Object { $_.name -eq 'NoSuchSymbolAnywhere' }).Count -eq 0)
  Check '7e the unit edges are still there' (@($GJ.edges).Count -ge 1)
  $Html = (& $Exe graph --db $Db --format html 2>$null) -join "`n"
  Check '7f graph html lists the text nodes' (($Html -match 'Widget guide') -and ($Html -match 'text node'))

  $DirDb = Join-Path $Root 'dir.sqlite'
  & $Exe index $Src --db $DirDb 2>&1 | Out-Null
  $DF = Rows $DirDb "SELECT path FROM files"
  Check '8 control: a directory walk still admits no .md' ((@($DF | Where-Object { $_.path -like '*.md' }).Count -eq 0) -and (@($DF | Where-Object { $_.path -like '*uMdA.pas' }).Count -eq 1))

  $LJ = (& $Exe lint-all --db $Db --json 2>$null) -join "`n"
  $LA = @()
  try { $LA = @($LJ.Substring($LJ.IndexOf('[')) | ConvertFrom-Json) } catch { }
  Check '9 control: lint-all anchors no finding in a .md' (@($LA | Where-Object { $_.file_path -like '*.md' }).Count -eq 0) ("findings: " + $LA.Count)
}
finally {
  try { [IO.Directory]::Delete($Root, $true) } catch { }
}
if ($Fail -gt 0) { Write-Host "RESULT: $Fail failure(s)"; exit 1 }
Write-Host 'RESULT: all pass'
exit 0
