<#
  PENDING -- named `pending_*` so the battery's `run_*.ps1` discovery does NOT
  pick it up. Stage 1 is not built yet, so this is RED BY DESIGN; a test for an
  unbuilt feature belongs outside the battery, not inside it as a standing red.
  RENAME TO run_* IN THE SAME COMMIT THAT LANDS THE FEATURE.

  Verified RED against the 2026-08-25 build (assertions 1 and 2 fail, both
  positive controls pass), so it discriminates.

  pending_exception_class_fits.ps1 -- STAGE 1 of exception-class-unit: when a project
  names its exceptions unit, `raise-bare-exception` must report WHICH existing
  exception class already covers this message, or say plainly that none does.

  THE RULING IT ENCODES (owner, 2026-08-25): "fits" = NORMALIZED MESSAGE MATCH.
  The raise site's STATIC message is compared against the known message of each
  existing exception class, normalized for casing and stopwords, so

      'Invoice not found'      (the message EInvoiceNotFound is raised with)
      'Invoice was not found'  (the bare raise under test)

  report the SAME class. A class-name match would report "none exists" for
  exactly this pair -- which is the near-duplicate collision design question 1 is
  about -- and stage 3 would then generate a second class for it.

  WHAT "THE KNOWN MESSAGE OF AN EXISTING CLASS" MEANS, since the ruling leaves it
  implicit and it is the only part a fixture can get wrong silently: it is the
  literal at that class's OWN raise sites, read from the AST. There is nowhere
  else for it to come from -- a class declaration carries no message. So the
  fixture must contain a real `raise EInvoiceNotFound.Create('Invoice not
  found')`, and it does; without it the class has no message and NOTHING should
  match, which is what control (b) pins.

  READ THE AST, NOT THE TEXT. A regex over the finding's line is the method that
  produced the 2026-08-17 measurement this note retracted: it recovered 80 of 139
  sites and reported the 59 it could not parse as "sites with no literal", i.e.
  wrote an extractor limitation up as a property of the code. Doubled-quote
  escapes and multi-line raises are what defeat it, so THIS FIXTURE CONTAINS BOTH
  (see uOrders.pas: a doubled-quote message, and a raise split across lines).

  THE FIXTURE:

    exc\uExceptions.pas   EInvoiceNotFound = class(Exception)
                          EPrinterOffline  = class(Exception)
    app\uOrders.pas       raise EInvoiceNotFound.Create('Invoice not found')
                                                        <- gives the class its message
                          raise Exception.Create('Invoice was not found')
                                                        <- 1. MUST report EInvoiceNotFound
                          raise Exception.Create('Disk quota exceeded on '' + S)
                                                        <- 2. matches nothing -> "none"
                          a raise split across lines     <- defeats a line regex

  WHAT IS ASSERTED:

    1  with the exceptions unit configured, the near-duplicate reports EInvoiceNotFound
    2  a message matching nothing says so explicitly, and names NO class
    3  POSITIVE CONTROL: with no `exceptions` KEY, the message is the plain rule
       text, byte-identical to today -- a project that never opted in must not
       change at all. Expressed with an explicit key-less --config, NOT by
       omitting --config: since 2026-08-28 lint-all discovers a config from the
       --db path, so omitting the flag no longer means "unconfigured".
    4  POSITIVE CONTROL: the multi-line raise is still FOUND (a line-oriented
       implementation silently drops it, and a dropped finding reads as "clean")

  3 AND 4 ARE LOAD-BEARING. Without 3, an implementation that enriches every run
  passes while silently changing behaviour for every project that never opted in.
  Without 4, the cheap regex implementation the note warns against passes.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_exc_fits'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $scratch 'exc') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch 'app') | Out-Null

function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}

WriteAscii (Join-Path $scratch 'exc\uExceptions.pas') @'
unit uExceptions;

interface

uses
  SysUtils;

type
  EInvoiceNotFound = class(Exception)
  end;

  EPrinterOffline = class(Exception)
  end;

implementation

end.
'@

# NOTE the two shapes a line-regex cannot read: a doubled-quote escape, and a
# raise whose Create( sits on a different line from the raise keyword.
WriteAscii (Join-Path $scratch 'app\uOrders.pas') @'
unit uOrders;

interface

procedure LoadInvoice(const AId: Integer);
procedure CheckQuota(const S: string);
procedure Split(const AId: Integer);

implementation

uses
  SysUtils, uExceptions;

