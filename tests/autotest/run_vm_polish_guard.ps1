<#
  run_vm_polish_guard.ps1 -- bug-fix wave 1.31.5 lane 1 (found on a clean Delphi-5 VM).

  V-A  A binary .dfm (FF 0A 00 'THTTPSERVER' 00 ... 'TPF0') must be reported with
       TDFMParser's own diagnostic ("binary DFM (TPF0) -- save as Text DFM ...") and
       NOT as "parse error (1,1)". EnsureUtf8Bytes used to transcode the leading $FF
       as CP1252 (C3 BF), so the parser's $FF guard missed.
  V-B  `index` must not write "FTS5 probe: AVAILABLE" to stderr (PowerShell 5.1 shows
       stderr of a native command as a red NativeCommandError). A healthy probe prints
       nothing on stderr; only UNAVAILABLE (a real problem) may.

  Controls:
    P1  a TEXT dfm in the same folder is indexed with no diagnostic (the fix must not
        turn every dfm into a "binary" one).
    P2  the binary dfm is still not indexed as a form (no rows), i.e. the fix did
        not make the parser accept it.
  Run from a neutral CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_vmpolish_{0}' -f [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null
$ascii = New-Object System.Text.ASCIIEncoding

# Binary DFM: resource header FF 0A 00 'THTTPSERVER' 00 then a TPF0 stream.
$bin = [System.Collections.Generic.List[byte]]::new()
$bin.AddRange([byte[]](0xFF,0x0A,0x00))
$bin.AddRange($ascii.GetBytes('THTTPSERVER'))
$bin.AddRange([byte[]](0x00,0x30,0x10,0x00,0x00))
$bin.AddRange($ascii.GetBytes('TPF0'))
$bin.AddRange([byte[]](0x0B)); $bin.AddRange($ascii.GetBytes('THTTPSERVER'))
$bin.AddRange([byte[]](0x0B)); $bin.AddRange($ascii.GetBytes('HTTPServer1'))
$bin.AddRange([byte[]](0x00,0x00))
[System.IO.File]::WriteAllBytes((Join-Path $src 'uBinForm.dfm'), $bin.ToArray())
[System.IO.File]::WriteAllText((Join-Path $src 'uBinForm.pas'),
  "unit uBinForm;`r`n`r`ninterface`r`n`r`ntype`r`n  TBinForm = class`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n",
  (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $src 'uTxtForm.dfm'),
  "object TxtForm: TTxtForm`r`n  Left = 0`r`n  Caption = 'text form'`r`nend`r`n",
  (New-Object System.Text.UTF8Encoding($false)))

$db = Join-Path $scratch 't.sqlite'
$errFile = Join-Path $scratch 'stderr.txt'
$outFile = Join-Path $scratch 'stdout.txt'
$p = Start-Process -FilePath $exePath -ArgumentList @('index',"`"$src`"",'--db',"`"$db`"") `
  -RedirectStandardOutput $outFile -RedirectStandardError $errFile -NoNewWindow -Wait -PassThru
$so = Get-Content -Raw $outFile; $se = Get-Content -Raw $errFile
if (-not $so) { $so = '' }; if (-not $se) { $se = '' }
$all = $so + "`n" + $se

Write-Host "`n--- V-A: binary DFM diagnostic ---" -ForegroundColor Cyan
Check 'V-A binary-DFM diagnostic appears' ([bool]($all -match 'binary DFM \(TPF0\) -- save as Text DFM')) $all
Check 'V-A no "parse error" for the binary dfm' (-not ($all -match 'parse error')) $all
Check 'P2 binary dfm yields no object rows' `
  (-not ((& $exePath query --text 'HTTPServer1' --db $db --source dfm 2>&1 | Out-String) -match 'uBinForm\.dfm')) ''

Write-Host "`n--- positive control ---" -ForegroundColor Cyan
Check 'P1 text dfm indexed' `
  ((& $exePath query --text 'text form' --db $db --source dfm 2>&1 | Out-String) -match 'uTxtForm\.dfm') $all
Check 'P1b diagnostic names only the binary file' (-not ($all -match 'uTxtForm\.dfm[^\r\n]*(binary|parse error)')) $all

Write-Host "`n--- V-B: FTS5 probe not on stderr ---" -ForegroundColor Cyan
Check 'V-B stderr has no "FTS5 probe: AVAILABLE"' (-not ($se -match 'FTS5 probe: AVAILABLE')) $se

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
