<#
  run_utf8_output.ps1 -- --utf8 / DRAGLINT_UTF8=1 write stdout as UTF-8
  (Gitea #35).

  WHY. Text goes out in the ANSI code page, so source text from a cp1252 unit
  (slice, context, find-callers --context, hover, --json) left as raw cp1252
  bytes: an agent reading UTF-8 saw "vari?veis" and the JSON was not valid
  UTF-8. The default stays ANSI -- the IDE plugin (ProcRun) and the convrules
  editor decode the output that way -- so UTF-8 is opt-in.

  Checks:
    U1  default: slice prints the cp1252 byte (unchanged), not UTF-8
    U2  --utf8: slice prints valid UTF-8 with the accented text
    U3  DRAGLINT_UTF8=1: the same without the flag
    U4  find-callers --context --json --utf8: valid UTF-8, parses, carries the text
    U5  serve --utf8 (MCP): replies stay valid UTF-8, byte-identical to serve
        without it (the server writes UTF-8 bytes itself; no double encoding)

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_utf8_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
# cp1252 == Latin-1 for every character used here (a-acute, c-cedilla, a-tilde)
function Write-Cp1252($p, $t) { [IO.File]::WriteAllBytes($p, [Text.Encoding]::Latin1.GetBytes((($t -replace "`r`n", "`n") -replace "`n", "`r`n"))) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
$aa = [char]0xE1; $cc = [char]0xE7; $at = [char]0xE3
$word = "vari$($aa)veis"
$call = "fun$($cc)$($at)o"

Write-Cp1252 (Join-Path $src 'uAcc.pas') @"
unit uAcc;

interface

function Hello: string;

implementation

function Hello: string;
begin
  Result:= '$word';
end;

end.
"@
Write-Cp1252 (Join-Path $src 'uMain.pas') @"
unit uMain;

interface

procedure Go;

implementation

uses
  uAcc;

procedure Go;
var
  S: string;
begin
  // $call
  S:= Hello;
end;

end.
"@
Write-Cp1252 (Join-Path $src 'P.dpr') @'
program P;

uses
  uAcc, uMain;

begin
end.
'@
$db = Join-Path $WorkDir 'p.sqlite'
$env:DRAGLINT_RULE_CACHE = '0'
$idx = & $exePath index --project (Join-Path $src 'P.dpr') --db $db 2>&1 | Out-String
$env:DRAGLINT_RULE_CACHE = $null
Check 'SANITY: fixture indexed' ($LASTEXITCODE -eq 0) $idx

$strict = New-Object Text.UTF8Encoding($false, $true)
# Runs the engine with stdout redirected to a file and returns the RAW bytes.
function Invoke-Raw([string[]]$ArgList, [string]$Tag, [string]$StdinFile = '') {
  $out = Join-Path $WorkDir "$Tag.out"
  $err = Join-Path $WorkDir "$Tag.err"
  $sp = @{ FilePath = $exePath; ArgumentList = $ArgList; WorkingDirectory = $WorkDir; NoNewWindow = $true; PassThru = $true
           RedirectStandardOutput = $out; RedirectStandardError = $err }
  if ($StdinFile) { $sp.RedirectStandardInput = $StdinFile }
  $p = Start-Process @sp
  if (-not $p.WaitForExit(60000)) { $p.Kill() }
  if (Test-Path $out) { , [IO.File]::ReadAllBytes($out) } else { , [byte[]]@() }
}
function Has-Bytes([byte[]]$Hay, [byte[]]$Needle) {
  for ($i = 0; $i -le $Hay.Length - $Needle.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $Needle.Length; $j++) { if ($Hay[$i + $j] -ne $Needle[$j]) { $ok = $false; break } }
    if ($ok) { return $true }
  }
  $false
}
function Utf8-Text([byte[]]$B) { try { $strict.GetString($B) } catch { $null } }
$qdb = "`"$db`""

# --- U1: the default is unchanged ------------------------------------------------
$env:DRAGLINT_UTF8 = $null
$b1 = Invoke-Raw @('slice', '--qname', 'uAcc.Hello', '--db', $qdb) 'u1'
Check 'U1 default: slice prints the cp1252 byte, not UTF-8' ((Has-Bytes $b1 ([byte[]](0x72, 0x69, 0xE1, 0x76))) -and -not (Has-Bytes $b1 ([byte[]](0xC3, 0xA1)))) ("{0} byte(s)" -f $b1.Length)

# --- U2/U3: --utf8 and DRAGLINT_UTF8=1 -------------------------------------------
$b2 = Invoke-Raw @('slice', '--qname', 'uAcc.Hello', '--db', $qdb, '--utf8') 'u2'
$t2 = Utf8-Text $b2
Check 'U2 --utf8: slice prints valid UTF-8 with the accented text' (($null -ne $t2) -and $t2.Contains($word)) ("{0} byte(s); decoded: {1}" -f $b2.Length, ($null -ne $t2))

$env:DRAGLINT_UTF8 = '1'
$b3 = Invoke-Raw @('slice', '--qname', 'uAcc.Hello', '--db', $qdb) 'u3'
$env:DRAGLINT_UTF8 = $null
$t3 = Utf8-Text $b3
Check 'U3 DRAGLINT_UTF8=1: the same without the flag' (($null -ne $t3) -and $t3.Contains($word)) ("{0} byte(s); decoded: {1}" -f $b3.Length, ($null -ne $t3))

# --- U4: --json carrying source text ---------------------------------------------
$b4 = Invoke-Raw @('query', 'find-callers', '--name', 'Hello', '--context', '2', '--json', '--utf8', '--db', $qdb) 'u4'
$t4 = Utf8-Text $b4
$j4 = $null
if ($null -ne $t4) { try { $j4 = $t4 | ConvertFrom-Json } catch { $j4 = $null } }
Check 'U4 find-callers --context --json --utf8: valid UTF-8, parses, carries the text' (($null -ne $j4) -and $t4.Contains($call)) ("decoded: {0}; parsed: {1}" -f ($null -ne $t4), ($null -ne $j4))

# --- U5: MCP serve under --utf8 ----------------------------------------------------
$in = Join-Path $WorkDir 'mcp.in.jsonl'
$req = @(
  '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}',
  '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_slice","arguments":{"qname":"uAcc.Hello"}}}'
)
[IO.File]::WriteAllText($in, (($req -join "`n") + "`n"), [Text.Encoding]::ASCII)
$m0 = Invoke-Raw @('serve', '--db', $qdb) 'm0' $in
$m1 = Invoke-Raw @('serve', '--db', $qdb, '--utf8') 'm1' $in
$tm = Utf8-Text $m1
$sliceText = ''
if ($null -ne $tm) {
  foreach ($line in ($tm -split "`n")) {
    if ($line.Trim() -eq '') { continue }
    try { $j = $line | ConvertFrom-Json } catch { continue }
    if ($j.id -eq 1 -and $j.result) { $sliceText = [string]$j.result.content[0].text }
  }
}
Check 'U5 serve --utf8: the reply is valid UTF-8 and carries the text' ($sliceText.Contains($word)) ("decoded: {0}" -f ($null -ne $tm))
Check 'U5 ... byte-identical to serve without --utf8' (($m0.Length -gt 0) -and ([Convert]::ToBase64String($m0) -eq [Convert]::ToBase64String($m1))) ("{0} vs {1} byte(s)" -f $m0.Length, $m1.Length)
}
finally {
  $env:DRAGLINT_UTF8 = $null
  $env:DRAGLINT_RULE_CACHE = $null
  if ($WorkDir -and (Test-Path $WorkDir)) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
