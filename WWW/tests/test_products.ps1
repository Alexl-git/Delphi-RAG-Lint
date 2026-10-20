. "$PSScriptRoot\..\lib\Config.ps1"
. "$PSScriptRoot\..\lib\Products.ps1"

$fx = "$PSScriptRoot\fixtures\products"
$cfg = [pscustomobject]@{ products = @(
    [pscustomobject]@{ id = 'dl'; facts = [pscustomobject]@{ rules = 190 } },
    [pscustomobject]@{ id = 'yadf' }
) }

# test_product_reads_metadata
$p = Read-ProductPage "$fx\dl\index.html" $cfg
Assert-Equal 'dl' $p.Id 'id'
Assert-Equal 'DL fixture' $p.Title 'title'
Assert-Equal 'The DL fixture product.' $p.Summary 'summary'
Assert-True (-not $p.Body.Contains('<!--product')) 'block not in body'
Assert-True ($p.Body.Contains('<img src="pic.png"')) 'body kept'

function New-BadProduct([string]$Folder, [string]$Text, [byte[]]$Bytes) {
    $root = New-TestDir
    $dir = Join-Path $root $Folder
    [void][IO.Directory]::CreateDirectory($dir)
    $f = Join-Path $dir 'index.html'
    if ($Bytes) { [IO.File]::WriteAllBytes($f, $Bytes) }
    else { [IO.File]::WriteAllText($f, $Text, [Text.ASCIIEncoding]::new()) }
    $f
}
$head = "<!--product`r`nid: dl`r`ntitle: T`r`nsummary: S`r`n-->`r`n"
$mic = '<p><a href="https://www.htrmicronite.com">Micronite</a></p>' + "`r`n"

# test_product_fills_facts
$f = New-BadProduct 'dl' ($head + $mic + "<p>Lint with {{fact:rules}} rules</p>`r`n")
$p = Read-ProductPage $f $cfg
Assert-True ($p.Body.Contains('Lint with 190 rules')) 'fact filled'
Assert-True (-not $p.Body.Contains('{{')) 'no placeholder left'

# test_product_unknown_fact_throws (typo on line 8)
$f = New-BadProduct 'dl' ($head + $mic + "<p>one</p>`r`n<p>{{fact:rule}}</p>`r`n")
Assert-Throws { Read-ProductPage $f $cfg } '*:8:*unknown fact*rule*'
# a product with no facts at all
$f = New-BadProduct 'yadf' (($head -replace 'id: dl', 'id: yadf') + $mic + "<p>{{fact:rules}}</p>`r`n")
Assert-Throws { Read-ProductPage $f $cfg } '*unknown fact*rules*'

# test_product_id_must_match_folder_and_config
$f = New-BadProduct 'dl' (($head -replace 'id: dl', 'id: yadf') + $mic)
Assert-Throws { Read-ProductPage $f $cfg } '*folder*'
$f = New-BadProduct 'zzz' (($head -replace 'id: dl', 'id: zzz') + $mic)
Assert-Throws { Read-ProductPage $f $cfg } '*site.json*'

# test_product_rejects_non_ascii_style_script
$bytes = [Text.Encoding]::ASCII.GetBytes($head + $mic + "<p>don") + [byte[]](0xE2, 0x80, 0x99) + [Text.Encoding]::ASCII.GetBytes("t</p>`r`n")
$f = New-BadProduct 'dl' $null $bytes
Assert-Throws { Read-ProductPage $f $cfg } '*:7:*non-ASCII*'
$f = New-BadProduct 'dl' ($head + $mic + "<div style=""color:red"">x</div>`r`n")
Assert-Throws { Read-ProductPage $f $cfg } '*forbidden markup*'
$f = New-BadProduct 'dl' ($head + $mic + "<script>x</script>`r`n")
Assert-Throws { Read-ProductPage $f $cfg } '*forbidden markup*'

# test_product_requires_micronite_link
$f = New-BadProduct 'dl' ($head + "<p>no link</p>`r`n")
Assert-Throws { Read-ProductPage $f $cfg } '*Micronite*'

# test_product_micronite_link_may_sit_low: the approved pages carry it in their section 04
$f = New-BadProduct 'dl' ($head + "<p>$('x' * 4000)</p>`r`n" + $mic)
Assert-Equal 'dl' (Read-ProductPage $f $cfg).Id 'Micronite link after 3000 characters is accepted'

# test_product_image_must_exist
$f = New-BadProduct 'dl' (($head -replace 'summary: S', "summary: S`r`nimage: share.png") + $mic)
Assert-Throws { Read-ProductPage $f $cfg } '*image*share.png*'

# test_get_product_pages_order_and_missing
$all = @(Get-ProductPages $fx $cfg)
Assert-Equal 'dl,yadf' (($all | ForEach-Object Id) -join ',') 'site.json order'
$root = Split-Path (Split-Path (New-BadProduct 'dl' ($head + $mic)) -Parent) -Parent
Assert-Throws { Get-ProductPages $root $cfg } '*no page*yadf*'

# test_config_accepts_facts
$d = New-TestDir
$j = Get-Content "$PSScriptRoot\..\site.json" -Raw | ConvertFrom-Json
$j.products[0] | Add-Member -NotePropertyName facts -NotePropertyValue ([pscustomobject]@{ rules = 190 }) -Force
$sj = Join-Path $d 'site.json'
$j | ConvertTo-Json -Depth 6 | Set-Content $sj
Assert-Equal 190 (Read-SiteConfig $sj).products[0].facts.rules 'facts read'
$j.products[0].facts = 'x'
$j | ConvertTo-Json -Depth 6 | Set-Content $sj
Assert-Throws { Read-SiteConfig $sj } '*facts*'
