#Requires -Version 7
<#
  run_lsp_project_created_mid_session_guard.ps1 -- 144 lspctx tail (148 LS): a project file
  created while the language server runs is seen without a restart. Before 148 the folder
  listing (FNearProjects) and a project-less file's context (FCtxCache) were session-long,
  so a unit opened before its .dproj existed stayed "no project" until the server restarted.
  One LIVE session (piped stdin, not a pre-written file), explicit --db, no defaults file:
    OWN   (passes on the 147 base too: didClose drops the memo and D2 re-reads the sole .dproj)
          uLoose.pas opened -> no project (POSITIVE CONTROL: the first open must not see a
          project that does not exist yet); then app\App.dproj listing it is created, the
          file is closed and reopened -> project = App.dproj.
    SIB   uLoose2.pas opened -> no project; then the EXISTING sibling folder proj\ gets
          P.dproj listing ..\app2\uLoose2.pas (only proj\'s stamp changes, not repo\'s) ->
          reopened -> project = P.dproj.
    SAVE  uLoose3.pas opened -> no project; proj3\Q.dproj listing it is created; the file is
          SAVED, never closed (its context memo is not dropped by didClose) -> project = Q.dproj.
    KEEP  CONTROL: a file whose project existed from the start keeps it on reopen.
  Run from any CWD, pwsh 7. -Exe defaults to the repo build.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-midproj-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
. (Join-Path $PSScriptRoot 'lsp_stdio_helpers.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
$env:DRAGLINT_CONTEXT_DEFAULTS = "$WorkDir\no-defaults.json"
$env:DRAGLINT_LSP_REINDEX_EXE = $env:ComSpec   # a pending fixture DB must never start a real run

function PasText([string]$n) { "unit $n;`r`n`r`ninterface`r`n`r`nprocedure Do$n;`r`n`r`nimplementation`r`n`r`nprocedure Do$n;`r`nbegin`r`nend;`r`n`r`nend.`r`n" }
function DprojText([string]$include) {
  "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n  <PropertyGroup>`r`n" +
  "    <Config Condition=`"'`$(Config)'==''`">Debug</Config>`r`n    <Platform Condition=`"'`$(Platform)'==''`">Win32</Platform>`r`n" +
  "  </PropertyGroup>`r`n  <ItemGroup>`r`n    <DCCReference Include=`"$include`"/>`r`n  </ItemGroup>`r`n</Project>`r`n"
}
function Uri($p) { 'file:///' + ($p -replace '\\', '/') }

$R = "$WorkDir\repo"
New-Item -ItemType Directory -Force "$R\.git", "$R\app", "$R\app2", "$R\app3", "$R\proj", "$R\proj3", "$R\kept", "$WorkDir\lib" | Out-Null
$own  = "$R\app\uLoose.pas";  WriteAnsi $own  (PasText 'uLoose')
$sib  = "$R\app2\uLoose2.pas"; WriteAnsi $sib  (PasText 'uLoose2')
$sav  = "$R\app3\uLoose3.pas"; WriteAnsi $sav  (PasText 'uLoose3')
$kept = "$R\kept\uKept.pas";  WriteAnsi $kept (PasText 'uKept')
WriteAnsi "$R\kept\Kept.dproj" (DprojText 'uKept.pas')
WriteAnsi "$WorkDir\lib\uLib.pas" (PasText 'uLib')
$db = "$WorkDir\library-Win64.sqlite"
& $Exe index "$WorkDir\lib" --db $db 2>&1 | Out-Null

$psi = [Diagnostics.ProcessStartInfo]::new($Exe)
foreach ($a in @('lsp', '--db', $db)) { $psi.ArgumentList.Add($a) }
$psi.WorkingDirectory = $WorkDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
function Send($o) { $p.StandardInput.Write((Frame $o)); $p.StandardInput.Flush() }
function Open($f) { Send @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=(Uri $f); languageId='pascal'; version=1; text=[IO.File]::ReadAllText($f) } } } }
function Save($f) { Send @{ jsonrpc='2.0'; method='textDocument/didSave'; params=@{ textDocument=@{ uri=(Uri $f) } } } }
function Close($f) { Send @{ jsonrpc='2.0'; method='textDocument/didClose'; params=@{ textDocument=@{ uri=(Uri $f) } } } }
$settle = 3
Send @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
Send @{ jsonrpc='2.0'; method='initialized'; params=@{} }
Open $own; Open $sib; Open $kept; Open $sav
Start-Sleep -Seconds $settle   # the first opens are answered before the project files appear
WriteAnsi "$R\app\App.dproj" (DprojText 'uLoose.pas')
WriteAnsi "$R\proj\P.dproj"  (DprojText '..\app2\uLoose2.pas')
WriteAnsi "$R\proj3\Q.dproj" (DprojText '..\app3\uLoose3.pas')
Close $own; Close $sib; Close $kept
Open $own; Open $sib; Open $kept
Save $sav   # still open: no didClose cleared its memo
Send @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} }
Send @{ jsonrpc='2.0'; method='exit'; params=@{} }
$p.StandardInput.Close()
if (-not $p.WaitForExit(60000)) { $p.Kill($true); Write-Host 'FATAL: server did not exit' -ForegroundColor Red; exit 2 }
$out = $outTask.Result
$ctx = @{}
foreach ($mm in [regex]::Matches($out, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.method -eq 'draglint/context') { $k = [string]$o.params.uri; if (-not $ctx.ContainsKey($k)) { $ctx[$k] = @() }; $ctx[$k] += ,$o.params }
}
function Ctx($f, $i) { $l = $ctx[(Uri $f)]; if ($l -and $l.Count -gt $i) { return $l[$i] } else { return $null } }
function Proj($c) { if ($c) { return [string]$c.project } else { return '<no context>' } }

Write-Host ''
Write-Host 'run_lsp_project_created_mid_session_guard -- a project file created mid-session is seen' -ForegroundColor Cyan
Check 'OWN control: first open -> a context notice, no project' (((Ctx $own 0) -ne $null) -and (Proj (Ctx $own 0)) -eq '') "project=$(Proj (Ctx $own 0))"
Check 'OWN: reopened after App.dproj appeared -> project App.dproj' ((Proj (Ctx $own 1)) -like '*\app\App.dproj') "project=$(Proj (Ctx $own 1))"
Check 'SIB control: first open -> no project' (((Ctx $sib 0) -ne $null) -and (Proj (Ctx $sib 0)) -eq '') "project=$(Proj (Ctx $sib 0))"
Check 'SIB: reopened after proj\P.dproj appeared -> project P.dproj' ((Proj (Ctx $sib 1)) -like '*\proj\P.dproj') "project=$(Proj (Ctx $sib 1))"
Check 'SAVE control: first open -> no project' (((Ctx $sav 0) -ne $null) -and (Proj (Ctx $sav 0)) -eq '') "project=$(Proj (Ctx $sav 0))"
Check 'SAVE: saved (never closed) after proj3\Q.dproj appeared -> project Q.dproj' ((Proj (Ctx $sav 1)) -like '*\proj3\Q.dproj') "project=$(Proj (Ctx $sav 1))"
Check 'KEEP control: an existing project is found on both opens' (((Proj (Ctx $kept 0)) -like '*\Kept.dproj') -and ((Proj (Ctx $kept 1)) -like '*\Kept.dproj')) "first=$(Proj (Ctx $kept 0)) second=$(Proj (Ctx $kept 1))"
$env:DRAGLINT_CONTEXT_DEFAULTS = $null; $env:DRAGLINT_LSP_REINDEX_EXE = $null
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed) { exit 1 }
