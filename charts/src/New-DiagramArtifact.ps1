<#
  New-DiagramArtifact.ps1 -- closes the loop: question -> chart -> bundle ->
  browser shell -> a cross-reference you paste into the code.

  These artifacts are NOT autodocumentation. They are large, slow to produce and
  stable over time, so nothing generates them on a build. Someone asks a question
  deliberately, and inserts a REFERENCE into the code or its documentation. The
  volatility therefore lives in the FILE -- a stable path plus a regenerated
  artifact -- and never in the comment, which is what keeps the autodoc rewriter
  entirely out of it.

  Produces, under <OutRoot>\<question>-<symbol>\ :
    graph.svg      the picture, rows are real <a xlink:href> anchors
    graph.plain    the geometry, from the SAME layout run (cannot drift)
    graph.dot      the dot we emitted (we never parse dot; it is our output)
    graph.png      raster export
    graph.pdf      document export
    index.html     the shell: opens in a browser, clicks are explained
    meta.json      index fingerprint + regenerate command (staleness detectable)
    xref.txt       the DocInsight <remarks> block to paste into the unit

  Clicks: the SVG anchors are draglint://open?file=..&line=.. Nothing answers
  that scheme yet -- the viewer speaks the named-pipe contract, the IDE plugin's
  pipe SERVER does not exist. The shell says so rather than failing silently.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Qname,
  [Parameter(Mandatory)][string] $DbPath,
  [ValidateSet('butterfly')][string] $Question = 'butterfly',
  [int]    $Depth   = 2,
  [string] $OutRoot = (Join-Path $PSScriptRoot '..\artifacts'),
  [switch] $Open
)

$ErrorActionPreference = 'Stop'

$slug    = ($Qname -replace '[^A-Za-z0-9]', '_')
$dir     = Join-Path $OutRoot "$Question-$slug"
New-Item -ItemType Directory -Force $dir | Out-Null

# ---- 1. emit ----------------------------------------------------------------
$r = & (Join-Path $PSScriptRoot 'Emit-Butterfly.ps1') -Qname $Qname -DbPath $DbPath -Depth $Depth -OutDir $dir
foreach ($pair in @(@($r.Svg,'graph.svg'), @($r.Plain,'graph.plain'), @($r.Dot,'graph.dot'))) {
  if (Test-Path $pair[0]) { Move-Item $pair[0] (Join-Path $dir $pair[1]) -Force }
}
foreach ($ext in 'png','pdf') {
  $src = Join-Path $dir "$slug.$ext"
  if (Test-Path $src) { Move-Item $src (Join-Path $dir "graph.$ext") -Force }
}

