# drag-lint LSP hover CALL-SITE resolution regression test.
#
# BUG (user-reported, live IDE): hovering the `Create` in a QUALIFIED call like
# `TGroup.Create(...)` showed an UNRELATED same-named symbol (e.g. a library
# `Abccompf.*.Create`/`Result` that merely sorts first alphabetically), not the
# `Create` of the type actually named at the cursor.
#
# ROOT CAUSE: HandleHover picked the hovered symbol by BARE NAME
# (FindSymbolsByExactName) + a disambiguation loop that only matches when the
# cursor is ON a candidate's DECLARATION or IMPLEMENTATION. At a CALL SITE nothing
# matches -> it fell back to Symbols[0] = an arbitrary same-named symbol, ignoring
# the `TGroup.` qualifier -- even though TTypeAtResolver already resolves it. It
# also resolved against the FIRST store holding the name (a library) rather than
# the store that OWNS the hovered file.
#
# FIX: when the cursor is NOT on a decl/impl, anchor resolution to the store that
# owns the hovered file and use TTypeAtResolver (qualifier -> member) to select the
# symbol; only override when it lands on the SAME identifier hovered.
#
# The fixture declares TWO constructors named Create; the WRONG one (TAaaThing,
# alphabetically first, carrying a doc comment so the old code takes the
# doc-content branch that skipped TTypeAtResolver) and the RIGHT one
# (TZzzGroup.Create, with a distinctive AValue param). We hover the `Create` in
# `TZzzGroup.Create(42)` and assert the RIGHT one comes back.
#
# Usage: pwsh -File tests/autotest/run_hover_callsite.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-hover-callsite",
    [string] $Py = "C:\Python314\python.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $s = if ($Ok) {'PASS'} else {'FAIL'}
    $c = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
    if (-not $Ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Py))  { $Py = 'python' }  # fall back to PATH
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- fixture: two Create constructors; call site targets the SECOND one ---
$src = "$WorkDir\HoverCallSite.pas"
@'
unit HoverCallSite;

interface

type
  TAaaThing = class
  public
    /// <summary>WRONG hit: alphabetically-first Create that must NOT be shown.</summary>
    constructor Create;
  end;

  TZzzGroup = class
  public
    constructor Create(AValue: Integer);
  end;

procedure UseIt;

implementation

constructor TAaaThing.Create;
begin
end;

constructor TZzzGroup.Create(AValue: Integer);
begin
end;

procedure UseIt;
var
  G: TZzzGroup;
begin
  G := TZzzGroup.Create(42);
end;

end.
'@ | Set-Content $src -Encoding ascii

$db = "$WorkDir\hovercallsite.sqlite"
& $Exe index $WorkDir --db $db | Out-Null
Check 'fixture db built' (Test-Path $db)

# --- build the LSP frame stream: initialize, hover at the call site, exit ---
# Call site is line 33 (1-based) "  G := TZzzGroup.Create(42);". LSP is 0-based:
# line 32. `Create` occupies 0-based chars 17..22; char 19 sits inside it.
$uri = 'file:///' + ($src -replace '\\','/')
$inFile  = "$WorkDir\frames.bin"
$outFile = "$WorkDir\out.txt"
$errFile = "$WorkDir\err.txt"
$pyGen = @"
import sys, json
def frame(m):
    b = json.dumps(m, separators=(',',':')).encode('utf-8')
    return ('Content-Length: %d\r\n\r\n' % len(b)).encode('utf-8') + b
uri = r'''$uri'''
msgs = [
    {'jsonrpc':'2.0','id':1,'method':'initialize','params':{'capabilities':{}}},
    {'jsonrpc':'2.0','id':2,'method':'textDocument/hover','params':{
        'textDocument':{'uri':uri}, 'position':{'line':32,'character':19}}},
    {'jsonrpc':'2.0','method':'exit'},
]
with open(r'''$inFile''','wb') as f:
    for m in msgs: f.write(frame(m))
"@
$pyFile = "$WorkDir\gen.py"
$pyGen | Set-Content $pyFile -Encoding ascii
& $Py $pyFile
Check 'lsp frames generated' (Test-Path $inFile)

Start-Process -FilePath $Exe -ArgumentList @('lsp','--db',$db) `
      -RedirectStandardInput $inFile -RedirectStandardOutput $outFile `
      -RedirectStandardError $errFile -NoNewWindow -Wait | Out-Null
$out = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { '' }

# The hover reply's markdown is JSON-escaped inside the response; a substring
# match on the raw stdout is sufficient and robust to framing.
Check 'resolves TZzzGroup.Create'      ($out -match 'TZzzGroup\.Create') $out
Check 'shows the AValue param'         ($out -match 'AValue')
Check 'does NOT show the wrong Create' (-not ($out -match 'WRONG hit')) `
      $(if ($out -match 'WRONG hit') { 'still resolving TAaaThing.Create' } else { '' })
Check 'does NOT resolve TAaaThing'     (-not ($out -match 'TAaaThing\.Create'))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
