# Re-creates the apply/1 captures of the "code-only inherited use" project (B10, 2026-10-23) from text and
# re-runs the same convert-apply commands.
#
# Usage: pwsh -NoProfile -File recapture.ps1 -Pin <pin dir> [-OutDir <dir>] [-Library <library-Win64.sqlite>]
#   -Pin      a pinned engine dir (third_party\engine-pinned\<version>-<stamp>): exe, tree-sitter DLLs, casts.castlib
#             and rules\ are copied into a scratch STAGE; the pin itself and dll-win64 are never run.
#   -OutDir   where the captures are written (default: this folder, i.e. the checked-in fixtures).
#   -Library  the Win64 library index (read-only --db). Default: C:\Projects\.drag-lint\library-Win64.sqlite.
# The staged engine gets its OWN drag-lint.json (indexes.outDir = the scratch stage, no sections), so no real
# project DB is touched; the project is indexed into its own scratch Fix.sqlite.
#
# Project: Anc.pas/.dfm (TAncForm, Label1: TLabel), Desc.pas/.dfm (TDescForm = class(TAncForm); the .dfm has NO
# Label1 block, but Desc.pas reads Label1.Caption in code) -- the engine's inherited_code_unconverted case.
# Book: #convert TLabel -> TStaticText.
# Captured: apply-desc-code-unconverted-1330.json  (Desc converted alone: ancestor_state unconverted, action code)
#           apply-desc-code-converted-1330.json    (Anc converted first, then Desc: ancestor_state converted)
# Normalisation: the scratch project dir -> C:\fix (JSON-escaped), uses_reindex.ms -> 0. Nothing else is touched.
param([Parameter(Mandatory = $true)][string]$Pin, [string]$OutDir = $PSScriptRoot,
      [string]$Library = 'C:\Projects\.drag-lint\library-Win64.sqlite', [string]$Work = '')
$ErrorActionPreference = 'Stop'
function WriteAscii($path, $text) { [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.ASCIIEncoding]::new()) }
if (-not (Test-Path -LiteralPath (Join-Path $Pin 'drag-lint.exe'))) { throw "no drag-lint.exe in $Pin" }
if (-not (Test-Path -LiteralPath $Library)) { throw "library index not found: $Library" }
if ($Work -eq '') { $Work = [IO.Path]::GetTempPath() }
$work = Join-Path $Work ('inherited-recapture-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work 'stage'; [void][IO.Directory]::CreateDirectory($stage)
foreach ($f in Get-ChildItem -LiteralPath $Pin -File) { if ($f.Name -ne 'ConvRulesEditor.exe') { Copy-Item -LiteralPath $f.FullName -Destination $stage } }
if (Test-Path -LiteralPath (Join-Path $Pin 'rules')) { Copy-Item -LiteralPath (Join-Path $Pin 'rules') -Destination $stage -Recurse }
$idxDir = (Join-Path $stage 'idx') -replace '\\', '\\'
WriteAscii (Join-Path $stage 'drag-lint.json') ('{ "settings": { "currentProjectsIndexing": "perProject", "defaultPlatform": "Win64", "enginePath": "auto" }, "indexes": { "outDir": "' + $idxDir + '", "sections": [] } }')
$engine = Join-Path $stage 'drag-lint.exe'
$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $engine).Hash
$ver = (Get-Content -Raw -LiteralPath (Join-Path $Pin 'ENGINE-PIN.json') | ConvertFrom-Json).version_string
$pinName = Split-Path -Leaf $Pin

function RunEngine($cwd, [string[]]$a) {
  $psi = [Diagnostics.ProcessStartInfo]::new($engine)
  $psi.WorkingDirectory = $cwd; $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  foreach ($x in $a) { [void]$psi.ArgumentList.Add($x) }
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $errTask.Result }
}

