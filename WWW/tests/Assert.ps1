# Minimal assert helpers for the WWW tests (Pester is not installed here).
# Each helper throws on failure; the runner reports the first throw per file.

function Assert-Equal($Expected, $Actual, [string]$Msg = '') {
    if ($Expected -ne $Actual) {
        throw "Assert-Equal failed: expected <$Expected> got <$Actual>. $Msg"
    }
}

function Assert-True($Cond, [string]$Msg = '') {
    if (-not $Cond) { throw "Assert-True failed. $Msg" }
}

function Assert-Throws([scriptblock]$Block, [string]$Like = '*') {
    try { & $Block } catch {
        if ($_.Exception.Message -like $Like) { return }
        throw "Assert-Throws: message <$($_.Exception.Message)> not like <$Like>"
    }
    throw "Assert-Throws: no exception (wanted <$Like>)"
}

function New-TestDir {
    $d = Join-Path ([IO.Path]::GetTempPath()) ("www-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void][IO.Directory]::CreateDirectory($d)
    $d
}
