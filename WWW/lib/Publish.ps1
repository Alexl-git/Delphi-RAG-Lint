# Publish helpers: pure planning functions (tested) and the WinSCP transfer calls.
# Credentials and the upload manifest live under %APPDATA%\delphi-rag-lint-www\, never in the repo.

$script:PublishDir = Join-Path $env:APPDATA 'delphi-rag-lint-www'
$script:CredPath = Join-Path $script:PublishDir 'ftp.xml'
$script:ManifestPath = Join-Path $script:PublishDir 'manifest.json'

# Upload = new or changed paths; Delete = old-manifest paths that are gone, never anything else.
# $OldManifest is the hashtable saved by the last publish (path -> SHA-256), or a bare path list,
# in which case nothing is known to be unchanged and every surviving path is uploaded.
function Get-PublishPlan($OldManifest, [hashtable]$NewFiles) {
    $old = @{}
    if ($OldManifest -is [System.Collections.IDictionary]) {
        foreach ($k in $OldManifest.Keys) { $old[[string]$k] = [string]$OldManifest[$k] }
    } else {
        foreach ($k in @($OldManifest)) { if ($k) { $old[[string]$k] = $null } }
    }
    $upload = @($NewFiles.Keys | Where-Object { -not $old.ContainsKey($_) -or $null -eq $old[$_] -or $old[$_] -ne [string]$NewFiles[$_] } | Sort-Object)
    $delete = @($old.Keys | Where-Object { -not $NewFiles.ContainsKey($_) } | Sort-Object)
    [pscustomobject]@{ Upload = $upload; Delete = $delete }
}

# True when the remote root is empty or holds only the IONOS placeholder page.
function Test-FirstPublishTarget([string[]]$RemoteNames) {
    foreach ($n in @($RemoteNames | Where-Object { $_ })) {   # an empty listing arrives as $null
        if ($n -notmatch '^(index|default)\.(html?|aspx?|php)$') { return $false }
    }
    $true
}

# Throws unless the credential object is complete and uses an encrypted protocol.
function Test-PublishCredential($Cred) {
    if ($Cred.Protocol -notin 'ftps', 'sftp') { throw "Protocol '$($Cred.Protocol)' refused: use ftps or sftp, never plain ftp" }
    foreach ($k in 'Host', 'User', 'RemoteRoot') { if (-not $Cred.$k) { throw "credential field $k is empty" } }
    if (-not ($Cred.Password -is [securestring])) { throw 'credential Password must be a SecureString' }
    if ([int]$Cred.Port -le 0) { throw 'credential Port must be a positive number' }
    if ($Cred.Protocol -eq 'ftps' -and -not $Cred.TlsFingerprint) { throw 'ftps needs TlsFingerprint (the server certificate fingerprint)' }
    if ($Cred.Protocol -eq 'sftp' -and -not $Cred.HostKey) { throw 'sftp needs HostKey (the SSH host key fingerprint)' }
    $true
}

function Read-PublishCredential { if (Test-Path -LiteralPath $script:CredPath) { Import-Clixml -LiteralPath $script:CredPath } }

function Request-PublishCredential {
    $proto = (Read-Host 'Protocol (ftps or sftp)').Trim().ToLowerInvariant()
    $cred = [pscustomobject]@{
        Protocol       = $proto
        Host           = (Read-Host 'Host').Trim()
        Port           = [int](Read-Host "Port (enter for $(if ($proto -eq 'sftp') { 22 } else { 21 }))")
        User           = (Read-Host 'User').Trim()
        Password       = (Read-Host 'Password' -AsSecureString)
        RemoteRoot     = (Read-Host 'Remote web root folder, e.g. /').Trim()
        HostKey        = ''
        TlsFingerprint = ''
    }
    if ($cred.Port -le 0) { $cred.Port = if ($proto -eq 'sftp') { 22 } else { 21 } }
    if ($proto -eq 'sftp') { $cred.HostKey = (Read-Host 'SSH host key fingerprint (ssh-ed25519 255 ...)').Trim() }
    else { $cred.TlsFingerprint = (Read-Host 'TLS certificate SHA-256 fingerprint (aa:bb:...)').Trim() }
    [void](Test-PublishCredential $cred)
    [void][IO.Directory]::CreateDirectory($script:PublishDir)
    $cred | Export-Clixml -LiteralPath $script:CredPath   # DPAPI: readable by this Windows user only
    $cred
}

