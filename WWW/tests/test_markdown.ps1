# Markdown subset + help-tree URL resolution.
. "$PSScriptRoot\..\lib\Render.ps1"
. "$PSScriptRoot\..\lib\Help.ps1"

$ctx = @{ Product = 'dl'; SrcRel = 'features/ask.md'; ResolveHref = { param($h, $c) Resolve-HelpHref $h $c.Product $c.SrcRel } }
function Cv([string]$s) { (ConvertFrom-SiteMarkdown $s $ctx).Trim() }

# test_resolve_href
Assert-Equal '/help/dl/features/other/' (Resolve-HelpHref 'other.md' 'dl' 'features/ask.md') 'sibling'
Assert-Equal '/help/dl/cli/#x' (Resolve-HelpHref '../cli.md#x' 'dl' 'features/ask.md') 'parent + anchor'
Assert-Equal '/help/dl/' (Resolve-HelpHref '../index.md' 'dl' 'features/ask.md') 'index'
Assert-Equal '/help/dl/features/img/a.png' (Resolve-HelpHref 'img/a.png' 'dl' 'features/ask.md') 'image'
Assert-Equal 'https://x.org/a.md' (Resolve-HelpHref 'https://x.org/a.md' 'dl' 'features/ask.md') 'external untouched'
Assert-Equal '#frag' (Resolve-HelpHref '#frag' 'dl' 'features/ask.md') 'anchor untouched'

# test_blocks
Assert-Equal '<h2 id="fix-it-mechanically-cycles---fix">Fix it mechanically (cycles --fix)</h2>' (Cv '## Fix it mechanically (cycles --fix)') 'heading id'
Assert-Equal '<p>a <strong>b</strong> <em>c</em> <code>d&lt;e&gt;</code></p>' (Cv 'a **b** *c* `d<e>`') 'inline'
Assert-Equal '<p>snake_case_name and 2*3*4</p>' (Cv 'snake_case_name and 2*3*4') 'no false emphasis'
Assert-Equal '<p>raw &lt;b&gt;x&lt;/b&gt;</p>' (Cv 'raw <b>x</b>') 'raw html escaped'
Assert-Equal '<p><a href="/help/dl/features/o/">O</a> <img src="/help/dl/features/img/a.png" alt="alt"></p>' (Cv '[O](o.md) ![alt](img/a.png)') 'link + image'
$t = Cv "| A | B |`n| --- | --- |`n| ``x|y`` \| z | 2 |"
Assert-True ($t.Contains('<th>A</th><th>B</th>')) 'table head'
Assert-True ($t -match '<td>.*z</td><td>2</td>') "table row: $t"
$c = Cv "``````text`n<a>`n  b`n``````"
Assert-Equal "<pre><code>&lt;a&gt;`n  b</code></pre>" $c 'fence'
Assert-Equal "<pre><code>x`n  y</code></pre>" (Cv "    x`n      y") 'indented code'

# test_lists
$l = Cv "- a`n- b`n  - c`n- d"
Assert-Equal "<ul>`n<li>a</li>`n<li>b<ul>`n<li>c</li>`n</ul></li>`n<li>d</li>`n</ul>" $l 'nested tight list'
$o = Cv "3. x`n`n   ``````text`n   code`n   ``````"
Assert-True ($o.StartsWith('<ol start="3">') -and $o.Contains('<pre><code>code</code></pre>')) "ordered start + fence in item: $o"
Assert-Equal "<blockquote><p>q</p>`n</blockquote>" (Cv '> q') 'quote'

# test_front_matter
$fm = Split-FrontMatter "---`r`nid: a`r`ntitle: `"T x`"`r`n---`r`n# Body"
Assert-Equal 'a' $fm.Meta['id'] 'id'
Assert-Equal 'T x' $fm.Meta['title'] 'quoted value unquoted'
Assert-Equal '# Body' $fm.Body 'body'
