<#
  run_implementors_guard.ps1 -- the interface report (`implementors` verb, 1.40).

  Spec: docs\superpowers\specs\2026-11-01-interface-report-design.md (section 8).
  Needs the x129 extractor rows (lane call): the clause edge to RunJob and the
  'delegates' row; an exe without them fails T2/T3/T5 by design.
  Fixture: tests\fixtures\ifrpt\IfFix.pas -- a plain implementor, a method-resolution
  clause (IJob.Execute = RunJob), an inherited implementation through a derived
  interface (TInheritedJob(TBaseJob, IJobEx)), a subclass of an implementor
  (TSubJob), `implements` delegation (TDelegatingJob), a class that has an Execute
  but does NOT implement IJob (TNotAJob, TBaseJob), an interface property, and call
  sites in UseIt.

  Every assertion counts exactly, and each has a positive control: a class that must
  be ABSENT, a phantom that must NOT be printed, a site count that must be 0 without
  --uses. Indexes its own scratch DB; never touches a real index.
  -LspExe: also runs T6 (LSP textDocument/implementation on IJob.Execute).
  Run from any CWD, pwsh 7 or Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "C:\TEMP\draglint_implementors_$PID",
  [string]$RealDb  = ''
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Exe)    { $Exe    = Join-Path $here '..\..\src\cli\Win64\Debug\drag-lint.exe' }
if (-not $RealDb) { $RealDb = Join-Path $here '..\..\src\cli\_D-RAG\drag-lint.sqlite' }
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
$ErrorActionPreference = 'Continue'  # a native stderr note is not an error (PS 5.1)
Copy-Item "$here\..\fixtures\ifrpt\IfFix.pas" $src
$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db *> (Join-Path $WorkDir 'index.log')
Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"

function Ifr([string[]]$a) {
  $out = & $exePath implementors @a --db $db 2>&1 | Out-String
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = $out }
}
function IfrJson([string[]]$a) {
  $r = Ifr (@($a) + '--json')
  $j = $null
  try { $j = $r.Text | ConvertFrom-Json } catch { }
  return [pscustomobject]@{ Exit = $r.Exit; J = $j; Text = $r.Text }
}
function Names($rows, $field) { @($rows | ForEach-Object { ($_.$field -split '\.')[-1] }) | Sort-Object }

# ---- T1: interface -> implementing classes ----
$r = IfrJson @('--target', 'IJob')
Check 'T1 exit 0' ($r.Exit -eq 0) $r.Text
$cls = Names $r.J.implementors 'class'
Check 'T1 exactly the seven implementors' (($cls -join ',') -eq 'TDelegatingJob,TInheritedJob,TOverJob,TPlainJob,TRenamedJob,TSubJob,TVirtJob') ($cls -join ',')
Check 'T1 control: TBaseJob / TNotAJob absent' (-not ($cls -contains 'TBaseJob') -and -not ($cls -contains 'TNotAJob')) ($cls -join ',')
$inh = @($r.J.implementors | Where-Object { $_.class -like '*.TInheritedJob' })[0]
Check 'T1 TInheritedJob how=via IJobEx' ($inh.how -eq 'via' -and $inh.via -like '*.IJobEx') "$($inh.how) $($inh.via)"
$sub = @($r.J.implementors | Where-Object { $_.class -like '*.TSubJob' })[0]
Check 'T1 TSubJob how=inherited from TPlainJob' ($sub.how -eq 'inherited' -and $sub.via -like '*.TPlainJob') "$($sub.how) $($sub.via)"
$del = @($r.J.implementors | Where-Object { $_.class -like '*.TDelegatingJob' })[0]
Check 'T1 TDelegatingJob how=delegated by Inner' ($del.how -eq 'delegated' -and $del.via -like '*.Inner') "$($del.how) $($del.via)"

