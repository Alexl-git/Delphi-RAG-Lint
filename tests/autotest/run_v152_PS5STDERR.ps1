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
    G2 guard: every ConvertFrom-Json in tests\ is followed by
       | ForEach-Object { $_ } (pwsh's ConvertFrom-Json = PS5's + enumeration,
       so this gives PS5 the pwsh result); G2C positive control.
    B2 PS5 behaviour of the fixed JSON shape and of @(helper) around a helper
       that returns @(...) (PS5 has no .Count on a scalar [pscustomobject]);
       B2C the bare shapes still misbehave under PS5 (control).
    B3 PS5 behaviour of the stderr-to-file shape (merge, append each
       ErrorRecord's text as UTF-8 lines; byte-identical to pwsh's 2>FILE);
       B3C a bare 2>FILE under PS5 still writes ErrorRecord text (control).
    G4 guard: every $p = Start-Process ... -PassThru is followed by
       $null = $p.Handle (PS5 leaves ExitCode $null otherwise); G4C control.
       B4 the cached form reports the exit code under PS5.
    Not covered here (reported to the lane owner): python -c with an embedded
    double quote is fixed per site (literal) or escaped under PS5 (variable);
    runners with #requires -Version 7 are pwsh-only by design.
    G5 guard: a wrap with a pipe in front of it forwards the input with
       "$input | " (piped input reaches the script block, never the native
       command inside it; INT14 found every stdin-fed runner empty); G5C control.
    S5 a stdin-fed `serve` call through the forwarding wrap answers initialize
       (in this shell); S5C the same wrap without "$input | " gets no answer.
#>
[CmdletBinding()]
param([string]$Root = '', [string]$Exe = '')
if (-not $Root) { $Root = "$PSScriptRoot\..\.." }
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
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

function Find-JsonArrayWrap([string]$Text) {
  $tok = $null; $err = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
  if ($err.Count) { return @('PARSE-ERROR') }
  $out = @()
  foreach ($pl in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.PipelineAst] }, $true)) {
    $els = $pl.PipelineElements
    for ($i = 0; $i -lt $els.Count; $i++) {
      $c = $els[$i]
      if ($c -isnot [Management.Automation.Language.CommandAst] -or $c.GetCommandName() -ne 'ConvertFrom-Json') { continue }
      if ($c.Extent.Text -match '-NoEnumerate') { continue }
      if ($i -lt $els.Count - 1 -and $els[$i + 1].Extent.Text -match '^ForEach-Object\s*\{\s*\$_\s*\}$') { continue }
      $out += "line $($c.Extent.StartLineNumber): $($pl.Extent.Text)"
    }
  }
  return $out
}

function Find-UnforwardedPipe([string]$Text) {
  $tok = $null; $err = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
  if ($err.Count) { return @('PARSE-ERROR') }
  $out = @()
  foreach ($sb in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.ScriptBlockExpressionAst] -and $x.Extent.Text.StartsWith($wrapHead) }, $true)) {
    $cmd = $sb.Parent
    if ($cmd -isnot [Management.Automation.Language.CommandAst] -or $cmd.InvocationOperator -ne 'Ampersand') { continue }
    $pl = $cmd.Parent
    if ($pl -isnot [Management.Automation.Language.PipelineAst] -or [array]::IndexOf($pl.PipelineElements, $cmd) -lt 1) { continue }
    $st = $sb.ScriptBlock.EndBlock.Statements
    $last = $st[$st.Count - 1]
    if ($last -is [Management.Automation.Language.PipelineAst] -and $last.PipelineElements[0].Extent.Text -eq '$input') { continue }
    $out += "line $($sb.Extent.StartLineNumber): $($pl.Extent.Text)"
  }
  return $out
}

