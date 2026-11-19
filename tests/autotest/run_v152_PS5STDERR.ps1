<#
  run_v152_PS5STDERR.ps1 -- Windows PowerShell 5.1 parity for redirected native stderr.

  THE DEFECT. Under $ErrorActionPreference = 'Stop', Windows PowerShell 5.1 turns
  every line a NATIVE exe writes to a REDIRECTED stderr (2>&1, 2>$null, 2>file,
  *>...) into a terminating NativeCommandError. drag-lint prints progress on stderr
  ("control channel listening on ..."), so a runner died on its first `index`
  call under PS5 while pwsh 7 ran it green. Measured on a 30-runner sample at
  c92bfb2b5: 3 of 30 gave the same result under both shells.

  A second PS5 difference: a merged stderr line arrives as an ErrorRecord, and
  Out-String renders it with "At line / CategoryInfo" noise, so text assertions
  over `2>&1 | Out-String` fail even when nothing throws.

  THE FIX (applied mechanically to tests\): every such call is wrapped as
      & { $ErrorActionPreference = 'Continue'; <call> 2>&1 | ForEach-Object { "$_" } }
  (the ForEach only where stderr is MERGED into the output; native stdout lines
  are already strings, so it is the identity on stdout and gives pwsh's text for
  stderr). Files that deliberately split streams by `-is [ErrorRecord]` keep the
  records.

  CHECKS
    G  guard: no test script holds an UNWRAPPED redirected-stderr native call
       (AST scan; a scriptblock target or a non-native bare command is exempt).
    GC positive control: the same scan flags a synthetic unwrapped call.
    B  behaviour under powershell.exe: the wrapped shape survives a stderr line
       and yields the plain text; BC the unwrapped shape still throws (control).
#>
[CmdletBinding()]
param([string]$Root = '')
if (-not $Root) { $Root = "$PSScriptRoot\..\.." }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}

$bareNative = '^(cmd|python|python3|pwsh|powershell|git|hg|reg|node|where|taskkill|tasklist|robocopy|icacls|msbuild|.*\.exe)$'
$wrapHead   = '{ $ErrorActionPreference = ''Continue''; '

function Find-Unwrapped([string]$Text) {
  $tok = $null; $err = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
  if ($err.Count) { return @('PARSE-ERROR') }
  $sbVars = @{}
  foreach ($p in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.ParameterAst] }, $true)) {
    if ($p.StaticType -eq [scriptblock]) { $sbVars[$p.Name.VariablePath.UserPath.ToLower()] = 1 }
  }
  foreach ($a in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] }, $true)) {
    if ($a.Left -is [Management.Automation.Language.VariableExpressionAst] -and $a.Right.Extent.Text.TrimStart().StartsWith('{')) {
      $sbVars[$a.Left.VariablePath.UserPath.ToLower()] = 1
    }
  }
  $out = @()
  $hits = $ast.FindAll({ param($x) $x -is [Management.Automation.Language.CommandAst] -and
                         ($x.Redirections | Where-Object { $_.FromStream -in 'Error','All' }) }, $true)
  foreach ($h in $hits) {
    $e0 = $h.CommandElements[0]
    if ($h.InvocationOperator -eq 'Dot') { continue }
    if ($h.InvocationOperator -eq 'Unknown') {
      if ($e0 -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $e0.Value -notmatch $bareNative) { continue }
    } else {
      if ($e0 -is [Management.Automation.Language.ScriptBlockExpressionAst]) { continue }
      if ($e0 -is [Management.Automation.Language.VariableExpressionAst] -and
          $sbVars.ContainsKey($e0.VariablePath.UserPath.ToLower())) { continue }
    }
    $sb = $h.Parent
    while ($sb -and $sb -isnot [Management.Automation.Language.ScriptBlockExpressionAst]) { $sb = $sb.Parent }
    if ($sb -and $sb.Extent.Text.StartsWith($wrapHead)) { continue }
    $out += "line $($h.Extent.StartLineNumber): $($h.Extent.Text)"
  }
  return $out
}

try {
  # ---- G: the tree ----------------------------------------------------------
  $enc = [Text.Encoding]::GetEncoding(28591)
  $bad = @()
  $files = Get-ChildItem (Join-Path $Root 'tests') -Recurse -Filter *.ps1
  foreach ($f in $files) {
    $t = $enc.GetString([IO.File]::ReadAllBytes($f.FullName))
    if ($t -notmatch '[2*]>') { continue }
    foreach ($u in (Find-Unwrapped $t)) { $bad += "$($f.FullName.Substring($Root.Length)) $u" }
  }
  Check "G no unwrapped redirected-stderr native call in tests\ ($($files.Count) scripts scanned)" ($bad.Count -eq 0) (($bad | Select-Object -First 10) -join "`n      ")

  # ---- GC: positive control -------------------------------------------------
  $ctl = Find-Unwrapped "`$x = & `$Exe index a --db b 2>&1`r`n& { `$ErrorActionPreference = 'Continue'; & `$Exe y 2>`$null }`r`n"
  Check 'GC the scan flags an unwrapped call and only that one' (@($ctl).Count -eq 1 -and "$ctl" -match 'line 1') "$ctl"

  # ---- B / BC: behaviour under Windows PowerShell 5.1 -----------------------
  $ps5 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
  if (-not (Test-Path $ps5)) {
    Write-Host '[SKIP] B/BC powershell.exe not present on this machine'
  } else {
    $probe = Join-Path $env:TEMP "ps5stderr_probe_$PID.ps1"
    $body = @'
$ErrorActionPreference = 'Stop'
try {
  $w = & { $ErrorActionPreference = 'Continue'; & cmd /c "echo out-line & echo err-line 1>&2" 2>&1 | ForEach-Object { "$_" } } | Out-String
  "WRAPPED-OK [" + (($w -split "`r?`n" | Where-Object { $_ }) -join '|') + "]"
} catch { "WRAPPED-THREW" }
try { $u = & cmd /c "echo err-line 1>&2" 2>&1; "UNWRAPPED-OK" } catch { "UNWRAPPED-THREW" }
'@
    [IO.File]::WriteAllText($probe, $body.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
    try {
      $r = (& $ps5 -NoProfile -ExecutionPolicy Bypass -File $probe) -join "`n"
    } finally { [IO.File]::Delete($probe) }
    Check 'B wrapped call survives stderr under PS5 and yields plain text' ($r -match 'WRAPPED-OK \[out-line \|err-line \]') $r
    Check 'BC control: the unwrapped call still throws under PS5' ($r -match 'UNWRAPPED-THREW') $r
  }
} catch {
  Check 'runner raised' $false $_.Exception.Message
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
