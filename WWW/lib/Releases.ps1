# Latest-release lookup for one product through the gh CLI.
# The build aborts on any failure: it never publishes guessed numbers.

function Get-ReleaseInfo($Product, [scriptblock]$Gh = { param($argv) & gh @argv }) {
    $argv = @('release', 'view', '--repo', $Product.repo, '--json', 'tagName,publishedAt')
    $global:LASTEXITCODE = 0
    $raw = (& $Gh $argv) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw "release lookup failed for $($Product.name): gh exit $LASTEXITCODE"
    }
    try { $j = $raw | ConvertFrom-Json } catch {
        throw "release lookup failed for $($Product.name): unreadable gh output"
    }
    foreach ($k in 'tagName', 'publishedAt') {
        if (-not $j.$k) { throw "release lookup failed for $($Product.name): $k missing" }
    }
    # ConvertFrom-Json turns ISO strings into DateTime; normalise to UTC either way.
    $when = if ($j.publishedAt -is [datetime]) { $j.publishedAt.ToUniversalTime() }
            else { [datetimeoffset]::Parse($j.publishedAt).UtcDateTime }
    [pscustomobject]@{
        Tag       = [string]$j.tagName
        Date      = $when.ToString('yyyy-MM-dd')
        Url       = "https://github.com/$($Product.repo)/releases/latest"
        Changelog = $Product.changelog
    }
}