procedure LoadInvoice(const AId: Integer);
begin
  if AId = 0 then
    raise EInvoiceNotFound.Create('Invoice not found');
  if AId < 0 then
    raise Exception.Create('Invoice was not found');
end;

procedure CheckQuota(const S: string);
begin
  raise Exception.Create('Disk quota exceeded on ''' + S + '''');
end;

procedure Split(const AId: Integer);
begin
  raise Exception.Create(
    'Invoice was not found');
end;

end.
'@

$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecApp", "db": "app.sqlite", "include": ["exc", "app"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

$db = Join-Path $scratch 'out\app.sqlite'

# The lint config that names the exceptions unit. Absent = today's behaviour.
$lintCfg = Join-Path $scratch 'drag-lint-lint.json'
@"
{
  "exceptions": { "unit": "uExceptions" }
}
"@ | Set-Content $lintCfg -Encoding ascii

function BareRaiseLines([string]$Out) {
  ($Out -split "`r?`n") | Where-Object { $_ -match 'raise-bare-exception' }
}

Push-Location C:\TEMP
try {
  & $exePath index --all --config $cfg --only SecApp --jobs 1 2>&1 | Out-Null
  Check '0. SANITY: the section DB exists' (Test-Path $db)

  # --- WITH the exceptions unit configured ---------------------------------
  $withCfg = (& $exePath lint-all --db $db --config $lintCfg --quiet 2>&1 | Out-String)
  $lines   = @(BareRaiseLines $withCfg)

  # -match against a COLLECTION returns the matching ELEMENTS, not a boolean, and
  # Check's [int]$ok cast then throws. Collapse to one string per assertion first.
  $allLines = ($lines -join "`n")

  Check '1. the near-duplicate message reports EInvoiceNotFound' `
        ($allLines -match 'EInvoiceNotFound') `
        "'Invoice was not found' must normalize onto 'Invoice not found'"

  Check '2. a message matching nothing says so, and names no class' `
        ($allLines -match '(?i)no existing exception class') `
        'must not silently pick the nearest class'

  Check '4. POSITIVE CONTROL: the MULTI-LINE raise is still reported' `
        (@($lines).Count -ge 3) `
        "a line-oriented implementation drops it, and a dropped finding reads as 'clean'"

  # --- WITHOUT the exceptions key: today's behaviour, unchanged ------------
  # THIS USED TO OMIT --config ENTIRELY, and that stopped meaning "no config"
  # on 2026-08-28: lint-all now anchors config discovery to the --db path
  # (<project>\_D-RAG\<name>.sqlite -> walk up), so a bare run FINDS the
  # fixture's own drag-lint-lint.json sitting in $scratch. Both runs were then
  # configured, both were enriched, and this control started failing -- against
  # an engine that had just been FIXED.
  #
  # Before that fix, a project's config governed a lint-all run only when the
  # operator happened to be standing in that project's directory. Measured on
  # ORM3: the per-file verb reported 12 rule ids lint-all did not, every one of
  # them in ORM3's own `enabled` list.
  #
  # So the control is expressed against the thing it was always about -- the
  # ABSENCE OF THE `exceptions` KEY, not the absence of a file. An explicit
  # --config with no such key is the strongest form: it holds whatever the
  # discovery rules do next, and an implementation that enriches every run still
  # fails it, which is the load-bearing property named at the top of this file.
  $noExcCfg = Join-Path $scratch 'no-exceptions-lint.json'
  '{ "_comment": "deliberately carries no exceptions key" }' | Set-Content $noExcCfg -Encoding ascii
  $noCfg     = (& $exePath lint-all --db $db --config $noExcCfg --quiet 2>&1 | Out-String)
  $noCfgLine = [string](@(BareRaiseLines $noCfg) | Select-Object -First 1)
  Check '3. POSITIVE CONTROL: with no exceptions KEY the message is the plain rule text' `
        (($noCfgLine -match 'raise a specific subclass') -and ($noCfgLine -notmatch 'EInvoiceNotFound') -and ($noCfgLine -notmatch '(?i)no existing exception class')) `
        'a project that never opted in must see byte-identical output'

  if ($fail) {
    Write-Host '      --- raise-bare-exception lines WITH config ---' -ForegroundColor DarkGray
    $lines | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
    Write-Host '      --- WITHOUT config ---' -ForegroundColor DarkGray
    (BareRaiseLines $noCfg) | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
