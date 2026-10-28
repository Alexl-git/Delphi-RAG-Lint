<#
  run_overview.ps1 -- `overview`, the ONE bounded call for an agent's first turn (XERJ item 6).

  WHY. A fresh agent spends its first five turns finding out what a project is: how
  big, how layered, what is referenced most, where it starts, which forms exist, how
  old the index is. `overview --db <db>` answers all six in a fixed order, every
  section capped, every cap reported ("N omitted by cap M; rerun with --max-rows K"
  in text, `total`/`cap`/`omitted` in JSON; exit code unchanged).

  FIXTURE  uLeaf <- uMid <- uTop (a 3-layer chain), uCycA <-> uCycB (a cycle),
           uForm (+ .dfm, TForm1 with a click handler), App.dpr uses them all.
           Empty.dpr = a project with no units, the positive control for "0".

  CASES
    T1 text: the six section headers appear, in the fixed order
    T2 --json: top-level keys are exactly the six sections, same order
    T3 layers: uLeaf is below uMid is below uTop; the cycle sits in the cyclic row
    T4 forms / entrypoints see the form and its event handler
    T5 --max-rows 2: text says "omitted by cap 2; rerun with --max-rows", JSON counts has cap=2 and omitted>0, exit 0
    T6 default output stays under 4000 tokens (chars/4)
    P1 CONTROL --max-rows 500: no "omitted by cap" line, every JSON omitted is 0 (T5 can only pass if the cap is real)
    P2 CONTROL empty project: all six headers still print; forms, fanin and entrypoints say 0

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_overview_$PID"
)
$script:fail = $false
try {
$ErrorActionPreference = 'Stop'
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function U([string]$Name, [string]$IntfUses, [string]$ImplUses) {
  $iu = if ($IntfUses) { "`nuses $IntfUses;`n" } else { '' }
  $mu = if ($ImplUses) { "`nuses $ImplUses;`n" } else { '' }
  return "{ header }`n`nunit $Name;`n`ninterface$iu`nprocedure Go$Name;`n`nimplementation$mu`nprocedure Go$Name;`nbegin`nend;`n`ninitialization`n  Go$Name;`n`nend.`n"
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
W "$WorkDir\uLeaf.pas" (U 'uLeaf' '' '')
W "$WorkDir\uMid.pas"  (U 'uMid'  'uLeaf' '')
W "$WorkDir\uTop.pas"  (U 'uTop'  'uMid' 'uLeaf')
W "$WorkDir\uCycA.pas" (U 'uCycA' 'uCycB' '')
W "$WorkDir\uCycB.pas" (U 'uCycB' '' 'uCycA')
W "$WorkDir\uForm.pas" "unit uForm;`n`ninterface`n`nuses Vcl.Forms;`n`ntype`n  TForm1 = class(TForm)`n    procedure Button1Click(Sender: TObject);`n  end;`n`nimplementation`n`n{`$R *.dfm}`n`nprocedure TForm1.Button1Click(Sender: TObject);`nbegin`nend;`n`nend.`n"
W "$WorkDir\uForm.dfm" "object Form1: TForm1`n  Caption = 'x'`n  object Button1: TButton`n    OnClick = Button1Click`n  end`nend`n"
W "$WorkDir\App.dpr" "program App;`nuses`n  uLeaf in 'uLeaf.pas',`n  uMid in 'uMid.pas',`n  uTop in 'uTop.pas',`n  uCycA in 'uCycA.pas',`n  uCycB in 'uCycB.pas',`n  uForm in 'uForm.pas';`nbegin`nend.`n"
W "$WorkDir\Empty.dpr" "program Empty;`nbegin`nend.`n"

$db  = "$WorkDir\app.sqlite"
$dbE = "$WorkDir\empty.sqlite"
& $exePath index --project "$WorkDir\App.dpr" --db $db 2>&1 | Out-Null
& $exePath index --project "$WorkDir\Empty.dpr" --db $dbE 2>&1 | Out-Null
Check 'V both fixture indexes were built' ((Test-Path $db) -and (Test-Path $dbE)) ''

$sections = 'freshness','counts','layers','fanin','entrypoints','forms'
function Run([string[]]$A) {
  $o = & $exePath overview @A 2>&1 | ForEach-Object { "$_" }
  return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($o -join "`n") }
}

$r = Run @('--db',$db)
$pos = @($sections | ForEach-Object { $r.Text.IndexOf("== $_") })
$ordered = ($pos -notcontains -1) -and (@($pos | Sort-Object) -join ',') -eq ($pos -join ',')
Check 'T1 six section headers in the fixed order' ($r.Exit -eq 0 -and $ordered) ("exit=$($r.Exit) pos=$($pos -join ',')")

$j = Run @('--db',$db,'--json')
$obj = $null; try { $obj = $j.Text | ConvertFrom-Json } catch {}
$keys = if ($obj) { @($obj.PSObject.Properties.Name) } else { @() }
Check 'T2 --json has exactly the six section keys, in order' (($keys -join ',') -eq ($sections -join ',')) ("keys=$($keys -join ',')")

if ($obj) {
  $rows = @($obj.layers.rows)
  $lineOf = { param($n) $i = 0; foreach ($x in $rows) { if ((($x.units) -join ' ') -match "\b$n\b") { return $i }; $i++ }; return -1 }
  $a = & $lineOf 'uLeaf'; $b = & $lineOf 'uMid'; $c = & $lineOf 'uTop'; $d = & $lineOf 'uCycA'
  Check 'T3 layers: uLeaf < uMid < uTop' (($a -ge 0) -and ($a -lt $b) -and ($b -lt $c)) "rows a=$a b=$b c=$c"
  Check 'T3b the cycle is in the cyclic row, after the layered units' (($d -gt $c) -and ($rows[$d].layer -eq 'cyclic')) "d=$d"
  Check 'T4 forms lists TForm1 / Form1' ((($obj.forms.rows | ConvertTo-Json -Compress) -match 'Form1') -and $obj.forms.total -ge 1) ($obj.forms | ConvertTo-Json -Compress)
  Check 'T4b entrypoints list the dfm click handler and an initialization' ((($obj.entrypoints.rows | ConvertTo-Json -Compress) -match 'OnClick') -and (($obj.entrypoints.rows | ConvertTo-Json -Compress) -match 'initialization')) ($obj.entrypoints | ConvertTo-Json -Compress)
}

$c2 = Run @('--db',$db,'--max-rows','2')
$c2j = $null; try { $c2j = (Run @('--db',$db,'--max-rows','2','--json')).Text | ConvertFrom-Json } catch {}
Check 'T5 --max-rows 2 text says "omitted by cap 2; rerun with --max-rows", exit unchanged' ($c2.Exit -eq 0 -and $c2.Text -match 'omitted by cap 2; rerun with --max-rows \d+') $c2.Text
Check 'T5b --max-rows 2 JSON: counts.cap=2, omitted>0, rows<=2' ($c2j -and $c2j.counts.cap -eq 2 -and $c2j.counts.omitted -gt 0 -and @($c2j.counts.rows).Count -le 2) ($c2j.counts | ConvertTo-Json -Compress)

Check 'T6 default output under 4000 tokens' (($r.Text.Length / 4) -lt 4000) "chars=$($r.Text.Length)"

$p1 = Run @('--db',$db,'--max-rows','500')
$p1j = $null; try { $p1j = (Run @('--db',$db,'--max-rows','500','--json')).Text | ConvertFrom-Json } catch {}
$allZero = $p1j -and (@($sections | Where-Object { $p1j.$_.omitted -ne 0 }).Count -eq 0)
Check 'P1 CONTROL --max-rows 500: no omitted line, every omitted is 0' ($p1.Exit -eq 0 -and $p1.Text -notmatch 'omitted by cap' -and $allZero) ''

$e = Run @('--db',$dbE)
$eHeaders = @($sections | Where-Object { $e.Text -notmatch "== $_" }).Count -eq 0
$eZero = ($e.Text -match '== fanin: 0 ==') -and ($e.Text -match '== entrypoints: 0 ==') -and ($e.Text -match '== forms: 0 ==')
Check 'P2 CONTROL empty project prints all six headers, forms/fanin/entrypoints = 0' ($e.Exit -eq 0 -and $eHeaders -and $eZero) $e.Text
} catch { Write-Host ("ERROR: $_") -ForegroundColor Red; $script:fail = $true
} finally { if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green } }
