param(
    [Parameter(Mandatory=$true)]
    [string] $ProjectFile,
    [string] $Platform = "Win64",
    [string] $Config = "Debug"
)

# Build wrapper for Delphi 13 (Studio 37) using MSBuild
# Loads Embarcadero environment and invokes msbuild with proper settings

$RsVarsPath = "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if (-not (Test-Path $RsVarsPath)) {
    Write-Error "rsvars.bat not found at $RsVarsPath"
    exit 1
}

$ProjectPath = Resolve-Path $ProjectFile
Write-Host "[delphi-build] Building $Platform/$Config"
Write-Host "[delphi-build] Project: $ProjectPath"

# Create wrapper batch file
$WrapperBat = @"
@echo off
call "$RsVarsPath"
cd /d "$($ProjectPath.DirectoryName)"
msbuild /t:Build /p:Config=$Config /p:Platform=$Platform /v:normal "$ProjectPath"
exit /b %ERRORLEVEL%
"@

$TempBat = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.bat'
Set-Content $TempBat $WrapperBat -Encoding ASCII

try {
    $proc = Start-Process cmd.exe -ArgumentList "/c", $TempBat -NoNewWindow -PassThru -Wait
    $exitCode = $proc.ExitCode

    if ($exitCode -eq 0) {
        Write-Host "[delphi-build] BUILD_EXITCODE=0 (success)"
    } else {
        Write-Error "[delphi-build] BUILD_EXITCODE=$exitCode (failed)"
    }
    exit $exitCode
} finally {
    Remove-Item $TempBat -Force -ErrorAction SilentlyContinue
}
