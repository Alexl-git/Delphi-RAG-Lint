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