# ---- T2/T3: interface method -> answering methods ----
$r = IfrJson @('--target', 'IJob.Execute')
Check 'T2 exit 0' ($r.Exit -eq 0) $r.Text
$byCls = @{}; foreach ($x in $r.J.implementors) { $byCls[($x.class -split '\.')[-1]] = $x }
Check 'T2 seven answered' ($r.J.implementors.Count -eq 7) (($byCls.Keys | Sort-Object) -join ',')
Check 'T2 TInheritedJob answered by TBaseJob.Execute' ($byCls['TInheritedJob'].method -like '*.TBaseJob.Execute' -and $byCls['TInheritedJob'].declared_in -like '*.TBaseJob') "$($byCls['TInheritedJob'].method)"
Check 'T2 TSubJob answered by TPlainJob.Execute' ($byCls['TSubJob'].method -like '*.TPlainJob.Execute') "$($byCls['TSubJob'].method)"
Check 'T2 TOverJob answered by its own override' ($byCls['TOverJob'].method -like '*.TOverJob.Execute') "$($byCls['TOverJob'].method)"
Check 'T2 control: TVirtJob answered by TVirtJob.Execute' ($byCls['TVirtJob'].method -like '*.TVirtJob.Execute') "$($byCls['TVirtJob'].method)"
Check 'T2 control: TBaseJob not an implementor' (-not $byCls.ContainsKey('TBaseJob'))
$un = @($r.J.unanswered)
Check 'T2 TDelegatingJob answered by delegation (property Inner), nothing unanswered' ($un.Count -eq 0 -and $byCls['TDelegatingJob'].how -eq 'delegated' -and $byCls['TDelegatingJob'].via -like '*.TDelegatingJob.Inner') ($un | ConvertTo-Json -Compress)
$rj = $byCls['TRenamedJob']
Check 'T3 resolution clause names RunJob' ($rj.method -like '*.TRenamedJob.RunJob') "$($rj.method)"
Check 'T3 clause edge certain, labelled Execute = RunJob' ($rj.confidence -eq 'certain' -and $rj.note -like '*Execute = RunJob*') "$($rj.confidence) $($rj.note)"
Check 'T3 control: phantom TRenamedJob.Execute never printed' (-not ($r.Text -match 'TRenamedJob\.Execute'))
Check 'T4 IJob.Execute: 1 call site in UseIt' ($r.J.sites_total -eq 1 -and $r.J.sites[0].mode -eq 'call' -and $r.J.sites[0].enclosing -like '*.UseIt') ($r.J.sites | ConvertTo-Json -Compress)

# ---- T4: property and implementor sites ----
$r = IfrJson @('--target', 'IJob.Name')
Check 'T4 IJob.Name: 1 read' ($r.Exit -eq 0 -and $r.J.sites_total -eq 1 -and $r.J.sites[0].mode -eq 'read') $r.Text
$r = IfrJson @('--target', 'TPlainJob.Execute')
Check 'T4 implementor answers IJob.Execute' ($r.Exit -eq 0 -and @($r.J.implementors).Count -eq 1 -and $r.J.implementors[0].member -like '*.IJob.Execute') $r.Text
Check 'T4 control: no sites without --uses' ($r.J.sites_total -eq 0)
$r = IfrJson @('--target', 'TPlainJob.Execute', '--uses')
Check 'T4 --uses: the interface site, via IJob.Execute' ($r.J.sites_total -eq 1 -and $r.J.sites[0].via -like '*.IJob.Execute') $r.Text

