<#
  run_dfm_grammar_corpus_ab.ps1 -- corpus A/B for the tree-sitter-DFM grammar DLL (150 row DF-F1,
  recreated by v152 VOPEN). Parses every text .dfm / .fmx of a corpus with two tree-sitter-dfm.dll
  builds -- A (base) and B (candidate) -- and compares which files parse with ERROR / MISSING nodes.

  WHY: the grammar repo has no test\corpus, and its node harness (tools\parse-corpus.js) needs node
  bindings that are not built in a worktree; the 149 DF lane's ad-hoc parse-corpus.bat was lost, so
  the 1.2.0 grammar (Unicode identifiers) shipped without its corpus A/B. This runner needs no
  compiler and no node: it loads tree-sitter.dll + the grammar DLL by FULL PATH through
  NativeLibrary in a child pwsh per side (a DLL of the same name never shadows the other side).

  Input bytes are decoded the way the engine decodes them (DRagLint.Core.Encoding.EnsureUtf8Bytes):
  UTF-8 BOM stripped, UTF-16 LE/BE transcoded, valid BOM-less UTF-8 unchanged, anything else read as
  Windows-1252. A binary .dfm (TPF0, bare or behind a .res header FF 0A 00) is classified BIN and never parsed.

  CHECKS
    C1 both sides classified the SAME file set, and it is not empty
    C2 POSITIVE CONTROL: every -ControlDfm file (default tests\fixtures\dfm-nonascii\*.dfm, the
       non-ASCII identifiers 1.2.0 fixed) is ERR on A and OK on B -- proves each side loaded the
       grammar it was given. Pass -NoControl when A and B are not that pair.
    C3 NO REGRESSION: every corpus file B fails, A fails too (new failures are listed)
  Exit 0 = PASS, 1 = FAIL, 2 = setup error (missing DLL / no corpus).

  Usage (pwsh 7, x64):
    pwsh -File tests\autotest\run_dfm_grammar_corpus_ab.ps1 -BaseDll <A\tree-sitter-dfm.dll> -LaneDll <B\tree-sitter-dfm.dll>
         [-CoreDll <tree-sitter.dll>] [-Roots <dir>,...] [-Manifest <file>] [-ControlDfm <file>,...] [-NoControl] [-OutDir <dir>]
#>
[CmdletBinding()]
param(
  [string]  $BaseDll,
  [string]  $LaneDll   = '',
  [string]  $CoreDll   = '',
  [string[]]$Roots     = @('C:\Program Files (x86)\Embarcadero\Studio\37.0\source',
                           'C:\Program Files (x86)\DevExpress\VCL',
                           'C:\Users\Public\Documents\Embarcadero\Studio\37.0\Samples'),
  [string]  $Manifest  = '',
  [string[]]$ControlDfm = @(),
  [switch]  $NoControl,
  [string]  $OutDir    = "C:\TEMP\draglint_dfm_corpus_ab_$PID",
  # worker mode (internal): parse -WorkList with -WorkDll, write -WorkOut
  [string]  $WorkDll   = '',
  [string]  $WorkList  = '',
  [string]  $WorkOut   = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $LaneDll) { $LaneDll = "$PSScriptRoot\..\..\third_party\dll-win64\tree-sitter-dfm.dll" }
if (-not $CoreDll) { $CoreDll = "$PSScriptRoot\..\..\third_party\dll-win64\tree-sitter.dll" }
if (-not $ControlDfm) { $ControlDfm = @("$PSScriptRoot\..\fixtures\dfm-nonascii\FormAnsi.dfm", "$PSScriptRoot\..\fixtures\dfm-nonascii\FormUtf8.dfm") }
$ErrorActionPreference = 'Stop'

