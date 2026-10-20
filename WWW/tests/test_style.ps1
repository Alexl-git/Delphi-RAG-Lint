# Product-page styles: one marked block in style.css, responsive, colours from theme tokens only.
$css = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\assets\style.css'))
$m = [regex]::Match($css, '(?s)/\* products: begin \*/(.*?)/\* products: end \*/')
Assert-True $m.Success 'products block present'
$b = $m.Groups[1].Value
Assert-True ($b.Contains('grid-template-columns:repeat(auto-fill,minmax(min(240px,100%),1fr))')) 'tiles never wider than a phone'
Assert-True ($b -match '\.tile\{[^}]*overflow-wrap:anywhere') '.tile wraps long words'
Assert-True ($b -match '\.where\{[^}]*overflow-wrap:anywhere') '.where wraps long words'
Assert-True ($b -match '@media \(max-width:700px\)\{\.howit,\.where\{grid-template-columns:1fr\}\}') 'one column on a phone'
Assert-True (-not ($b -match '#[0-9a-fA-F]{3,6}\b')) 'no hex colour in the block'
Assert-True (-not $b.Contains('rgb(')) 'no rgb() in the block'
# Any literal colour breaks dark mode, not just hex: rgb/rgba/hsl/hsla and the white/black keywords
# (but not white-space). Positive control first, so the guard can fail.
$literal = 'rgba?\(|hsla?\(|(?<![\w-])(white|black)(?![\w-])'
foreach ($s in 'color:rgba(0,0,0,.1)', 'color:hsl(0 0% 0%)', 'background:white', 'color:black;') {
    Assert-True ($s -match $literal) "guard catches $s"
}
foreach ($s in 'white-space:nowrap', 'color:var(--ink)') { Assert-True ($s -notmatch $literal) "guard allows $s" }
Assert-True ($b -notmatch $literal) "no rgb/hsl/white/black literal in the block: $([regex]::Match($b, $literal).Value)"
# --check must not render as an em-dash (IBM Plex Mono ligature)
$code = [regex]::Match($css, '(?m)^code\{[^}]*\}').Value
Assert-True ($code -match 'font-variant-ligatures:none') 'code{} turns ligatures off'
