# gate-grammar.ps1 -- regenerate a tree-sitter-delphi13 worktree (root + pure), build its x64 (and x86)
# DLLs, run tree-sitter test on both grammars, and gate the new DLLs against a BASE pair with tsdiff/tserr
# over every list file in -ListDir. 7-bit ASCII, CRLF. pwsh 7.
#
# usage: pwsh -File tools\grammar\gate-grammar.ps1 -Grammar <worktree> -Base <dir with root\ and pure\ base DLLs>
#            -Out <scratch dir> -Tools <dir with tsdiff.exe/tserr.exe> -ListDir <dir of *.txt path lists>
#            [-Step <name>] [-NoGen] [-X86] [-TreeSitter <tree-sitter.exe>] [-VsEnv <_vsenv.bat>]
# Output: <Out>\gate-<Step>.log (one line per step), <Out>\dll\<Step>\{root,pure}\*.dll (x64),
#         <Out>\dll\<Step>-x86\..., <Out>\test-<Step>-{root,pure}.txt, <Out>\gate-<Step>-<grammar>-<list>.tsv,
#         <Out>\tserr-<Step>-<grammar>-<list>.tsv (changed files only). Last log line: GATE_DONE <Step>.
# The gate never writes outside -Out; it does not touch third_party\ or any engine.
param(
  [Parameter(Mandatory)][string]$Grammar,
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Out,
  [Parameter(Mandatory)][string]$Tools,
  [Parameter(Mandatory)][string]$ListDir,
  [string]$Step = 'new',
  [switch]$NoGen,
  [switch]$X86,
  [string]$TreeSitter = 'C:\Projects\tree-sitter-delphi13\node_modules\tree-sitter-cli\tree-sitter.exe',
  [string]$VsEnv = (Join-Path $PSScriptRoot '..\..\build\_vsenv.bat')
)
$ErrorActionPreference = 'Stop'
$inc = Join-Path (Split-Path $TreeSitter -Parent) '..\tree-sitter\vendor\tree-sitter\lib\include'
$inc = [IO.Path]::GetFullPath($inc)
New-Item -ItemType Directory -Force $Out | Out-Null
$L = Join-Path $Out "gate-$Step.log"
function Gate-Log([string]$m) { "$(Get-Date -Format s) $m" | Add-Content $L; $m }
Gate-Log "gate $Step start grammar=$Grammar base=$Base"

if (-not $NoGen) {
  $a = Start-Process $TreeSitter -ArgumentList 'generate' -WorkingDirectory $Grammar -RedirectStandardOutput "$Out\gen-$Step-root.out" -RedirectStandardError "$Out\gen-$Step-root.err" -PassThru -WindowStyle Hidden
  $b = Start-Process $TreeSitter -ArgumentList 'generate' -WorkingDirectory "$Grammar\pure" -RedirectStandardOutput "$Out\gen-$Step-pure.out" -RedirectStandardError "$Out\gen-$Step-pure.err" -PassThru -WindowStyle Hidden
  $a.WaitForExit(); $b.WaitForExit()
  Gate-Log "generate root=$($a.ExitCode) pure=$($b.ExitCode); root: $((Get-Content "$Out\gen-$Step-root.out","$Out\gen-$Step-root.err") -join ' | '); pure: $((Get-Content "$Out\gen-$Step-pure.out","$Out\gen-$Step-pure.err") -join ' | ')"
  if ($a.ExitCode -ne 0 -or $b.ExitCode -ne 0) { Gate-Log "GATE_ABORT $Step generate failed"; exit 1 }
}

$grs = @(
  @('root', 'tree-sitter-delphi13.dll', 'tree_sitter_delphi13', "$Grammar\src"),
  @('pure', 'tree-sitter-delphi13-pure.dll', 'tree_sitter_delphi13_pure', "$Grammar\pure\src"))
