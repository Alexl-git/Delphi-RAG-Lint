<#
  run_implementors_output_encoding.ps1 --
  `implementors --output` obeys --output-encoding and never writes a BOM (1.44 C16).

  THE STATE IT REPLACES. DoImplementors wrote its report with
  TFile.WriteAllText(..., TEncoding.UTF8): EF BB BF at byte 0 whatever
  --output-encoding said. Every other --output writer goes through
  WriteOutputFile (DRagLint.Core.OutputEncoding).

  POSITIVE CONTROL. The report must be non-empty and must name the implementing
  class (a vacuous empty file has no BOM either), and a utf16 run must really
  differ from the ascii run (the option is wired, not ignored).

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_impl_outenc_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uFixE.pas') @"
unit uFixE;

interface

type
  IWorker = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Work: Integer;
  end;

  TWorkerAlpha = class(TInterfacedObject, IWorker)
  public
    function Work: Integer;
  end;

implementation

function TWorkerAlpha.Work: Integer;
begin
  Result := 1;
end;

end.
"@

$db = Join-Path $WorkDir 'fx.sqlite'
& $exePath index $src --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

function Run([string]$Name, [string[]]$Extra) {
  $out = Join-Path $WorkDir $Name
  & $exePath implementors --target IWorker --db $db --output $out @Extra 2>&1 | Out-Null
  if (Test-Path $out) { return ,[IO.File]::ReadAllBytes($out) } else { return ,[byte[]]@() }
}
function HasBom([byte[]]$b) { return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }

foreach ($fmt in 'text','json') {
  $a = Run "a_$fmt.out" @('--format', $fmt)
  Check "V2 POSITIVE CONTROL [$fmt] default run wrote a report naming TWorkerAlpha" `
        ($a.Length -gt 0 -and ([Text.Encoding]::ASCII.GetString($a) -match 'TWorkerAlpha')) ("len=" + $a.Length)
  Check "C16 [$fmt] default (ascii) output has no UTF-8 BOM" (-not (HasBom $a)) ('first bytes: ' + (($a | Select-Object -First 3 | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
  Check "C16 [$fmt] default output is pure 7-bit ASCII" (@($a | Where-Object { $_ -ge 0x80 }).Count -eq 0)

  $u8 = Run "u8_$fmt.out" @('--format', $fmt, '--output-encoding', 'utf8')
  Check "C16 [$fmt] utf8 output has no BOM" ($u8.Length -gt 0 -and -not (HasBom $u8))

  $u16 = Run "u16_$fmt.out" @('--format', $fmt, '--output-encoding', 'utf16')
  Check "C16 [$fmt] utf16 output is UTF-16LE (option is honoured): twice the ascii length, no BOM" `
        ($u16.Length -ge 2 * $a.Length - 8 -and $u16.Length -gt 0 -and $u16[1] -eq 0 -and -not (HasBom $u16) -and -not ($u16[0] -eq 0xFF -and $u16[1] -eq 0xFE)) `
        ("len=" + $u16.Length + " vs ascii " + $a.Length)
}
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