$files = @{
  'Fix.dpr'   = "program Fix;`nuses`n  Vcl.Forms,`n  Anc in 'Anc.pas' {AncForm},`n  Desc in 'Desc.pas' {DescForm};`nbegin`nend."
  'Anc.pas'   = "unit Anc;`ninterface`nuses`n  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes;`ntype`n  TAncForm = class(TForm)`n    Label1: TLabel;`n  end;`nimplementation`n{`$R *.dfm}`nend."
  'Anc.dfm'   = "object AncForm: TAncForm`n  object Label1: TLabel`n    Caption = 'Hello'`n  end`nend"
  'Desc.pas'  = "unit Desc;`ninterface`nuses`n  Anc;`ntype`n  TDescForm = class(TAncForm)`n    procedure Say;`n  end;`nimplementation`n{`$R *.dfm}`nprocedure TDescForm.Say;`nbegin`n  Label1.Caption := 'Desc';`nend;`nend."
  'Desc.dfm'  = "inherited DescForm: TDescForm`nend"
  'Fix.rules' = "#convert Vcl.StdCtrls.TLabel -> Vcl.StdCtrls.TStaticText, Vcl.StdCtrls`n#link Caption <- Caption"
}
$cases = @(
  @{ Out = 'apply-desc-code-unconverted-1330.json'; Units = @('Desc.pas')
     Note = 'Desc.pas converted ALONE; its ancestor Anc still has TLabel Label1; Desc.dfm has no Label1 block, Desc.pas reads Label1.Caption (code-only use).' }
  @{ Out = 'apply-desc-code-converted-1330.json'; Units = @('Anc.pas', 'Desc.pas')
     Note = 'Anc.pas converted first (apply), then Desc.pas (the capture is the Desc.pas run); same code-only use, ancestor now converted.' }
)
[void][IO.Directory]::CreateDirectory($OutDir)
foreach ($c in $cases) {
  $dir = Join-Path $work ($c.Out -replace '\.json$', '')
  [void][IO.Directory]::CreateDirectory($dir)
  foreach ($k in $files.Keys) { WriteAscii (Join-Path $dir $k) $files[$k] }
  Copy-Item -LiteralPath (Join-Path $stage 'casts.castlib') -Destination $dir
  $ix = RunEngine $dir @('index', '--project', 'Fix.dpr', '--db', 'Fix.sqlite')
  if ($ix.Code -ne 0) { throw "index failed ($($ix.Code)) for $($c.Out): $($ix.Err) $($ix.Out)" }
  $r = $null
  foreach ($u in $c.Units) {
    $r = RunEngine $dir @('convert-apply', '--unit', $u, '--rules', 'Fix.rules', '--db', 'Fix.sqlite', '--db', $Library,
                          '--castlib', 'casts.castlib', '--apply', '--format', 'json')
    $json = $r.Out.Trim()
    if (-not $json.StartsWith('{')) { throw "no JSON from convert-apply $u for $($c.Out) (exit $($r.Code)): $($r.Err) $json" }
  }
  $dirEsc = $dir -replace '\\', '\\'
  $json = $json.Replace($dirEsc, 'C:\\fix')
  $json = [regex]::Replace($json, '("uses_reindex":\{[^}]*"ms":)\d+', '${1}0')
  $note = "RECAPTURE by recapture.ps1 (engine $ver pin $pinName sha256 $sha, exit code $($r.Code)). stdout of the last convert-apply only. Command: index --project Fix.dpr --db Fix.sqlite, then convert-apply --unit <u> --rules Fix.rules --db Fix.sqlite --db library-Win64.sqlite --castlib casts.castlib --apply --format json. $($c.Note) Temp paths replaced by C:\fix\; uses_reindex.ms zeroed." -replace '\\', '\\'
  $out = '{"_note":"' + $note + '",' + $json.Substring(1) + "`r`n"
  [IO.File]::WriteAllText((Join-Path $OutDir $c.Out), $out, [Text.ASCIIEncoding]::new())
  Write-Host ("{0}: exit {1}, {2} chars" -f $c.Out, $r.Code, $out.Length)
}
Write-Host "scratch kept at $work"
