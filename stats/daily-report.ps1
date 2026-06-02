# Daily report: drag-lint token/time savings (local usage log) + GitHub
# activity across ALL your repos (downloads, stars, issues, traffic) with
# day-over-day deltas. Writes a markdown report; email is optional.
#
#   pwsh daily-report.ps1                       # write report file only
#   pwsh daily-report.ps1 -EmailTo you@x.com    # also email (needs $env:GMAIL_APP_PASSWORD)
param(
    [string]$Owner     = 'Alexl-git',
    [string[]]$Repos   = @(),          # explicit list; empty = all of $Owner's repos
    [string]$EmailTo   = '',
    [string]$EmailFrom = 'alexanderliberov@gmail.com'
)
$ErrorActionPreference = 'Stop'
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile  = Join-Path $Here 'draglint-usage.log'
$SnapFile = Join-Path $Here 'gh-snapshot.json'
$RepDir   = Join-Path $Here 'reports'
New-Item -ItemType Directory -Force $RepDir | Out-Null
$Today    = Get-Date -Format 'yyyy-MM-dd'
$RepFile  = Join-Path $RepDir "daily-$Today.md"

function GhJson($path) { try { gh api $path 2>$null | ConvertFrom-Json } catch { $null } }

# ---- 1. drag-lint savings (local usage log) -----------------------------
$todayRows=0; $todayLines=0; $todayTokens=0; $totLines=0; $totTokens=0
if (Test-Path $LogFile) {
    foreach ($line in Get-Content $LogFile) {
        if ($line.StartsWith('#') -or -not $line.Trim()) { continue }
        $f = $line -split "`t"; if ($f.Count -lt 4) { continue }
        $ln=[int]$f[2]; $tk=[int]$f[3]; $totLines+=$ln; $totTokens+=$tk
        if ($f[0].StartsWith($Today)) { $todayRows++; $todayLines+=$ln; $todayTokens+=$tk }
    }
}

# ---- 2. repo list -------------------------------------------------------
if (-not $Repos -or $Repos.Count -eq 0) {
    $list = try { gh repo list $Owner --no-archived --limit 200 --json nameWithOwner 2>$null | ConvertFrom-Json } catch { @() }
    $Repos = @($list | ForEach-Object { $_.nameWithOwner })
}

# ---- 3. per-repo stats + deltas vs snapshot -----------------------------
$prev = if (Test-Path $SnapFile) { Get-Content $SnapFile -Raw | ConvertFrom-Json } else { $null }
function PrevVal($name,$key) { if ($prev -and ($prev.PSObject.Properties.Name -contains $name)) { [int]($prev.$name.$key) } else { -1 } }
function DeltaStr($now,$was) { if ($was -lt 0) { '' } else { $d=$now-$was; if ($d -gt 0) { " (+$d)" } elseif ($d -lt 0) { " ($d)" } else { '' } } }

$snap = @{}
$rows = @()
$newIssues = @()
foreach ($r in $Repos) {
    $info = GhJson "repos/$r"
    if (-not $info) { continue }
    $rels = GhJson "repos/$r/releases"
    $dl = 0; if ($rels) { foreach ($rel in $rels) { foreach ($a in $rel.assets) { $dl += [int]$a.download_count } } }
    $stars = [int]$info.stargazers_count
    $openI = [int]$info.open_issues_count
    $views = GhJson "repos/$r/traffic/views"; $vc = if ($views) { [int]$views.count } else { 0 }
    # new issues in last 24h (exclude PRs)
    $iss = GhJson "repos/$r/issues?state=open&since=$((Get-Date).AddHours(-24).ToString('yyyy-MM-ddTHH:mm:ssZ'))&per_page=50"
    if ($iss) { foreach ($i in $iss) {
        if ($i.PSObject.Properties.Name -contains 'pull_request') { continue }
        if ([datetime]$i.created_at -ge (Get-Date).AddHours(-24)) { $newIssues += "  - [$r] #$($i.number) $($i.title)" }
    } }

    $dDl = DeltaStr $dl    (PrevVal $r 'downloads')
    $dSt = DeltaStr $stars (PrevVal $r 'stars')
    $dOi = DeltaStr $openI (PrevVal $r 'openIssues')
    $rows += "- **$r**: downloads $dl$dDl | stars $stars$dSt | open issues $openI$dOi | views(14d) $vc"
    $snap[$r] = @{ downloads=$dl; stars=$stars; openIssues=$openI }
}

# ---- 4. compose ---------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Daily report - $Today")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## drag-lint vs Grep savings (estimate)")
[void]$sb.AppendLine("- Today: $todayRows queries, ~$todayLines grep-lines avoided, ~$todayTokens tokens saved")
[void]$sb.AppendLine("- All-time: ~$totLines grep-lines avoided, ~$totTokens tokens saved")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("## GitHub activity ($($Repos.Count) repos under $Owner)")
foreach ($line in $rows) { [void]$sb.AppendLine($line) }
[void]$sb.AppendLine("")
if ($newIssues.Count -gt 0) {
    [void]$sb.AppendLine("## New issues / bug reports (24h)")
    foreach ($n in $newIssues) { [void]$sb.AppendLine($n) }
} else {
    [void]$sb.AppendLine("## New issues / bug reports (24h): none")
}
$report = $sb.ToString()
Set-Content -Path $RepFile -Value $report -Encoding utf8
Write-Host $report

($snap | ConvertTo-Json -Depth 4) | Set-Content -Path $SnapFile -Encoding utf8

# ---- 5. optional email (Gmail SMTP app password) ------------------------
if ($EmailTo -and $env:GMAIL_APP_PASSWORD) {
    $sec  = ConvertTo-SecureString $env:GMAIL_APP_PASSWORD -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($EmailFrom, $sec)
    Send-MailMessage -To $EmailTo -From $EmailFrom -Subject "Daily repo report $Today" `
        -Body $report -SmtpServer smtp.gmail.com -Port 587 -UseSsl -Credential $cred
    Write-Host "Emailed to $EmailTo"
}