# ---- 2. fingerprint the index, so staleness is DETECTABLE not merely visible -
$dbItem = Get-Item $DbPath
$fp = [pscustomobject]@{
  question    = $Question
  qname       = $Qname
  depth       = $Depth
  index       = $dbItem.FullName
  indexBytes  = $dbItem.Length
  indexMtime  = $dbItem.LastWriteTimeUtc.ToString('s') + 'Z'
  generated   = (Get-Date).ToUniversalTime().ToString('s') + 'Z'
  callers     = $r.Callers
  callees     = $r.Callees
  clickTargets= $r.ClickTargets
  regenerate  = "New-DiagramArtifact.ps1 -Question $Question -Qname $Qname -DbPath `"$DbPath`" -Depth $Depth"
}
$fp | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dir 'meta.json') -Encoding ascii

# ---- 3. the shell ------------------------------------------------------------
$svg = [IO.File]::ReadAllText((Join-Path $dir 'graph.svg'))
$svg = $svg -replace '(?s)^.*?(?=<svg)', ''          # drop the XML prolog + DOCTYPE

$short = $Qname
$html = @"
<!doctype html>
<meta charset="utf-8">
<title>$Question -- $short</title>
<style>
  :root{--bg:#F6F7F9;--panel:#fff;--ink:#131820;--muted:#5B6674;--line:#DDE2E8;
        --accent:#0F766E;--accent-soft:#E2F1EF;--warn:#9A5408;--warn-soft:#FBF0E0;
        --mono:'Cascadia Mono',Consolas,monospace;
        --sans:'Segoe UI',system-ui,sans-serif;}
  @media (prefers-color-scheme:dark){:root{--bg:#0E1319;--panel:#151C24;--ink:#E6EBF1;
        --muted:#96A2B1;--line:#293441;--accent:#4FD1C0;--accent-soft:#12312D;
        --warn:#E0A458;--warn-soft:#33260F;}}
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);}
  header{padding:20px 24px;border-bottom:1px solid var(--line);}
  h1{margin:0 0 6px;font-size:22px;font-weight:650;}
  h1 code{font-family:var(--mono);font-size:.85em;}
  .meta{font-family:var(--mono);font-size:12.5px;color:var(--muted);
        display:flex;flex-wrap:wrap;gap:6px 22px;}
  .meta b{color:var(--ink);font-weight:600;}
  main{padding:20px 24px;}
  .stage{background:var(--panel);border:1px solid var(--line);border-radius:10px;
         padding:16px;overflow:auto;}
  .stage svg{max-width:100%;height:auto;}
  .stage a{cursor:pointer;}
  .stage a:hover text{text-decoration:underline;}
  .note{margin:18px 0 0;border-left:4px solid var(--warn);background:var(--warn-soft);
        padding:14px 18px;border-radius:0 8px 8px 0;font-size:14px;}
  .note b{color:var(--warn);}
  #toast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);
         background:var(--ink);color:var(--bg);font-family:var(--mono);font-size:13px;
         padding:11px 16px;border-radius:8px;max-width:min(92vw,720px);
         box-shadow:0 6px 24px rgba(0,0,0,.25);opacity:0;pointer-events:none;
         transition:opacity .18s;}
  #toast.on{opacity:1;}
  footer{padding:16px 24px 32px;color:var(--muted);font-family:var(--mono);font-size:12px;}
  code.k{background:var(--accent-soft);color:var(--accent);padding:1px 6px;border-radius:4px;}
</style>
<header>
  <h1>$Question &mdash; <code>$short</code></h1>
  <div class="meta">
    <span><b>$($r.Callers)</b> callers</span>
    <span><b>$($r.Callees)</b> callees</span>
    <span><b>$($r.ClickTargets)</b> click targets</span>
    <span>index <b>$([IO.Path]::GetFileName($DbPath))</b></span>
    <span>generated <b>$($fp.generated)</b></span>
  </div>
</header>
<main>
  <div class="stage">$svg</div>

  <div class="note">
    <p><b>Clicks are wired but nothing answers them yet.</b> Every row is a real
    anchor carrying <code class="k">draglint://open?file=..&amp;line=..</code>.
    Click one and this page will show you the exact message it would send. The
    standalone viewer already speaks the named-pipe contract
    (<code class="k">\\.\pipe\drag-lint-open-source</code>, one line,
    <code class="k">&lt;file&gt;&lt;TAB&gt;&lt;line&gt;&lt;LF&gt;</code>); what
    does not exist is the IDE plugin's pipe <b>server</b>. Until it does, these
    links are deliberately inert rather than quietly doing nothing.</p>
  </div>
</main>
<footer>
  graph.svg &middot; graph.png &middot; graph.pdf &middot; graph.plain (geometry,
  same layout run) &middot; meta.json (regenerate command + index fingerprint)
</footer>
<div id="toast"></div>
<script>
(function () {
  var t = document.getElementById('toast'), timer = null;
  function toast(msg) {
    t.textContent = msg; t.classList.add('on');
    clearTimeout(timer); timer = setTimeout(function () { t.classList.remove('on'); }, 5200);
  }
  document.querySelector('.stage').addEventListener('click', function (ev) {
    var a = ev.target.closest('a'); if (!a) return;
    var href = a.getAttribute('xlink:href') || a.getAttribute('href') || '';
    if (href.indexOf('draglint://') !== 0) return;
    ev.preventDefault();
    var m = /file=([^&]*)&(?:amp;)?line=(\d+)/.exec(href);
    if (!m) { toast('unparseable target: ' + href); return; }
    var file = decodeURIComponent(m[1]), line = m[2];
    toast('would send over \\\\.\\pipe\\drag-lint-open-source  ->  ' + file + ' TAB ' + line);
  });
})();
</script>
"@
[IO.File]::WriteAllText((Join-Path $dir 'index.html'),
  ($html -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.UTF8Encoding($false)))

# ---- 4. the cross-reference to paste into the unit ---------------------------
$rel = (Resolve-Path (Join-Path $dir 'index.html')).Path
$xref = @"
/// <remarks>
/// Diagram: $Question of $Qname
/// Artifact: $rel
/// Generated: $($fp.generated) from $([IO.Path]::GetFileName($DbPath))
/// Regenerate: $($fp.regenerate)
/// The artifact is REGENERATED, not edited. This comment names a stable path
/// so it never needs rewriting when the diagram changes.
/// </remarks>
"@
[IO.File]::WriteAllText((Join-Path $dir 'xref.txt'),
  ($xref -replace "`r`n", "`n" -replace "`n", "`r`n"), (New-Object Text.ASCIIEncoding))

if ($Open) { Start-Process (Join-Path $dir 'index.html') }

[pscustomobject]@{
  Bundle       = $dir
  Shell        = (Join-Path $dir 'index.html')
  Xref         = (Join-Path $dir 'xref.txt')
  ClickTargets = $r.ClickTargets
  Files        = (Get-ChildItem $dir | Sort-Object Name | ForEach-Object { "$($_.Name) ($($_.Length))" }) -join ', '
}
