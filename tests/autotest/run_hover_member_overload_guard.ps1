#Requires -Version 7
<#
  run_hover_member_overload_guard.ps1 -- the member a dotted call site means is
  picked by the call's ARGUMENT COUNT, across the receiver type and its
  ancestors, before visibility (1.52.2 HOVER lane; INBOX
  lsp-proxy-merge-diagnostics-drops-draglint "WRONG drag-lint part on an
  overload").

  Owner case: `Doc.Format(2)` with Doc: TJSONArray. TJSONArray declares a
  PROTECTED Format(Builder; ParentIdent, Ident) (3 parameters); the call means
  TJSONAncestor.Format(Indentation: Integer = 4) (0..1 parameters). The member
  lookup took the first Format on the receiver's own class. typeat and hover
  share that lookup (TTypeAtResolver -> TLSPServer.SelectSymbolAt), so typeat
  --format json pins it.

  Cases (fixture Ovl.pas, TBase <- TMid <- TLeaf):
    1 L.Format(2)            -> TBase.Format   (1 arg: only the ancestor's fits)
    2 L.Format(Sb, 'a', 'b') -> TLeaf.Format   (3 args: the own overload fits)
    3 L.Format()             -> TBase.Format   (0 args: the default parameter)
    4 L.Format(Sb, / 'a', 'b') -> TLeaf.Format (3 args over 2 lines)
    6 L.Format( / 2 / )      -> TBase.Format   (1.52.3 HOVER-OVL: 1 arg over 3 lines,
                                               a comment inside; before the fix the
                                               count stopped at the line end: TLeaf)
    5 L.Done(1, 2)           -> TLeaf.Done     (nothing fits: nearest as before)
  Positive control: case 2 and case 4 must still answer the leaf's own member,
  so a lookup that always skips the receiver class fails.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\draglint_hover_overload_$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

Write-Host ''
Write-Host 'run_hover_member_overload_guard -- dotted member picked by argument count' -ForegroundColor Cyan

$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null
$unit = Join-Path $src 'Ovl.pas'
$lines = @(
  'unit Ovl;',                                                                  # 1
  '',                                                                           # 2
  'interface',                                                                  # 3
  '',                                                                           # 4
  'type',                                                                       # 5
  '  TBase = class',                                                            # 6
  '  public',                                                                   # 7
  '    function Format(Indentation: Integer = 4): string; overload;',           # 8
  '  end;',                                                                     # 9
  '  TMid = class(TBase)',                                                      # 10
  '  end;',                                                                     # 11
  '  TLeaf = class(TMid)',                                                     # 12
  '  protected',                                                                # 13
  '    procedure Format(Builder: TObject; const ParentIdent, Ident: string); overload;',  # 14
  '    procedure Done;',                                                        # 15
  '  end;',                                                                     # 16
  '',                                                                           # 17
  'procedure Use(L: TLeaf; Sb: TObject);',                                      # 18
  '',                                                                           # 19
  'implementation',                                                             # 20
  '',                                                                           # 21
  'function TBase.Format(Indentation: Integer): string; begin Result:= ''''; end;',   # 22
  'procedure TLeaf.Format(Builder: TObject; const ParentIdent, Ident: string); begin end;',  # 23
  'procedure TLeaf.Done; begin end;',                                           # 24
  '',                                                                           # 25
  'procedure Use(L: TLeaf; Sb: TObject);',                                      # 26
  'begin',                                                                      # 27
  '  L.Format(2);',                                                             # 28
  '  L.Format(Sb, ''a'', ''b'');',                                              # 29
  '  L.Format();',                                                              # 30
  '  L.Format(Sb,',                                                             # 31
  '    ''a'', ''b'');',                                                         # 32
  '  L.Format(',                                                                # 33  1.52.3 HOVER-OVL: a 3-line call
  '    2 { one argument }',                                                     # 34
  '  );',                                                                       # 35
  '  L.Done(1, 2);',                                                            # 36
  'end;',                                                                       # 37
  '',                                                                           # 38
  'end.',                                                                       # 39
  '')
[IO.File]::WriteAllText($unit, ($lines -join "`r`n"), [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'ovl.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $src --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'fixture index built' (Test-Path $db)

function TypeAt([int]$line, [int]$col) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe typeat "$($unit):$($line):$($col)" --format json --db $db 2>$null } | Out-String
  try { return ($raw | ConvertFrom-Json | ForEach-Object { $_ }) } catch { return $null }
}
# col = 1-based column inside the member name ("  L.Format" -> F at 5).
$cases = @(
  @{ N = '1 L.Format(2): the ancestor''s 0..1-parameter Format';          L = 28; C = 6; W = 'Ovl.TBase.Format' },
  @{ N = '2 L.Format(Sb, ''a'', ''b''): the leaf''s own 3-parameter Format'; L = 29; C = 6; W = 'Ovl.TLeaf.Format' },
  @{ N = '3 L.Format(): the default parameter fits the ancestor''s';       L = 30; C = 6; W = 'Ovl.TBase.Format' },
  @{ N = '4 L.Format(Sb, / ''a'', ''b''): 3 args over 2 lines: the leaf''s';  L = 31; C = 6; W = 'Ovl.TLeaf.Format' },
  @{ N = '6 L.Format( / 2 / ): 1 arg over 3 lines: the ancestor''s (HOVER-OVL)'; L = 33; C = 6; W = 'Ovl.TBase.Format' },
  @{ N = '5 L.Done(1, 2): nothing fits: nearest, as before';               L = 36; C = 5; W = 'Ovl.TLeaf.Done' }
)
foreach ($c in $cases) {
  $j = TypeAt $c.L $c.C
  $got = if ($j) { "$($j.resolved)" } else { '<no json>' }
  Check $c.N ($got -eq $c.W) "resolved=$got"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
