<#
  run_arch_diagram.ps1 -- E-PARITY-ARCHIFY phase 1 (wave 146, lane x3).

  `arch-diagram --db D --output F` writes ONE self-contained HTML layer diagram of the units by
  folder, measured from unit_uses. Fixture folders:

    ui      uses data and core             -> top layer
    data    uses core twice                -> middle
    core    uses data once (implementation)-> layer 0; core->data is the BACK-edge, data->core forward
    ring\a -> ring\b -> ring\c -> ring\a   -> a TANGLE: one layer, kind tangle on all three
    r&d     uses core; the & must be escaped in the page

  RED-CHECK: against a build without the verb every check on the output FAILS, the exit check first.
  CONTROL: `graph --format dot` still starts with `digraph`, and a tampered copy of the page fails
  the self-contained scan, so that scan can fail.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
$script:Checks = 0
function Check($n, $ok, $d = '') {
  $script:Checks++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d)
  if (-not $ok) { $script:Failed = $true }
}
function ExternalRefs([string]$html) {
  # anything that would fetch: a src attribute, a link element, a CSS url to the net or @import, an
  # http(s) href. The svg namespace is a name, not a fetch; url(#mk-..) is a local reference.
  $scan = $html -replace 'xmlns="http://www\.w3\.org/2000/svg"', ''
  return @([regex]::Matches($scan, '(?i)\bsrc\s*=|<link\b|@import|url\(\s*["'']?(?!#)|href\s*=\s*["'']?https?:|https?://') | ForEach-Object { $_.Value })
}
function Unit([string]$name, [string]$intf, [string]$impl) {
  $i = if ($intf) { "uses $intf;`r`n" } else { '' }
  $m = if ($impl) { "uses $impl;`r`n" } else { '' }
  return "unit $name;`r`ninterface`r`n$i`r`nimplementation`r`n$m`r`nend.`r`n"
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) ("dl-arch-" + [guid]::NewGuid().ToString('N'))
$Src = Join-Path $Work 'proj'
try {
  $files = [ordered]@{
    'ui\uUi.pas'       = Unit 'uUi' 'uData1' 'uCore1'
    'data\uData1.pas'  = Unit 'uData1' 'uCore1' ''
    'data\uData2.pas'  = Unit 'uData2' '' 'uCore1'
    'core\uCore1.pas'  = Unit 'uCore1' '' 'uData2'
    'ring\a\uA.pas'    = Unit 'uA' 'uB' ''
    'ring\b\uB.pas'    = Unit 'uB' 'uC' ''
    'ring\c\uC.pas'    = Unit 'uC' '' 'uA'
    'r&d\uLab.pas'     = Unit 'uLab' 'uCore1' 'System.SysUtils'
  }
  foreach ($k in $files.Keys) {
    $p = Join-Path $Src $k
    [void][IO.Directory]::CreateDirectory((Split-Path $p))
    [IO.File]::WriteAllText($p, $files[$k], [Text.Encoding]::ASCII)
  }
  $Db = Join-Path $Work 'arch.sqlite'
  & $Exe index $Src --db $Db 2>&1 | Out-Null
  if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB'; exit 2 }

  $Html = Join-Path $Work 'arch.html'
  $out = & $Exe arch-diagram --db $Db --output $Html 2>&1
  Check 'exit-0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  Check 'file-written' (Test-Path $Html)
  $page = if (Test-Path $Html) { [IO.File]::ReadAllText($Html) } else { '' }

  Check 'is-html-with-svg' ($page.StartsWith('<!DOCTYPE html>') -and $page.Contains('<svg id="d"'))
  $ext = @(ExternalRefs $page)
  Check 'self-contained' (($page.Length -gt 0) -and ($ext.Count -eq 0)) ($ext -join ' | ')
  $tampered = $page + '<script src="https://cdn.example/x.js"></script><link rel="stylesheet" href="a.css">'
  Check 'control:scan-can-fail' (@(ExternalRefs $tampered).Count -ge 2)

  $m = [regex]::Match($page, '(?s)<script type="application/json" id="graph">(.*?)</script>')
  Check 'model-embedded' $m.Success
  $model = $null
  try { $model = $m.Groups[1].Value | ConvertFrom-Json } catch { }
  Check 'schema' ($model.schema -eq 'drag-lint.arch/1') "schema=$($model.schema)"
  Check 'counts' (($model.units -eq 8) -and (@($model.zones).Count -eq 7)) "units=$($model.units) zones=$(@($model.zones).Count)"

  $layer = @{}; foreach ($z in @($model.zones)) { $layer[$z.name] = $z.layer }
  Write-Host ("    layers: " + (($layer.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '))
  Check 'layer:foundation-is-0' ($layer['core'] -eq 0) "core=$($layer['core'])"
  Check 'layer:data-above-core' ($layer['data'] -gt $layer['core'])
  Check 'layer:ui-above-data' ($layer['ui'] -gt $layer['data'])
  Check 'layer:rd-above-core' ($layer['r&d'] -gt $layer['core'])
  Check 'tangle:one-layer' (($layer['ring/a'] -eq $layer['ring/b']) -and ($layer['ring/b'] -eq $layer['ring/c']))

  function EdgeOf($f, $t) { @($model.edges) | Where-Object { ($_.from -eq $f) -and ($_.to -eq $t) } | Select-Object -First 1 }
  $dc = EdgeOf 'data' 'core'; $cd = EdgeOf 'core' 'data'
  Check 'edge:data->core-forward-2' (($dc.kind -eq 'forward') -and ($dc.weight -eq 2) -and ($dc.interface -eq 1)) "kind=$($dc.kind) w=$($dc.weight) i=$($dc.interface)"
  Check 'edge:core->data-back-1' (($cd.kind -eq 'back') -and ($cd.weight -eq 1)) "kind=$($cd.kind) w=$($cd.weight)"
  $p = @($cd.pairs)[0]
  Check 'evidence:pair-has-file-and-line' (($p.from -eq 'uCore1') -and ($p.to -eq 'uData2') -and ($p.path -eq 'core/uCore1.pas') -and ($p.line -eq 5) -and ($p.section -eq 'implementation')) "$($p.from) $($p.to) $($p.path):$($p.line) $($p.section)"
  $rings = @(@($model.edges) | Where-Object { ($_.from -like 'ring/*') -and ($_.to -like 'ring/*') })
  Check 'tangle:three-tangle-edges' (($rings.Count -eq 3) -and (@($rings | Where-Object kind -eq 'tangle').Count -eq 3)) "n=$($rings.Count)"
  $uc = EdgeOf 'ui' 'core'; $ud = EdgeOf 'ui' 'data'
  Check 'implied:ui->core-via-data' (($uc.kind -eq 'forward') -and ($uc.implied -eq $true)) "kind=$($uc.kind) implied=$($uc.implied)"
  Check 'implied:direct-steps-stay' (($ud.implied -eq $false) -and ($dc.implied -eq $false))
  Check 'implied:faint-in-drawing' ($page.Contains('class="edge forward implied"') -and $page.Contains('.edge.implied{opacity'))
  Check 'keys:graph-edge-shape' (($null -ne $dc.from) -and ($null -ne $dc.to) -and ($null -ne $dc.weight))
  Check 'external:counted-not-drawn' (($model.externalUses -ge 1) -and (-not $page.Contains('data-zone="System')))  "external=$($model.externalUses)"

  Check 'escape:amp-in-text' ($page.Contains('<title>r&amp;d</title>'))
  $svg = [regex]::Match($page, '(?s)<svg id="d".*?</svg>').Value
  Check 'escape:no-raw-amp-in-svg' (-not ($svg -match '&(?!amp;|lt;|gt;|quot;|#)'))
  Check 'drawing:one-box-per-zone' ([regex]::Matches($svg, 'class="zone"').Count -eq 7)
  Check 'drawing:back-edge-marked' ($svg.Contains('class="edge back"'))
  Check 'drawing:bottom-layer-lowest' {
    $ys = @{}; foreach ($b in [regex]::Matches($svg, '<g class="zone" data-z="(\d+)"[^>]*><title>([^<]+)</title><rect x="\d+" y="(\d+)"')) { $ys[$b.Groups[2].Value] = [int]$b.Groups[3].Value }
    ($ys['core'] -gt $ys['data']) -and ($ys['data'] -gt $ys['ui'])
  }.Invoke()

  # the click panel, driven in a real browser: a copy of the page calls zone() and edge() at load and
  # writes what the panel shows into the title. A throw leaves the title alone, so this can fail.
  $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  if (Test-Path $edge) {
    $probe = Join-Path $Work 'probe.html'; $dom = Join-Path $Work 'dom.html'
    $js = '<script>zone(M.zones.findIndex(function(z){return z.name==="core"}));var a=P.textContent;edge(M.edges.findIndex(function(e){return e.kind==="back"}));document.title="PANEL|"+a+"|"+P.textContent+"|"+document.querySelectorAll("#d .edge.dim").length;</script></body>'
    [IO.File]::WriteAllText($probe, $page.Replace('</body>', $js), [Text.Encoding]::ASCII)
    $b = Start-Process $edge -ArgumentList '--headless=new', '--disable-gpu', "--user-data-dir=$Work\edge", '--dump-dom', ('file:///' + $probe.Replace('\', '/')) -RedirectStandardOutput $dom -PassThru
    # Edge's children outlive the process started here and hold the file: read it shared, until complete
    $text = ''; $until = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $until -and -not $text.Contains('</html>')) {
      [Threading.Thread]::Sleep(1000)
      try {
        $fs = [IO.File]::Open($dom, 'Open', 'Read', 'ReadWrite,Delete')
        try { $text = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
      } catch { $text = '' }
    }
    if ($text.Contains('</html>')) {
      $tt = [regex]::Match($text, '<title>(PANEL\|[^<]*)</title>').Groups[1].Value
      Write-Host "    panel: $($tt.Substring(0, [Math]::Min(150, $tt.Length)))"
      Check 'panel:folder-lists-units' ($tt.Contains('uCore1') -and $tt.Contains('core/uCore1.pas'))
      Check 'panel:arrow-lists-uses-line' ($tt.Contains('uCore1 uses uData2') -and $tt.Contains('core/uCore1.pas:5 (implementation)'))
      Check 'panel:others-dimmed' (($tt -match '\|(\d+)$') -and ([int]$Matches[1] -eq (@($model.edges).Count - 1)))
    } else { Write-Host '  [SKIP] panel: the browser did not finish in 120 s' }
  } else { Write-Host '  [SKIP] panel: no Edge on this box' }

  $Html2 = Join-Path $Work 'arch2.html'
  & $Exe arch-diagram --db $Db --output $Html2 2>&1 | Out-Null
  $same = (Test-Path $Html2) -and ([IO.File]::ReadAllText($Html2) -ceq $page)
  Check 'deterministic:same-bytes' $same

  $json = (& $Exe arch-diagram --db $Db --json 2>&1 | Out-String).Trim()
  Check 'json:same-model-as-page' ($json -ceq $m.Groups[1].Value.Replace('<', '<')) "len=$($json.Length)"

  & $Exe arch-diagram --db (Join-Path $Work 'none.sqlite') 2>&1 | Out-Null
  Check 'missing-db:exit-2' ($LASTEXITCODE -eq 2) "exit=$LASTEXITCODE"
  Check 'missing-db:not-created' (-not (Test-Path (Join-Path $Work 'none.sqlite')))

  $dot = (& $Exe graph --db $Db --format dot 2>&1 | Out-String)
  Check 'control:graph-dot-unchanged' ($dot -match 'digraph')
} catch {
  # a throw must fail the guard: the checks after it never ran
  Check 'no-exception' $false $_.Exception.Message
} finally {
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Work) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { } }
  try { if (Test-Path $Work) { [IO.Directory]::Delete($Work, $true) } } catch { Write-Host "  [NOTE] temp folder left: $Work" }
}
if ($script:Checks -lt 30) { Check 'ran-all-checks' $false "only $($script:Checks) checks ran" }
if ($script:Failed) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'
exit 0