# ---- T5: class -> interfaces and what answers each member ----
$r = IfrJson @('--target', 'TInheritedJob')
$m = @{}; foreach ($x in $r.J.implementors) { $m[($x.member -split '\.')[-2..-1] -join '.'] = ($x.method -split '\.')[-2..-1] -join '.' }
Check 'T5 IJobEx.Cancel -> TInheritedJob.Cancel' ($m['IJobEx.Cancel'] -eq 'TInheritedJob.Cancel') (($m.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')
Check 'T5 IJob.Execute -> TBaseJob.Execute (inherited)' ($m['IJob.Execute'] -eq 'TBaseJob.Execute')
Check 'T5 three members, none unanswered' ($m.Count -eq 3 -and @($r.J.unanswered).Count -eq 0)
$r = IfrJson @('--target', 'TDelegatingJob')
Check 'T5 TDelegatingJob: both members delegated to Inner' (@($r.J.unanswered).Count -eq 0 -and @($r.J.implementors | Where-Object { $_.how -eq 'delegated' -and $_.via -like '*.Inner' }).Count -eq 2) $r.Text

# ---- T7: JSON shape on an empty answer ----
$r = IfrJson @('--target', 'TNotAJob')
Check 'T7 empty answer: exit 0, schema, every array present' ($r.Exit -eq 0 -and $r.J.schema -eq 'implementors/1' -and
  $r.Text -match '"implementors":\[\]' -and $r.Text -match '"unanswered":\[\]' -and $r.Text -match '"sites":\[\]' -and $r.Text -match '"notes":\[\]') $r.Text

# ---- usage / errors / formats ----
$r = Ifr @('--target', 'INoSuchThing')
Check 'E1 unknown target: exit 1' ($r.Exit -eq 1) $r.Text
$r = Ifr @('--target', 'Execute')
Check 'E2 ambiguous bare name: exit 2, candidates listed' ($r.Exit -eq 2 -and $r.Text -match 'TPlainJob\.Execute') $r.Text
$r = Ifr @('--target', 'IJob', '--format', 'xml')
Check 'E3 bad --format: exit 2' ($r.Exit -eq 2) $r.Text
$r = Ifr @('--target', 'IJob.Execute')
Check 'F1 text: heading and clause label' ($r.Text -match 'implementors \(7\):' -and $r.Text -match 'resolution clause \(Execute = RunJob\)' -and $r.Text -notmatch 'not answered') $r.Text
$r = Ifr @('--target', 'IJob', '--format', 'dot')
Check 'F2 dot chart' ($r.Exit -eq 0 -and $r.Text -match '(?m)^digraph implementors' -and $r.Text -match 'TSubJob') $r.Text
$r = Ifr @('--target', 'IJob', '--format', 'mermaid')
Check 'F3 mermaid chart' ($r.Exit -eq 0 -and $r.Text -match '(?m)^flowchart LR') $r.Text

# ---- T6: LSP textDocument/implementation on IJob.Execute reads the implements rows ----
function Frame($o) { $b = ($o | ConvertTo-Json -Compress -Depth 10); return "Content-Length: $($b.Length)`r`n`r`n$b" }
$fx = Join-Path $src 'IfFix.pas'
$fl = [IO.File]::ReadAllLines($fx)
function LineOf([string]$pat) { for ($i = 0; $i -lt $fl.Count; $i++) { if ($fl[$i] -match $pat) { return $i } }; return -1 }
$lDecl = LineOf '^\s+procedure Execute;$'          # the first one is IJob's
$want = @((LineOf '^procedure TPlainJob\.Execute;'), (LineOf '^procedure TRenamedJob\.RunJob;'),
          (LineOf '^procedure TBaseJob\.Execute;'), (LineOf '^procedure TVirtJob\.Execute;'),
          (LineOf '^procedure TOverJob\.Execute;')) | Sort-Object
$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=11; method='textDocument/implementation'; params=@{ textDocument=@{ uri=('file:///' + $fx.Replace('\', '/')) }; position=@{ line=$lDecl; character=($fl[$lDecl].IndexOf('Execute') + 1) } } }
$fxUri = 'file:///' + $fx.Replace('\', '/')
$m += Frame @{ jsonrpc='2.0'; id=12; method='textDocument/codeLens'; params=@{ textDocument=@{ uri=$fxUri } } }
$m += Frame @{ jsonrpc='2.0'; id=13; method='draglint/callerCounts'; params=@{ textDocument=@{ uri=$fxUri } } }
$m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
$inF = Join-Path $WorkDir 'lsp_in.txt'; $outF = Join-Path $WorkDir 'lsp_out.txt'
[IO.File]::WriteAllText($inF, $m, [Text.Encoding]::ASCII)
Start-Process $exePath -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir -RedirectStandardInput $inF `
  -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $WorkDir 'lsp_err.txt') -NoNewWindow -Wait | Out-Null
$got = @()
foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -eq 11) { $got = @($o.result | ForEach-Object { $_.range.start.line }) | Sort-Object }
  if ($o.id -eq 12) { $lens = @($o.result) }
  if ($o.id -eq 13) { $cc = $o.result }
}
Check 'T6 LSP implementation of IJob.Execute = the five answering bodies' (($got -join ',') -eq ($want -join ',')) "got=$($got -join ',') want=$($want -join ',')"
Check 'T6 control: not the phantom clause line, not TNotAJob' (-not ($got -contains (LineOf 'IJob\.Execute = RunJob')) -and -not ($got -contains (LineOf '^procedure TNotAJob\.Execute;')))

$lIJob = LineOf '^\s+IJob = interface'
$implLens = @($lens | Where-Object { $_.command.command -eq 'draglint.showImplementors' })
$onIJob = @($implLens | Where-Object { $_.range.start.line -eq $lIJob })
$onExec = @($implLens | Where-Object { $_.range.start.line -eq $lDecl })
Check 'L1 codeLens: "7 implementors" above IJob' ($onIJob.Count -eq 1 -and $onIJob[0].command.title -eq '7 implementors') ($implLens | ConvertTo-Json -Compress -Depth 6)
Check 'L1 codeLens: "5 implementors" above IJob.Execute (distinct answering methods)' ($onExec.Count -eq 1 -and $onExec[0].command.title -eq '5 implementors')
Check 'L1 control: no implementors lens on a class line' (-not @($implLens | Where-Object { $_.range.start.line -eq (LineOf '^\s+TNotAJob = class') }).Count)
$ccI = @($cc.implementors | Where-Object { $_.line -eq $lIJob })
Check 'L2 draglint/callerCounts carries implementors (plugin lens)' ($ccI.Count -eq 1 -and $ccI[0].count -eq 7 -and $null -ne $cc.counts) ($cc | ConvertTo-Json -Compress -Depth 5)

# ---- A1: the `ask implementors` chart (same engine; rows parsed from its anchored labels) ----
$askOut = Join-Path $WorkDir 'ask'
$a = & $exePath ask implementors --target IJob.Execute --db $db --plain --out-root $askOut --allow-stale 2>&1 | Out-String
$aExit = $LASTEXITCODE
Check 'A1 ask implementors: exit 0, 7 implementors, rows anchored (RunJob, TOverJob.Execute)' ($aExit -eq 0 -and
  $a -match 'CHART implementors IJob\.Execute -- 7 implementors' -and $a -match 'TRenamedJob\.RunJob @IfFix\.pas:\d+' -and $a -match 'TOverJob\.Execute @IfFix\.pas:\d+') $a
$a = & $exePath ask implementors --target INoSuchThing --db $db --plain --out-root $askOut --allow-stale 2>&1 | Out-String
Check 'A1 control: an unknown target is refused (exit 1)' ($LASTEXITCODE -eq 1) $a
# ---- M1/M2: MCP get_implementors (same engine) and the corrected get_wiring text ----
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
$list = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
$call = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_implementors","arguments":{"qname":"IJob.Execute"}}}'
$bad  = '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_implementors","arguments":{"qname":"INoSuchThing"}}}'
$mcp  = "$init`n$list`n$call`n$bad" | & $exePath serve --db $db 2>$null | Out-String
$rep  = @{}
foreach ($ln in ($mcp -split "`n")) { try { $o = $ln.Trim() | ConvertFrom-Json; if ($o.id) { $rep[[int]$o.id] = $o } } catch { } }
$tools = @($rep[2].result.tools)
$gi = @($tools | Where-Object { $_.name -eq 'get_implementors' })
$gw = @($tools | Where-Object { $_.name -eq 'get_wiring' })
Check 'M1 tools/list carries get_implementors' ($gi.Count -eq 1 -and $gi[0].inputSchema.required -contains 'qname')
Check 'M1 get_wiring no longer claims "who implements IFoo"; points at get_implementors' ($gw.Count -eq 1 -and $gw[0].description -notmatch 'who implements' -and $gw[0].description -match 'get_implementors') "$($gw[0].description)"
$txt = [string]$rep[3].result.content[0].text
Check 'M2 get_implementors IJob.Execute: implementors/1 naming RunJob' ($txt -match 'implementors/1' -and $txt -match 'TRenamedJob\.RunJob') $txt
Check 'M2 control: unknown target is an error, not an empty answer' ($null -ne $rep[4].error -or [bool]$rep[4].result.isError) ($rep[4] | ConvertTo-Json -Compress -Depth 5)

# ---- T8: the real CLI index, read-only (skipped when absent) ----
if (Test-Path $RealDb) {
  $out = & $exePath implementors --target DRagLint.Core.Interfaces.IParser.Parse --db $RealDb --json 2>$null | Out-String
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $n = (Names $j.implementors 'class') -join ','
  Check 'T8 src\cli: IParser.Parse -> the four parsers (TMarkdownParser since 1.47, Markdown text nodes)' ($n -eq 'TDelphi13Parser,TDFMParser,TFirebirdSqlParser,TMarkdownParser') $n
} else { Write-Host '[SKIP] T8 (no src\cli index)' }

if (-not $script:fail) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:fail) { Write-Host 'run_implementors_guard: FAIL'; exit 1 }
Write-Host 'run_implementors_guard: PASS'
exit 0