$archs = @(@('64', 'X64', "$Step")); if ($X86) { $archs += , @('32', 'X86', "$Step-x86") }
foreach ($ar in $archs) {
  foreach ($gr in $grs) {
    $dll = "$Out\dll\$($ar[2])\$($gr[0])"; New-Item -ItemType Directory -Force $dll | Out-Null
    $log = "$Out\cl-$($ar[2])-$($gr[0]).log"
    $bat = "@echo off`r`ncall `"$VsEnv`" $($ar[0]) >NUL 2>NUL`r`ncd /d `"$dll`"`r`ncl /nologo /O2 /LD /MD /D_CRT_SECURE_NO_WARNINGS /wd4146 /wd4244 /wd4267 /wd4090 /I `"$inc`" `"$($gr[3])\parser.c`" `"$($gr[3])\scanner.c`" /Fe:`"$dll\$($gr[1])`" /link /EXPORT:$($gr[2]) /MACHINE:$($ar[1]) > `"$log`" 2>&1`r`necho CL_EXIT=%errorlevel%>>`"$log`"`r`n"
    [IO.File]::WriteAllText("$Out\b-$($ar[2])-$($gr[0]).bat", $bat, [Text.Encoding]::ASCII)
    Start-Process cmd.exe -ArgumentList '/c', "$Out\b-$($ar[2])-$($gr[0]).bat" -Wait -WindowStyle Hidden
    Gate-Log ("cl $($ar[2]) $($gr[0]): " + ((Get-Content $log) -join ' | '))
  }
}

foreach ($gr in $grs) {
  $dir = if ($gr[0] -eq 'root') { $Grammar } else { "$Grammar\pure" }
  if (-not (Test-Path "$dir\test\corpus")) { Gate-Log "tree-sitter test $($gr[0]): no corpus"; continue }
  New-Item -ItemType Directory -Force "$Out\tslib\$Step-$($gr[0])" | Out-Null
  $env:TREE_SITTER_LIBDIR = "$Out\tslib\$Step-$($gr[0])"
  Push-Location $dir; & $TreeSitter test *> "$Out\test-$Step-$($gr[0]).txt"; $tx = $LASTEXITCODE; Pop-Location
  $fails = (Get-Content "$Out\test-$Step-$($gr[0]).txt") | Where-Object { $_ -match [char]0x2717 }
  Gate-Log "tree-sitter test $($gr[0]) exit=$tx failures=$(@($fails).Count): $($fails -join ' | ')"
}

foreach ($gr in $grs) {
  $old = "$Base\$($gr[0])\$($gr[1])"; $new = "$Out\dll\$Step\$($gr[0])\$($gr[1])"
  foreach ($lst in Get-ChildItem "$ListDir\*.txt") {
    $name = $lst.BaseName
    $tsv = "$Out\gate-$Step-$($gr[0])-$name.tsv"
    $r = & "$Tools\tsdiff.exe" $old $new $gr[2] $lst.FullName $tsv
    $rows = Get-Content $tsv | ForEach-Object { $c = $_ -split "`t"; [pscustomobject]@{ f = $c[0]; o = [int]$c[1]; n = [int]$c[2]; reg = $c[4] } }
    $nf = @($rows | Where-Object { $_.o -eq 0 -and $_.n -eq 1 }); $fx = @($rows | Where-Object { $_.o -eq 1 -and $_.n -eq 0 })
    $changed = @($rows | Where-Object { $_.reg -ne '' -and $null -ne $_.reg })
    Gate-Log "tsdiff $($gr[0]) $name : $r changed=$($changed.Count) newlyFailing=$($nf.Count) fixed=$($fx.Count)$(if ($nf.Count) { ' NEWLY FAILING: ' + (($nf | ForEach-Object { $_.f }) -join ' ; ') })"
    if ($changed.Count) {
      $cl = "$Out\changed-$Step-$($gr[0])-$name.txt"; $changed | ForEach-Object { $_.f } | Set-Content $cl -Encoding ASCII
      & "$Tools\tserr.exe" $old $new $gr[2] $cl "$Out\tserr-$Step-$($gr[0])-$name.tsv" | Out-Null
      $cleanChanged = @(Get-Content "$Out\tserr-$Step-$($gr[0])-$name.tsv" | ForEach-Object { $c = $_ -split "`t"; if ([int]$c[1] -eq 0 -and [int]$c[2] -eq 0) { $c[0] } })
      Gate-Log "tserr $($gr[0]) $name : changed files failing on neither grammar (intended tree changes, inspect): $($cleanChanged.Count)"
    }
  }
}
Gate-Log "GATE_DONE $Step"
