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
    foreach ($n in @($RemoteNames)) {
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

function Remove-PublishFiles($Session, [string]$Root, [string[]]$Paths) {
    foreach ($rel in $Paths) {
        $r = Join-RemotePath $Root $rel
        if ($Session.FileExists($r)) { $Session.RemoveFiles($Session.EscapeFileMask($r)).Check() }
        Write-Host "  del $rel"
    }
}

# HTTP status, Location and body of one GET, redirects not followed.
function Get-HttpStatus([string]$Url) {
    $r = Invoke-WebRequest -Uri $Url -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue
    [pscustomobject]@{ Status = [int]$r.StatusCode; Location = [string]($r.Headers['Location'] | Select-Object -First 1); Content = [string]$r.Content }
}

# True only when the response is OUR home page (200 and our canonical link), so a
# placeholder that IIS still serves with 200 is not mistaken for a successful publish.
function Test-LiveHome($Response, [string]$BaseUrl) {
    $Response.Status -eq 200 -and ([string]$Response.Content).Contains("<link rel=""canonical"" href=""$BaseUrl/"">")
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