# Relative path (forward slashes) -> SHA-256 for every file under $Dir.
function Get-SiteHashes([string]$Dir) {
    $root = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\') + '\'
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Recurse -File) {
        $h[$f.FullName.Substring($root.Length).Replace('\', '/')] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    $h
}

# The manifest {Host; RemoteRoot; NoRewrite; Files} is bound to host + root:
# a different target reads as "no manifest". NoRewrite remembers that IIS lacks URL Rewrite.
function Read-PublishManifest($Cred) {
    if (-not (Test-Path -LiteralPath $script:ManifestPath)) { return $null }
    $m = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json -AsHashtable
    if ($m.Host -ne $Cred.Host -or $m.RemoteRoot -ne $Cred.RemoteRoot) { return $null }
    $m
}

function Write-PublishManifest($Cred, [hashtable]$Files, [bool]$NoRewrite) {
    [void][IO.Directory]::CreateDirectory($script:PublishDir)
    $json = [ordered]@{ Host = $Cred.Host; RemoteRoot = $Cred.RemoteRoot; NoRewrite = $NoRewrite; Files = $Files } | ConvertTo-Json -Depth 3
    [IO.File]::WriteAllText($script:ManifestPath, $json, [Text.ASCIIEncoding]::new())
}

function Import-WinScp {
    $dirs = "${env:ProgramFiles(x86)}\WinSCP", "$env:ProgramFiles\WinSCP", "$env:LOCALAPPDATA\Programs\WinSCP"
    foreach ($d in $dirs) {
        foreach ($p in "$d\netstandard2.0\WinSCPnet.dll", "$d\WinSCPnet.dll") {
            if (Test-Path -LiteralPath $p) { Add-Type -LiteralPath $p; return $d }
        }
    }
    throw 'WinSCPnet.dll not found: install WinSCP with "winget install WinSCP.WinSCP"'
}

function Open-PublishSession($Cred) {
    $dir = Import-WinScp
    $o = New-Object WinSCP.SessionOptions
    $o.HostName = $Cred.Host
    $o.PortNumber = [int]$Cred.Port
    $o.UserName = $Cred.User
    $o.SecurePassword = $Cred.Password
    if ($Cred.Protocol -eq 'sftp') {
        $o.Protocol = [WinSCP.Protocol]::Sftp
        $o.SshHostKeyFingerprint = $Cred.HostKey
    } else {
        $o.Protocol = [WinSCP.Protocol]::Ftp
        $o.FtpSecure = [WinSCP.FtpSecure]::Explicit
        $o.TlsHostCertificateFingerprint = $Cred.TlsFingerprint
    }
    $s = New-Object WinSCP.Session
    $exe = Join-Path $dir 'WinSCP.exe'
    if (Test-Path -LiteralPath $exe) { $s.ExecutablePath = $exe }
    [void][IO.Directory]::CreateDirectory($script:PublishDir)
    $s.SessionLogPath = Join-Path $script:PublishDir 'winscp-session.log'
    $s.Open($o)
    $s
}

function Join-RemotePath([string]$Root, [string]$Rel) { ($Root.TrimEnd('/') + '/' + $Rel) }

function Get-RemoteNames($Session, [string]$Root) {
    @($Session.ListDirectory($Root).Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' } | ForEach-Object Name)
}

function Send-PublishFile($Session, [string]$Root, [string]$LocalPath, [string]$Rel) {
    $t = New-Object WinSCP.TransferOptions
    $t.TransferMode = [WinSCP.TransferMode]::Binary
    $Session.PutFiles($Session.EscapeFileMask($LocalPath), (Join-RemotePath $Root $Rel), $false, $t).Check()
    Write-Host "  put $Rel"
}

function Send-PublishFiles($Session, [string]$Root, [string]$LocalDir, [string[]]$Paths) {
    $t = New-Object WinSCP.TransferOptions
    $t.TransferMode = [WinSCP.TransferMode]::Binary
    $made = @{}
    foreach ($rel in $Paths) {
        $parts = $rel.Split('/')
        for ($i = 1; $i -lt $parts.Length; $i++) {
            $d = Join-RemotePath $Root ($parts[0..($i - 1)] -join '/')
            if (-not $made[$d]) {
                if (-not $Session.FileExists($d)) { $Session.CreateDirectory($d) }
                $made[$d] = $true
            }
        }
        $local = Join-Path $LocalDir ($rel.Replace('/', '\'))
        $Session.PutFiles($Session.EscapeFileMask($local), (Join-RemotePath $Root $rel), $false, $t).Check()
        Write-Host "  put $rel"
    }
}

function Remove-PublishFile($Session, [string]$Root, [string]$Rel) {
    $r = Join-RemotePath $Root $Rel
    if ($Session.FileExists($r)) { $Session.RemoveFiles($Session.EscapeFileMask($r)).Check(); Write-Host "  del $Rel" }
    else { Write-Host "  del $Rel (already gone)" }
}

# Runs the plan one file at a time and calls $Save with the manifest after EVERY step,
# so a publish that dies half-way still records exactly what is on the server.
# $Put / $Remove = { param($rel) }; $Save = { param([hashtable]$files) }. Returns the final manifest.
function Invoke-PublishPlan($Plan, [hashtable]$OldFiles, [hashtable]$NewFiles, [scriptblock]$Put, [scriptblock]$Remove, [scriptblock]$Save) {
    $state = if ($OldFiles) { $OldFiles.Clone() } else { @{} }
    foreach ($rel in @($Plan.Upload)) { & $Put $rel; $state[$rel] = $NewFiles[$rel]; & $Save $state }
    foreach ($rel in @($Plan.Delete)) { & $Remove $rel; $state.Remove($rel); & $Save $state }
    $state
}

# Remote folders left empty by the deletes, deepest first; the root is never one of them.
function Get-EmptiedRemoteDirs([string[]]$Deleted, [string[]]$Remaining) {
    $dirs = @{}
    foreach ($p in @($Deleted)) {
        $parts = $p.Split('/')
        for ($i = $parts.Length - 1; $i -ge 1; $i--) { $dirs[($parts[0..($i - 1)] -join '/')] = $true }
    }
    @($dirs.Keys | Where-Object { $d = "$_/"; -not @($Remaining | Where-Object { $_.StartsWith($d) }).Count } |
        Sort-Object @{ Expression = { $_.Split('/').Length }; Descending = $true }, @{ Expression = { $_ } })
}

function Remove-EmptiedRemoteDirs($Session, [string]$Root, [string[]]$Dirs) {
    foreach ($d in $Dirs) {
        $r = Join-RemotePath $Root $d
        if (-not $Session.FileExists($r)) { continue }
        $left = @($Session.ListDirectory($r).Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' })
        if ($left.Count -eq 0) { $Session.RemoveFiles($Session.EscapeFileMask($r)).Check(); Write-Host "  rmdir $d" }
    }
}

# HTTP status, Location and body of one GET, redirects not followed.
# A DNS, TLS or connection failure is Status 0, never an exception.
function Get-HttpStatus([string]$Url) {
    # HttpClient, not Invoke-WebRequest: pwsh 7.6 IWR -MaximumRedirection 0 throws on any 3xx
    $h = [Net.Http.HttpClientHandler]::new(); $h.AllowAutoRedirect = $false
    $c = [Net.Http.HttpClient]::new($h); $c.Timeout = [TimeSpan]::FromSeconds(30)
    try {
        $r = $c.GetAsync($Url).GetAwaiter().GetResult()
        $loc = if ($r.Headers.Location) { $r.Headers.Location.OriginalString } else { '' }
        [pscustomobject]@{ Status = [int]$r.StatusCode; Location = $loc; Content = $r.Content.ReadAsStringAsync().GetAwaiter().GetResult() }
    } catch {
        [pscustomobject]@{ Status = 0; Location = ''; Content = ''; Error = $_.Exception.Message }
    } finally { $c.Dispose() }
}

# True when the bare http URL redirects to $BaseUrl/... . 302 counts: the IONOS .htaccess
# add-on answers 302 whatever the R= flag (owner 2026-10-20: accept it).
function Test-LiveRedirect($Response, [string]$BaseUrl) {
    $Response.Status -in 301, 302 -and ([string]$Response.Location).StartsWith("$BaseUrl/")
}

# True only when the response is OUR home page (200 and our canonical link), so a
# placeholder that IIS still serves with 200 is not mistaken for a successful publish.
function Test-LiveHome($Response, [string]$BaseUrl) {
    $Response.Status -eq 200 -and ([string]$Response.Content).Contains("<link rel=""canonical"" href=""$BaseUrl/"">")
}

# True only when a missing page answers 404 with OUR not-found page: a 200 is a soft 404
# (search engines index it), and the host's own 404 page means web.config's httpErrors was ignored.
function Test-LiveNotFound($Response) {
    $Response.Status -eq 404 -and ([string]$Response.Content).Contains('<title>Page not found - Delphi-RAG-Lint</title>')
}

# The HTTP 500 fallback: upload the prepared rewrite-free web.config (no rebuild, no gh),
# probe again, and keep NoRewrite only if the site now answers 200.
# $Put = { param($localPath, $relPath) }; $Probe = { -> status code }.
# Returns {NoRewrite; Status; Files} where Files is a copy of $Files with only the
# web.config entry changed to what is now on the server.
function Invoke-RewriteFallback([hashtable]$Files, [string]$WebConfigText, [scriptblock]$Put, [scriptblock]$Probe) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("web-norewrite-" + [guid]::NewGuid().ToString('N') + '.config')
    try {
        [IO.File]::WriteAllText($tmp, $WebConfigText, [Text.ASCIIEncoding]::new())
        & $Put $tmp 'web.config'
        $out = $Files.Clone()
        $out['web.config'] = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    } finally {
        [IO.File]::Delete($tmp)
    }
    $status = [int](& $Probe)
    [pscustomobject]@{ NoRewrite = ($status -eq 200); Status = $status; Files = $out }
}