$csharp = @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
public static class DfmAb {
  [StructLayout(LayoutKind.Sequential)]
  public struct TSNode { public uint c0, c1, c2, c3; public IntPtr id; public IntPtr tree; }
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr FnNoArg();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate bool FnSetLang(IntPtr p, IntPtr l);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr FnParse(IntPtr p, IntPtr old, byte[] s, uint n);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate TSNode FnRoot(IntPtr t);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate bool FnHasErr(TSNode n);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void FnDel(IntPtr t);
  static T F<T>(IntPtr lib, string name) { return Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(lib, name)); }

  // DRagLint.Core.Encoding.EnsureUtf8Bytes, same rules
  static bool ValidUtf8(byte[] b, int start) {
    int i = start, n = b.Length;
    while (i < n) {
      int b0 = b[i], extra; uint cp, min;
      if (b0 < 0x80) { i++; continue; }
      else if (b0 >= 0xC2 && b0 <= 0xDF) { extra = 1; cp = (uint)(b0 & 0x1F); min = 0x80; }
      else if (b0 >= 0xE0 && b0 <= 0xEF) { extra = 2; cp = (uint)(b0 & 0x0F); min = 0x800; }
      else if (b0 >= 0xF0 && b0 <= 0xF4) { extra = 3; cp = (uint)(b0 & 0x07); min = 0x10000; }
      else return false;
      if (i + extra >= n) return false;
      for (int j = 1; j <= extra; j++) { int c = b[i + j]; if ((c & 0xC0) != 0x80) return false; cp = (cp << 6) | (uint)(c & 0x3F); }
      if (cp < min || (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF) return false;
      i += extra + 1;
    }
    return true;
  }
  public static byte[] ToUtf8(byte[] b) {
    Encoding ansi = Encoding.GetEncoding(1252); // pwsh 7 registers the code-page provider
    if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
      byte[] r = new byte[b.Length - 3]; Array.Copy(b, 3, r, 0, r.Length);
      return ValidUtf8(r, 0) ? r : Encoding.UTF8.GetBytes(ansi.GetString(r));
    }
    if (b.Length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return Encoding.UTF8.GetBytes(Encoding.Unicode.GetString(b, 2, b.Length - 2));
    if (b.Length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return Encoding.UTF8.GetBytes(Encoding.BigEndianUnicode.GetString(b, 2, b.Length - 2));
    return ValidUtf8(b, 0) ? b : Encoding.UTF8.GetBytes(ansi.GetString(b));
  }

  public static void Run(string core, string grammar, string listFile, string outFile) {
    IntPtr c = NativeLibrary.Load(core), g = NativeLibrary.Load(grammar);
    var newParser = F<FnNoArg>(c, "ts_parser_new"); var setLang = F<FnSetLang>(c, "ts_parser_set_language");
    var parse = F<FnParse>(c, "ts_parser_parse_string"); var root = F<FnRoot>(c, "ts_tree_root_node");
    var hasErr = F<FnHasErr>(c, "ts_node_has_error"); var delTree = F<FnDel>(c, "ts_tree_delete");
    var lang = F<FnNoArg>(g, "tree_sitter_dfm")();
    IntPtr p = newParser();
    if (!setLang(p, lang)) throw new Exception("ts_parser_set_language refused " + grammar + " (ABI mismatch with " + core + ")");
    using (var w = new StreamWriter(outFile, false, new UTF8Encoding(false))) {
      foreach (string path in File.ReadAllLines(listFile)) {
        if (path.Trim() == "") continue;
        string verdict;
        try {
          byte[] raw = File.ReadAllBytes(path);
          if ((raw.Length >= 4 && raw[0] == (byte)'T' && raw[1] == (byte)'P' && raw[2] == (byte)'F' && raw[3] == (byte)'0') || (raw.Length >= 3 && raw[0] == 0xFF && raw[1] == 0x0A && raw[2] == 0x00)) verdict = "BIN"; // TPF0, or TPF0 inside a .res header (FF 0A 00)
          else {
            byte[] u = ToUtf8(raw);
            IntPtr t = parse(p, IntPtr.Zero, u, (uint)u.Length);
            if (t == IntPtr.Zero) verdict = "NOTREE";
            else { verdict = hasErr(root(t)) ? "ERR" : "OK"; delTree(t); }
          }
        } catch (IOException) { verdict = "UNREAD"; } catch (UnauthorizedAccessException) { verdict = "UNREAD"; }
        w.WriteLine(verdict + "\t" + path);
      }
    }
  }
}
'@

# ---------------- worker ----------------
if ($WorkDll -ne '') {
  Add-Type -TypeDefinition $csharp
  [DfmAb]::Run((Resolve-Path $CoreDll).Path, (Resolve-Path $WorkDll).Path, $WorkList, $WorkOut)
  exit 0
}

# ---------------- controller ----------------
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor (@('Red', 'Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
foreach ($pair in @(@('BaseDll', $BaseDll), @('LaneDll', $LaneDll), @('CoreDll', $CoreDll))) {
  if ([string]::IsNullOrWhiteSpace($pair[1]) -or -not (Test-Path -LiteralPath $pair[1])) {
    Write-Host "FATAL: -$($pair[0]) not found: '$($pair[1])'" -ForegroundColor Red; exit 2
  }
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

if ($Manifest -ne '') { $corpus = @(Get-Content -LiteralPath $Manifest | Where-Object { $_.Trim() -ne '' }) }
else {
  $corpus = @(foreach ($r in $Roots) {
    if (Test-Path -LiteralPath $r) { Get-ChildItem -LiteralPath $r -Recurse -File -Include *.dfm, *.fmx -ErrorAction SilentlyContinue | ForEach-Object FullName }
    else { Write-Host "  note: corpus root missing, skipped: $r" -ForegroundColor DarkGray }
  })
}
$controls = @(if ($NoControl) { @() } else { @($ControlDfm | Where-Object { $_ } | ForEach-Object { (Resolve-Path -LiteralPath $_).Path }) })
if ($corpus.Count -eq 0) { Write-Host 'FATAL: empty corpus (no root / manifest file found)' -ForegroundColor Red; exit 2 }
$list = Join-Path $OutDir 'list.txt'
[IO.File]::WriteAllLines($list, [string[]]($corpus + $controls))

$side = @{}
foreach ($s in @(@('A', $BaseDll), @('B', $LaneDll))) {
  $out = Join-Path $OutDir "corpus-$($s[0]).tsv"
  $t0 = Get-Date
  & { $ErrorActionPreference = 'Continue'; & pwsh -NoProfile -File $PSCommandPath -WorkDll $s[1] -WorkList $list -WorkOut $out -CoreDll $CoreDll 2>&1 | ForEach-Object { "$_" } } | Out-Host
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { Write-Host "FATAL: worker $($s[0]) failed (exit $LASTEXITCODE)" -ForegroundColor Red; exit 2 }
  $map = @{}
  foreach ($ln in [IO.File]::ReadAllLines($out)) { $f = $ln.Split("`t", 2); $map[$f[1]] = $f[0] }
  $side[$s[0]] = $map
  $cnt = $map.Values | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" }
  Write-Host ("  {0} {1}: {2} files in {3:n1} s: {4}" -f $s[0], $s[1], $map.Count, ((Get-Date) - $t0).TotalSeconds, ($cnt -join ' '))
}
$A = $side['A']; $B = $side['B']

Write-Host ''
Check "C1 both sides classified the same $($corpus.Count + $controls.Count) files" (($A.Count -eq $B.Count) -and ($A.Count -eq ($corpus.Count + $controls.Count)) -and ($corpus.Count -gt 0)) "A=$($A.Count) B=$($B.Count)"
foreach ($c in $controls) {
  Check "C2 control $([IO.Path]::GetFileName($c)): ERR on A, OK on B" (($A[$c] -eq 'ERR') -and ($B[$c] -eq 'OK')) "A=$($A[$c]) B=$($B[$c])"
}
$newFail = @($corpus | Where-Object { $B[$_] -in 'ERR', 'NOTREE' -and $A[$_] -notin 'ERR', 'NOTREE' })
$fixed   = @($corpus | Where-Object { $A[$_] -in 'ERR', 'NOTREE' -and $B[$_] -eq 'OK' })
Check "C3 no regression: files B fails that A parsed = $($newFail.Count)" ($newFail.Count -eq 0) (($newFail | Select-Object -First 10) -join '; ')
Write-Host ("  info: fixed by B {0}; failing on both {1}; outputs {2}" -f $fixed.Count, @($corpus | Where-Object { $A[$_] -eq 'ERR' -and $B[$_] -eq 'ERR' }).Count, $OutDir)
[IO.File]::WriteAllLines((Join-Path $OutDir 'new-failures.txt'), [string[]]$newFail)
[IO.File]::WriteAllLines((Join-Path $OutDir 'fixed.txt'), [string[]]$fixed)

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