function Find-UncachedHandle([string]$Text) {
  $tok = $null; $err = $null
  $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tok, [ref]$err)
  if ($err.Count) { return @('PARSE-ERROR') }
  $out = @()
  foreach ($a in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and
                                 $x.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                                 $x.Right -is [Management.Automation.Language.PipelineAst] }, $true)) {
    $c = $a.Right.PipelineElements[0]
    if ($c -isnot [Management.Automation.Language.CommandAst] -or $c.GetCommandName() -ne 'Start-Process') { continue }
    if (-not ($c.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'PassThru' })) { continue }
    if ($a.Parent -isnot [Management.Automation.Language.StatementBlockAst] -and $a.Parent -isnot [Management.Automation.Language.NamedBlockAst]) { continue }
    $after = $Text.Substring($a.Extent.EndOffset, [Math]::Min(60, $Text.Length - $a.Extent.EndOffset))
    if ($after -notmatch ('^\s*;?\s*\$null\s*=\s*' + [regex]::Escape($a.Left.Extent.Text) + '\.Handle')) {
      $out += "line $($a.Extent.StartLineNumber): $($a.Left.Extent.Text) = Start-Process ... -PassThru"
    }
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
    foreach ($u in (@(Find-Unwrapped $t))) { $bad += "$($f.FullName.Substring($Root.Length)) $u" }
  }
  Check "G no unwrapped redirected-stderr native call in tests\ ($($files.Count) scripts scanned)" ($bad.Count -eq 0) (($bad | Select-Object -First 10) -join "`n      ")

  # ---- GC: positive control -------------------------------------------------
  $ctl = @(Find-Unwrapped "`$x = & `$Exe index a --db b 2>&1`r`n& { `$ErrorActionPreference = 'Continue'; & `$Exe y 2>`$null }`r`n")
  Check 'GC the scan flags an unwrapped call and only that one' (@($ctl).Count -eq 1 -and "$ctl" -match 'line 1') "$ctl"

  # ---- G2: @(<x> | ConvertFrom-Json) ---------------------------------------
  # PS5 ConvertFrom-Json emits a JSON array as ONE object, so @(...) around it
  # has Count 1 for [] and for [a,b]; pwsh enumerates. The fixed shape is
  # @((<x> | ConvertFrom-Json) | ForEach-Object { $_ }).
  $bad2 = @()
  foreach ($f in $files) {
    $t = $enc.GetString([IO.File]::ReadAllBytes($f.FullName))
    if ($t -notmatch 'ConvertFrom-Json') { continue }
    foreach ($u in @(Find-JsonArrayWrap $t)) { $bad2 += "$($f.FullName.Substring($Root.Length)) $u" }
  }
  Check 'G2 every ConvertFrom-Json in tests\ is followed by ForEach-Object { $_ } (or says -NoEnumerate)' ($bad2.Count -eq 0) (($bad2 | Select-Object -First 10) -join "`n      ")
  $ctl2 = @(Find-JsonArrayWrap ("`$a = @(`$o | ConvertFrom-Json)`r`n`$b = `$o | ConvertFrom-Json | Where-Object { `$_ }`r`n" +
                                "`$c = `$o | ConvertFrom-Json | ForEach-Object { `$_ }`r`n`$d = `$o | ConvertFrom-Json -NoEnumerate`r`n"))
  Check 'G2C the scan flags the two bare shapes and neither fixed one' ($ctl2.Count -eq 2 -and "$ctl2" -match 'line 1' -and "$ctl2" -match 'line 2') "$ctl2"

  # ---- G4: Start-Process -PassThru caches the handle ------------------------
  $bad4 = @()
  foreach ($f in $files) {
    $t = $enc.GetString([IO.File]::ReadAllBytes($f.FullName))
    if ($t -notmatch 'Start-Process') { continue }
    foreach ($u in @(Find-UncachedHandle $t)) { $bad4 += "$($f.FullName.Substring($Root.Length)) $u" }
  }
  Check 'G4 every $p = Start-Process ... -PassThru in tests\ is followed by $null = $p.Handle' ($bad4.Count -eq 0) (($bad4 | Select-Object -First 10) -join "`n      ")
  $ctl4 = @(Find-UncachedHandle "`$p = Start-Process cmd -PassThru`r`n`$q = Start-Process cmd -PassThru; `$null = `$q.Handle`r`n")
  Check 'G4C the scan flags the uncached form and not the cached one' ($ctl4.Count -eq 1 -and "$ctl4" -match 'line 1') "$ctl4"

  # ---- G5: piped wraps forward their input ---------------------------------
  $bad5 = @()
  foreach ($f in $files) {
    $t = $enc.GetString([IO.File]::ReadAllBytes($f.FullName))
    if (-not $t.Contains($wrapHead)) { continue }
    foreach ($u in @(Find-UnforwardedPipe $t)) { $bad5 += "$($f.FullName.Substring($Root.Length)) $u" }
  }
  Check 'G5 every piped wrap in tests\ forwards its input ($input | <native call>)' ($bad5.Count -eq 0) (($bad5 | Select-Object -First 10) -join "`n      ")
  $ctl5 = @(Find-UnforwardedPipe ("`$a = `$r | & { `$ErrorActionPreference = 'Continue'; & `$Exe serve 2>`$null }`r`n" +
                                  "`$b = `$r | & { `$ErrorActionPreference = 'Continue'; `$input | & `$Exe serve 2>`$null }`r`n" +
                                  "`$c = & { `$ErrorActionPreference = 'Continue'; & `$Exe lint x 2>`$null }`r`n"))
  Check 'G5C the scan flags the unforwarded piped wrap only' ($ctl5.Count -eq 1 -and "$ctl5" -match 'line 1') "$ctl5"

  # ---- S5 / S5C: a stdin-fed serve call through the wrap -------------------
  if (-not (Test-Path -LiteralPath $Exe)) {
    Check 'S5 engine present for the stdin probe' $false "missing: $Exe"
  } else {
    $sDir = Join-Path $env:TEMP "ps5stderr_s5_$PID"
    [void][IO.Directory]::CreateDirectory($sDir)
    try {
      [IO.File]::WriteAllText((Join-Path $sDir 'U1.pas'), "unit U1;`r`n`r`ninterface`r`n`r`nprocedure P;`r`n`r`nimplementation`r`n`r`nprocedure P;`r`nbegin`r`nend;`r`n`r`nend.`r`n", [Text.Encoding]::ASCII)
      $sDb = Join-Path $sDir 's5.sqlite'
      $null = & { $ErrorActionPreference = 'Continue'; & $Exe index $sDir --db $sDb 2>&1 | ForEach-Object { "$_" } }
      $req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
      $fwd = $req | & { $ErrorActionPreference = 'Continue'; $input | & $Exe serve --db $sDb 2>$null } | Out-String
      Check 'S5 the forwarding wrap feeds serve: initialize is answered' ($fwd -match '"id"\s*:\s*1') "out: [$($fwd.Trim())]"
      # The control's native call would read the HOST stdin, so run it in a child
      # of this same shell with stdin redirected from an empty file and a timeout.
      $ctlPs = Join-Path $sDir 'ctl.ps1'
      $ctlIn = Join-Path $sDir 'empty.in'
      $ctlOut = Join-Path $sDir 'ctl.out'
      [IO.File]::WriteAllText($ctlIn, '')
      [IO.File]::WriteAllText($ctlPs, ("param([string]`$Exe, [string]`$Db)`r`n`$req = '" + $req + "'`r`n" +
        "`$o = `$req | & { `$ErrorActionPreference = 'Continue'; & `$Exe serve --db `$Db 2>`$null } | Out-String`r`n" +
        "'CTL-OUT [' + `$o.Trim() + ']'`r`n"), [Text.Encoding]::ASCII)
      $me = (Get-Process -Id $PID).Path
      $cp = Start-Process -FilePath $me -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ctlPs, '-Exe', $Exe, '-Db', $sDb) `
              -RedirectStandardInput $ctlIn -RedirectStandardOutput $ctlOut -NoNewWindow -PassThru; $null = $cp.Handle
      if (-not $cp.WaitForExit(60000)) { try { $cp.Kill() } catch { } }
      $drop = if (Test-Path -LiteralPath $ctlOut) { [IO.File]::ReadAllText($ctlOut) } else { '' }
      Check 'S5C control: without $input the native call gets no request, no answer' (($drop -match 'CTL-OUT \[') -and ($drop -notmatch '"id"\s*:\s*1')) "out: [$($drop.Trim())]"
    } finally {
      if ([IO.Directory]::Exists($sDir)) { [IO.Directory]::Delete($sDir, $true) }
    }
  }

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
"JSON-FIXED " + @(('[]' | ConvertFrom-Json) | ForEach-Object { $_ }).Count + " " + @(('[{"a":1},{"a":2}]' | ConvertFrom-Json) | ForEach-Object { $_ }).Count
"JSON-BARE " + @('[{"a":1},{"a":2}]' | ConvertFrom-Json).Count
function One { return @([pscustomobject]@{ a = 1 }) }
"COUNT-FIXED " + @(One).Count + " BARE [" + (One).Count + "]"
$err = Join-Path $env:TEMP "ps5stderr_b3_$PID.txt"
$o3 = & { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($err); [IO.File]::WriteAllText($dlErrFile, ''); & cmd /c "echo o1& echo e1 1>&2" 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }
"ERRFILE-FIXED [" + ([IO.File]::ReadAllText($err) -replace "`r`n", '|') + "] OUT [" + ($o3 -join '|') + "]"
$null = & { $ErrorActionPreference = 'Continue'; & cmd /c "echo e1 1>&2" 2>$err }
"ERRFILE-BARE-HAS-RECORD-TEXT " + ([IO.File]::ReadAllText($err) -match 'CategoryInfo|NativeCommandError')
[IO.File]::Delete($err)
$p4 = Start-Process cmd -ArgumentList '/c', 'exit 3' -NoNewWindow -PassThru; $null = $p4.Handle
$null = $p4.WaitForExit(30000)
"EXIT-FIXED [" + $p4.ExitCode + "]"
'@
    [IO.File]::WriteAllText($probe, $body.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
    try {
      $r = (& $ps5 -NoProfile -ExecutionPolicy Bypass -File $probe) -join "`n"
    } finally { [IO.File]::Delete($probe) }
    Check 'B wrapped call survives stderr under PS5 and yields plain text' ($r -match 'WRAPPED-OK \[out-line \|err-line \]') $r
    Check 'BC control: the unwrapped call still throws under PS5' ($r -match 'UNWRAPPED-THREW') $r
    Check 'B2 fixed shapes under PS5: JSON [] -> 0, [a,b] -> 2; @(helper) of one object -> 1' ($r -match 'JSON-FIXED 0 2' -and $r -match 'COUNT-FIXED 1 ') $r
    Check 'B2C control: under PS5 the bare JSON shape gives 1 for [a,b] and a scalar object has no Count' ($r -match 'JSON-BARE 1' -and $r -match 'BARE \[\]') $r
    Check 'B3 the stderr-to-file shape writes the plain stderr lines under PS5 and keeps stdout' ($r -match 'ERRFILE-FIXED \[e1 ?\|\] OUT \[o1\]') $r
    Check 'B3C control: a bare 2>FILE under PS5 writes ErrorRecord text' ($r -match 'ERRFILE-BARE-HAS-RECORD-TEXT True') $r
    Check 'B4 Start-Process -PassThru with the handle cached reports the exit code under PS5' ($r -match 'EXIT-FIXED \[3\]') $r
  }
} catch {
  Check 'runner raised' $false $_.Exception.Message
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
