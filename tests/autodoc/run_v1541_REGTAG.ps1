<#
  run_v1541_REGTAG.ps1 -- Q21: the `Registered as:` fact of a unit two projects
  compile is tagged per project and reaches a fixpoint.

  THE DEFECT: each project rendered the line from its own DI registrations and
  replaced the other's, so the shared unit changed on every run (A, B, A, B).
  THE RULE (docs\wiki\shared-unit.md): on a unit another project is seen in, the
  line reads `[CliApp]IFoo (singleton), [SrvApp]IFoo (transient)`; a run adds and
  removes only its own tag.

  FIXTURE: shared\uShared.pas (NOT marked dl:shared) compiled by SrvApp and
  CliApp. SrvApp registers TFoo as IFoo transient, TBar as IBar, and TGen as a
  two-argument generic (its comma is inside the entry). CliApp registers TFoo
  as IFoo singleton only. srv\uOnly.pas belongs to SrvApp alone.

  CASES
    PINGPONG  A, B, A, B apply; the second round writes nothing
    TAGS      each project's part is there, tagged; methods included
    DRYRUN / DRIFT  nothing proposed, no doc-drift, on both DBs
    GENERIC   a comma inside <...> does not split an entry
    SINGLE    the private unit is untagged and stable
    PRIVATE   a registration dropped from a private unit goes plainly
    MIGRATE   an untagged stored line is kept by the project that does not render
              it and tagged once by the one that does
    HAND      banner, hand-written summary and prose naming the label untouched
    SHARED    two projects registering the same entry share one [A,B] set
    REMOVE    a registration CliApp drops takes only [CliApp] away
    DROPOWN   the last tag goes with its registration, other lines stay
    RETIRED   a tag of a project that is gone stays until doc-forget reaps it
    NOTAG     a run with two --db neither adds nor removes a tag
    FORGET    doc-forget --list-tags / --project sees the tags of this line
    MARKED    a dl:shared unit with no other evidence migrates once
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0
function Check($n, $ok, $d = '') {
  if ($ok) { $script:Pass++ } else { $script:Fail++ }
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([IO.Path]::GetTempPath()) "dl-regtag-$PID"
$null = New-Item -ItemType Directory -Force $root, "$root\shared", "$root\srv", "$root\cli"
function Put([string]$p, [string]$s) { [IO.File]::WriteAllText($p, ($s -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
function Run { $xs = $args; $o = & { $ErrorActionPreference = 'Continue'; & $Exe @xs 2>&1 | ForEach-Object { "$_" } } | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
function BlockAbove([string]$path, [string]$pat) {
  $ls = [IO.File]::ReadAllLines($path); $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $pat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) { if ($ls[$i] -notmatch '^\s*///') { break }; $acc = ,$ls[$i] + $acc }
  return ($acc -join "`n")
}
# The fact, with a wrapped line folded back into one.
function Reg([string]$path, [string]$pat) {
  $b = (BlockAbove $path $pat) -replace '\n\s*///\s*', ' '
  if ($b -match '<para>Registered as: ([^\r\n]*?)</para>') { ($Matches[1] -replace '\s+', ' ').Trim() } else { '' }
}

$uS   = "$root\shared\uShared.pas"; $uM = "$root\shared\uMarked.pas"; $uO = "$root\srv\uOnly.pas"
$dprA = "$root\srv\SrvApp.dpr"; $dprB = "$root\cli\CliApp.dpr"
$dbA  = "$root\SrvApp.sqlite";  $dbB  = "$root\CliApp.sqlite"
$foo = '^\s*TFoo = class'; $bar = '^\s*TBar = class'; $gen = '^\s*TGen = class'; $bump = '^\s*procedure Bump'
$only = '^\s*TOnly = class'; $mk = '^\s*TMarked = class'

Put $uS @'
unit uShared;

interface

///////////////////////////////////////////////
// Hand banner -- Registered as: not a fact
///////////////////////////////////////////////

type
  IFoo = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F41}']
    procedure Run;
  end;

  IBar = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F42}']
    procedure Ping;
  end;

  IPair<K, V> = interface
    procedure Put;
  end;

  TFoo = class(TInterfacedObject, IFoo)
  private
    FCount: Integer;
  public
    /// <summary>Hand-written. A human may say Registered as: whatever.</summary>
    procedure Run;
    procedure Bump;
  end;

  TBar = class(TInterfacedObject, IBar)
  public
    procedure Ping;
  end;

  TGen = class(TInterfacedObject, IPair<string, Integer>)
  public
    procedure Put;
  end;

implementation

procedure TFoo.Run;
begin
  Bump;
end;

procedure TFoo.Bump;
begin
  FCount := FCount + 1;
end;

procedure TBar.Ping;
begin
end;

procedure TGen.Put;
begin
end;

end.
'@
Put $uM @'
unit uMarked;   // dl:shared SrvApp, CliApp

interface

type
  IMarked = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F43}']
    procedure Go;
  end;

  TMarked = class(TInterfacedObject, IMarked)
  public
    procedure Go;
  end;

procedure RegisterMarked;

implementation

uses Spring.Container;

procedure TMarked.Go;
begin
end;

procedure RegisterMarked;
begin
  GlobalContainer.RegisterType<TMarked>.Implements<IMarked>.AsSingleton;
end;

end.
'@
Put $uO @'
unit uOnly;

interface

type
  IOnly = interface
    ['{2F1B6A1E-6D9C-4C3A-9A55-0B0C1D2E3F44}']
    procedure Go;
  end;

  TOnly = class(TInterfacedObject, IOnly)
  public
    procedure Go;
  end;

implementation

procedure TOnly.Go;
begin
end;

end.
'@
function RegLines($l) { ($l | ForEach-Object { "  GlobalContainer.RegisterType<$($_[0])>.Implements<$($_[1])>.$($_[2]);`n" }) -join '' }
function PutSrv($l) {
  Put "$root\srv\uSrvReg.pas" ("unit uSrvReg;`n`ninterface`n`nprocedure RegisterSrv;`n`nimplementation`n`nuses Spring.Container, uShared, uOnly;`n`n" +
    "procedure RegisterSrv;`nbegin`n" + (RegLines $l) + "end;`n`nend.`n")
}
function PutCli($l) {
  Put "$root\cli\uCliReg.pas" ("unit uCliReg;`n`ninterface`n`nprocedure RegisterCli;`n`nimplementation`n`nuses Spring.Container, uShared;`n`n" +
    "procedure RegisterCli;`nvar`n  B: TBar;`nbegin`n" + (RegLines $l) + "  B := TBar.Create;`n  B.Ping;`nend;`n`nend.`n")
}
$rFoo  = ,@('TFoo', 'IFoo', 'AsTransient')
$rFooS = ,@('TFoo', 'IFoo', 'AsSingleton')
$rGen  = ,@('TGen', 'IPair<string, Integer>', 'AsSingleton')
$rRest = @(,@('TBar', 'IBar', 'AsTransient')) + $rGen
$rOnly = ,@('TOnly', 'IOnly', 'AsSingleton')
Put $dprA "program SrvApp;`nuses uShared in '..\shared\uShared.pas', uMarked in '..\shared\uMarked.pas', uOnly in 'uOnly.pas', uSrvReg in 'uSrvReg.pas';`nbegin`n  RegisterSrv; RegisterMarked;`nend.`n"
Put $dprB "program CliApp;`nuses uShared in '..\shared\uShared.pas', uCliReg in 'uCliReg.pas';`nbegin`n  RegisterCli;`nend.`n"
PutSrv ($rFoo + $rRest + $rOnly)
PutCli $rFooS

function IdxA { $null = Run index --project $dprA --db $dbA }
function IdxB { $null = Run index --project $dprB --db $dbB }
function DocA([string]$u = $uS) { IdxA; $null = Run document --unit $u --db $dbA --apply --no-backup }
function DocB([string]$u = $uS) { IdxB; $null = Run document --unit $u --db $dbB --apply --no-backup }
function Bytes([string]$p) { [IO.File]::ReadAllText($p) }
function Drift([string]$db, [string]$u = $uS) {
  $r = Run lint $u --db $db --project-rules --rule doc-drift
  return ,@($r.Out -split "`r?`n" | Where-Object { $_ -match 'managed facts block is out of date' })
}
# Both projects, reindexed: nothing proposed, no drift on the facts block.
function Settled([string]$n, [string]$u = $uS) {
  IdxA; IdxB
  $t = Bytes $u
  foreach ($k in @(@('SrvApp', $dbA), @('CliApp', $dbB))) {
    $r = Run document --unit $u --db $k[1] --apply --no-backup
    Check "$n DRYRUN $($k[0]) writes nothing" ((Bytes $u) -ceq $t) $r.Out
    if ((Bytes $u) -cne $t) { [IO.File]::WriteAllText($u, $t, [Text.Encoding]::ASCII) }
    $d = Drift $k[1] $u
    Check "$n DRIFT  $($k[0]) no stale facts block" ($d.Count -eq 0) ($d -join ' | ')
  }
}
function Seed([string]$u, [string]$decl, [string]$indent, [string[]]$facts) {
  $x = (@('<remarks>', '<!-- drag-lint:auto BEGIN -->') + @($facts | ForEach-Object { "<para>$_</para>" }) + @('<!-- drag-lint:auto END -->', '</remarks>') | ForEach-Object { "$indent/// $_" }) -join "`r`n"
  Put $u ((Bytes $u).Replace($decl, "$x`r`n$decl"))
}

$both = '[CliApp]IFoo (singleton), [SrvApp]IFoo (transient)'
try {
  $s0 = Bytes $uS

  Write-Host '--- PINGPONG' -ForegroundColor Cyan
  DocA; DocB; DocA; DocB
  $r2 = Bytes $uS
  DocA; $a3 = Bytes $uS; DocB; $b3 = Bytes $uS
  Check 'PINGPONG a further SrvApp run writes nothing' ($a3 -ceq $r2) (Reg $uS $foo)
  Check 'PINGPONG a further CliApp run writes nothing' ($b3 -ceq $a3) (Reg $uS $foo)
  Check 'TAGS TFoo carries both registrations' ((Reg $uS $foo) -eq $both) (Reg $uS $foo)
  Check 'TAGS TFoo.Bump (a method) carries both' ((Reg $uS $bump) -eq $both) (Reg $uS $bump)
  Check 'TAGS TBar keeps the part CliApp does not register' ((Reg $uS $bar) -eq '[SrvApp]IBar (transient)') (Reg $uS $bar)
  Check 'GENERIC the comma inside <> stays in one entry' ((Reg $uS $gen) -match '^\[SrvApp\]IPair&lt;string, ?Integer&gt; \(singleton\)$') (Reg $uS $gen)
  Settled 'PINGPONG'
  $banner = ($s0 -split "`r`n")[4..6] -join "`r`n"
  Check 'HAND banner untouched' ((Bytes $uS).Contains($banner)) ''
  Check 'HAND summary untouched' ((Bytes $uS).Contains('/// <summary>Hand-written. A human may say Registered as: whatever.</summary>')) ''

  Write-Host '--- SINGLE / PRIVATE' -ForegroundColor Cyan
  DocA $uO; $o1 = Bytes $uO
  Check 'SINGLE the private unit is untagged' ((Reg $uO $only) -eq 'IOnly (singleton)') (Reg $uO $only)
  DocA $uO
  Check 'SINGLE a second run is byte-identical' ((Bytes $uO) -ceq $o1) ''
  Check 'SINGLE no tag anywhere in the private unit' (-not ((Bytes $uO) -match '\[SrvApp\]')) ''
  PutSrv ($rFoo + $rRest); DocA $uO
  Check 'PRIVATE a removed registration goes plainly' ((Reg $uO $only) -eq '') (Reg $uO $only)
  PutSrv ($rFoo + $rRest + $rOnly); DocA $uO
  Check 'PRIVATE ... and comes back untagged' ((Reg $uO $only) -eq 'IOnly (singleton)') (Reg $uO $only)

  Write-Host '--- SHARED / REMOVE / DROPOWN' -ForegroundColor Cyan
  PutCli $rFoo; DocB; DocA; DocB
  Check 'SHARED one entry, two tags' ((Reg $uS $foo) -eq '[CliApp,SrvApp]IFoo (transient)') (Reg $uS $foo)
  Settled 'SHARED'
  PutCli $rGen; DocB
  Check 'REMOVE only [CliApp] goes from TFoo' ((Reg $uS $foo) -eq '[SrvApp]IFoo (transient)') (Reg $uS $foo)
  Check 'REMOVE [CliApp] goes from TFoo.Bump too' ((Reg $uS $bump) -eq '[SrvApp]IFoo (transient)') (Reg $uS $bump)
  DocA; Settled 'REMOVE'
  PutSrv ($rRest + $rOnly); DocA
  Check 'DROPOWN the last tag takes the line away' ((Reg $uS $foo) -eq '') (Reg $uS $foo)
  Check 'DROPOWN the other lines stay' ((Reg $uS $bar) -eq '[SrvApp]IBar (transient)') (Reg $uS $bar)
  DocB; Settled 'DROPOWN'
  PutSrv ($rFoo + $rRest + $rOnly); PutCli $rFooS

  Write-Host '--- MIGRATE (old untagged lines; the project that registers less runs first)' -ForegroundColor Cyan
  Put $uS $s0
  Seed $uS '  TFoo = class(' '  ' @('Used by: uSrvReg.RegisterSrv (uSrvReg.pas)', 'Used in units: uSrvReg', 'Registered as: IFoo (transient), IFoo (transient)')
  Seed $uS '    procedure Bump;' '    ' @('Called from: uShared.TFoo.Run (uShared.pas)', 'Registered as: IFoo (transient), IFoo (transient)')
  Seed $uS '  TBar = class(' '  ' @('Used by: uSrvReg.RegisterSrv (uSrvReg.pas)', 'Used in units: uSrvReg', 'Registered as: IBar (transient)')
  DocB
  Check 'MIGRATE CliApp keeps the untagged line it does not render' ((Reg $uS $bar) -eq 'IBar (transient)') (Reg $uS $bar)
  Check 'MIGRATE CliApp writes its own part tagged' ((Reg $uS $foo) -match '\[CliApp\]IFoo \(singleton\)') (Reg $uS $foo)
  DocA
  Check 'MIGRATE SrvApp adopts TBar' ((Reg $uS $bar) -eq '[SrvApp]IBar (transient)') (Reg $uS $bar)
  Check 'MIGRATE TFoo ends with both parts, the duplicate gone' ((Reg $uS $foo) -eq $both) (Reg $uS $foo)
  Check 'MIGRATE TFoo.Bump likewise' ((Reg $uS $bump) -eq $both) (Reg $uS $bump)
  DocB; Settled 'MIGRATE'

  Write-Host '--- NOTAG / FORGET' -ForegroundColor Cyan
  $t = Bytes $uS
  $null = Run document --unit $uS --db $dbA --db $dbB --apply --no-backup
  Check 'NOTAG two --db leave the tagged line alone' ((Reg $uS $foo) -eq $both) (Reg $uS $foo)
  Put $uS ($t.Replace('Registered as: [SrvApp]IBar (transient)', 'Registered as: [OldApp,SrvApp]IBar (transient), [OldApp]IOld'))
  $t2 = Bytes $uS; DocA; DocB
  Check 'RETIRED a tag no project here can judge is kept by both' (((Bytes $uS) -ceq $t2) -and ($t2 -cne $t)) (Reg $uS $bar)
  Put $uS $t
  $uF = "$root\shared\uForget.pas"
  Put $uF "unit uForget;`n`ninterface`n`ntype`n  /// <remarks>`n  /// <!-- drag-lint:auto BEGIN -->`n  /// <para>Registered as: [CliApp,SrvApp]IPair&lt;string, Integer&gt; (singleton), [CliApp]IBar (transient)</para>`n  /// <!-- drag-lint:auto END -->`n  /// </remarks>`n  TX = class`n  end;`n`nimplementation`n`nend.`n"
  $r = Run doc-forget --scope $uF --list-tags
  Check 'FORGET --list-tags counts the tags of this line' (($r.Out -match '(?m)CliApp\D+2\b|\b2\D+CliApp') -and ($r.Out -match '(?m)SrvApp\D+1\b|\b1\D+SrvApp')) $r.Out
  $null = Run doc-forget --scope $uF --project CliApp --apply --no-backup
  Check 'FORGET --project removes only that tag' ((Reg $uF '^\s*TX = class') -eq '[SrvApp]IPair&lt;string, Integer&gt; (singleton)') (Reg $uF '^\s*TX = class')

  Write-Host '--- MARKED (dl:shared, registered by the unit itself)' -ForegroundColor Cyan
  Seed $uM '  TMarked = class(' '  ' @('Registered as: IMarked (singleton)')
  DocA $uM; $m1 = Bytes $uM
  Check 'MARKED the old untagged line migrates' ((Reg $uM $mk) -eq '[SrvApp]IMarked (singleton)') (Reg $uM $mk)
  DocA $uM
  Check 'MARKED ... once' ((Bytes $uM) -ceq $m1) ''
} finally {
  if (Test-Path -LiteralPath $root) { try { [IO.Directory]::Delete($root, $true) } catch { } }
}
Write-Host ("pass={0} fail={1}" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
