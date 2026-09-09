<#
  run_dfm_object_type_is_searchable.ps1 -- `query --text` must find a DFM
  component's TYPE, not just its property values.

  WHY. Asked on 2026-09-08 while measuring convert-apply:

      drag-lint query --text "TOvcTable" --db Micronite2027.sqlite --source dfm
      -> 0 match(es)

  against a DFM holding 28 `object <name>: TOvcTable` blocks. The DFM text index
  stored property VALUES and component names (`dfm-prop`) and nothing else, so
  the type token on the `object` line was unreachable. "Which forms contain a
  component of type X, and how many?" is the FIRST question anyone asks before a
  component conversion, and the only way to answer it was to read a 942 KB .dfm
  as text -- precisely what the index exists to replace.

  The converter side confirmed they already work around it
  (`ConvRules.FormTypes.ScanDfmTypes` parses the .dfm itself), so nothing was
  blocked -- but the workaround is a second header parser maintained outside the
  engine, which is the cost of the gap rather than a reason to keep it.

  THE CONTROLS:

    C1  property-value search (`dfm-prop`) still works. The new token class must
        be additive; breaking the existing rows to add types would trade one
        gap for another.
    N1  a type that is NOT in the DFM returns nothing. Without this, an
        implementation that indexed every identifier it saw would pass the
        positive check and make --text useless by flooding it.
    N2  the hit is attributed to the right FILE and LINE, not merely present.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_dfmtype_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

Write-Ascii (Join-Path $src 'uTypeForm.pas') @"
unit uTypeForm;

interface

uses
  Vcl.Forms;

type
  TTypeForm = class(TForm)
  public
    procedure Go;
  end;

implementation

{`$R *.dfm}

procedure TTypeForm.Go;
begin
end;

end.
"@

# Three distinct component types, one of them repeated -- so a count question
# ("how many TZzWidget?") is answerable too, not just existence.
Write-Ascii (Join-Path $src 'uTypeForm.dfm') @"
object TypeForm: TTypeForm
  Left = 0
  Top = 0
  Caption = 'A caption value that dfm-prop already indexed'
  object edFirst: TZzWidget
    Hint = 'first hint'
  end
  object edSecond: TZzWidget
    Hint = 'second hint'
  end
  object gridOne: TQqGrid
    Hint = 'grid hint'
  end
end
"@

$db = Join-Path $scratch 't.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null

function TextHits([string]$Needle, [string]$ExtraArg) {
  $a = @('query','--text',$Needle,'--db',$db,'--source','dfm')
  if ($ExtraArg) { $a += $ExtraArg }
  $out = & $exePath @a 2>&1 | Out-String
  return $out
}

Write-Host "`n--- C1: the existing dfm-prop rows still work ---" -ForegroundColor Cyan
$capOut = TextHits 'A caption value that dfm-prop already indexed'
Check 'C1 a property VALUE is still findable' ([bool]($capOut -match 'uTypeForm\.dfm')) ($capOut.Trim())

Write-Host "`n--- the ask: find a component TYPE ---" -ForegroundColor Cyan
$zz = TextHits 'TZzWidget'
Check 'a component type is findable at all' ([bool]($zz -match 'uTypeForm\.dfm')) `
  "this is the whole point -- 0 matches means the object line's type token is still unindexed`n$($zz.Trim())"
Check 'N2 the hit names the .dfm and a line number' ([bool]($zz -match 'uTypeForm\.dfm:\d+')) ($zz.Trim())
Check 'both instances of the repeated type are found (count is answerable)' `
  ((([regex]::Matches($zz,'uTypeForm\.dfm:\d+')).Count) -ge 2) `
  "found $((([regex]::Matches($zz,'uTypeForm\.dfm:\d+')).Count)) -- 'how many of type X' needs every instance, not the first"

$qq = TextHits 'TQqGrid'
Check 'a second, singleton type is also findable' ([bool]($qq -match 'uTypeForm\.dfm')) ($qq.Trim())

Write-Host "`n--- N1: negative control ---" -ForegroundColor Cyan
$absent = TextHits 'TNoSuchWidgetAnywhere'
Check 'N1 a type NOT in the DFM returns nothing' (-not ($absent -match 'uTypeForm\.dfm')) `
  "indexing every identifier would satisfy the positive checks and flood --text`n$($absent.Trim())"

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
