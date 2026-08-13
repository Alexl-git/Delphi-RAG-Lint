<#
  run_shared_unit_marker.ps1 -- Task 3: The `dl:shared` marker -- grammar, reader, CLI surface

  A unit declares that several projects compile it:

    unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup

  Fixtures (four scenarios):
    1. Unmarked unit (no marker) -- should be reported as not shared
    2. Marked unit with one project -- marker present, one project listed
    3. Marked unit with project already listed (adding same project is idempotent)
    4. Unit with line-1 block comment -- marker must be found below it, not on line 1
       (line 1 is often the { of a header comment -- the anchoring trap that
       already breaks unit-too-large)

  Test assertions (per plan):
    - unmarked unit is not shared
    - marked unit is shared
    - projects parse in written order
    - adding a listed project is a no-op (idempotent)
    - marker is found below a line-1 block comment

  Expected CLI surface:
    drag-lint shared-unit --in <file.pas> [--add-project <name>] [--apply] [--json]

  Dry-run by default (no --apply). Output format (--json):
    { "is_shared": true/false, "projects": ["YADF", ...], "marker_text": "..." }
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-shared-unit-marker"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false

function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

function GetSharedUnitInfo([string]$FilePath) {
  <# Calls: drag-lint shared-unit --in <file> --json
     Returns: parsed JSON object or $null on error
     Expected response: { "is_shared": bool, "projects": [string...], "marker_text": string } #>
  try {
    $json = & $Exe shared-unit --in $FilePath --json 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
      Write-Host "    [shared-unit CLI failed with EC $LASTEXITCODE]" -ForegroundColor Yellow
      return $null
    }
    $obj = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
    return $obj
  } catch {
    return $null
  }
}

function IsSharedPerCli([string]$FilePath) {
  $info = GetSharedUnitInfo $FilePath
  if ($null -eq $info) { return $false }
  return $info.is_shared -eq $true
}

function GetProjectsPerCli([string]$FilePath) {
  $info = GetSharedUnitInfo $FilePath
  if ($null -eq $info -or $info.is_shared -ne $true) { return @() }
  return @($info.projects)
}

function AddProjectPerCli([string]$FilePath, [string]$Project, [bool]$Apply = $false) {
  <# Calls: drag-lint shared-unit --in <file> --add-project <name> [--apply] --json
     Returns: parsed JSON object with new marker_text, or $null on error
     If Apply=$false, this is a dry-run (default, same as the plan says) #>
  try {
    $args = @('shared-unit', '--in', $FilePath, '--add-project', $Project, '--json')
    if ($Apply) { $args += '--apply' }
    $json = & $Exe @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
      Write-Host "    [shared-unit --add-project CLI failed with EC $LASTEXITCODE]" -ForegroundColor Yellow
      return $null
    }
    $obj = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
    return $obj
  } catch {
    return $null
  }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Fixture 1: Plain unit (no marker)
$PlainUnit = @'
unit UnitPlain;

interface

type
  TOptions = class
  public
    procedure LoadDefaults;
  end;

implementation

procedure TOptions.LoadDefaults;
begin
end;

end.
'@

# Fixture 2: Marked unit with one project
$MarkedUnit = @'
unit UnitMarked;   // dl:shared YADF

interface

type
  TOptions = class
  public
    procedure LoadDefaults;
  end;

implementation

procedure TOptions.LoadDefaults;
begin
end;

end.
'@

# Fixture 3: Marked unit with two projects (for project-parsing test)
$MarkedMultiProject = @'
unit UnitMulti;   // dl:shared YADF, YADFOT

interface

type
  TOptions = class
  public
    procedure LoadDefaults;
  end;

implementation

procedure TOptions.LoadDefaults;
begin
end;

end.
'@

# Fixture 4: Unit with line-1 block comment, marker below it
$BlockCommentFirst = @'
{
  This is a header comment block that spans multiple lines.
  It explains the unit's purpose.
}
unit UnitBlockComment;   // dl:shared DataCopy

interface

type
  TOptions = class
  public
    procedure LoadDefaults;
  end;

implementation

procedure TOptions.LoadDefaults;
begin
end;

end.
'@

# Fixture 5: Marked unit for idempotence test (starts with YADF, YADFOT)
$MarkedForIdempotence = @'
unit UnitIdempotent;   // dl:shared YADF, YADFOT

interface

type
  TOptions = class
  public
    procedure LoadDefaults;
  end;

implementation

procedure TOptions.LoadDefaults;
begin
end;

end.
'@

function Write-Fixture([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir = Join-Path $WorkDir 'fixtures'
New-Item -ItemType Directory $dir | Out-Null

$plainPath = Join-Path $dir 'UnitPlain.pas'
$markedPath = Join-Path $dir 'UnitMarked.pas'
$multiPath = Join-Path $dir 'UnitMulti.pas'
$blockCommentPath = Join-Path $dir 'UnitBlockComment.pas'
$idempotentPath = Join-Path $dir 'UnitIdempotent.pas'

Write-Fixture $plainPath $PlainUnit
Write-Fixture $markedPath $MarkedUnit
Write-Fixture $multiPath $MarkedMultiProject
Write-Fixture $blockCommentPath $BlockCommentFirst
Write-Fixture $idempotentPath $MarkedForIdempotence

Write-Host 'Testing dl:shared marker' -ForegroundColor Cyan

Write-Host ''
Write-Host 'Test 1: Basic marker detection' -ForegroundColor Yellow
Check 'unmarked unit is not shared' (-not (IsSharedPerCli $plainPath))
Check 'marked unit is shared' (IsSharedPerCli $markedPath)

Write-Host ''
Write-Host 'Test 2: Project parsing' -ForegroundColor Yellow
$projects = GetProjectsPerCli $markedPath
Check 'single-project marker parses' (($projects | Measure-Object).Count -eq 1)
if ($null -ne $projects -and $projects.Count -gt 0) {
  Check 'project name is YADF' ($projects[0] -eq 'YADF') "got: $($projects -join ',')"
} else {
  Check 'project name is YADF' $false "CLI not responding"
}

Write-Host ''
Write-Host 'Test 3: Projects in written order' -ForegroundColor Yellow
$multiProjects = GetProjectsPerCli $multiPath
Check 'multi-project marker parses in order' (($multiProjects -join ',') -eq 'YADF,YADFOT') `
  "got: $($multiProjects -join ',')"

Write-Host ''
Write-Host 'Test 4: Marker below line-1 block comment' -ForegroundColor Yellow
Check 'marker is found below a line-1 block comment' (IsSharedPerCli $blockCommentPath) `
  'line 1 here is often the { of a header comment -- the anchoring trap that already breaks unit-too-large'
$blockProjects = GetProjectsPerCli $blockCommentPath
if ($null -ne $blockProjects -and $blockProjects.Count -gt 0) {
  Check 'projects parse correctly below block comment' ($blockProjects[0] -eq 'DataCopy') `
    "got: $($blockProjects -join ',')"
} else {
  Check 'projects parse correctly below block comment' $false "CLI not responding"
}

Write-Host ''
Write-Host 'Test 5: Idempotent add-project' -ForegroundColor Yellow
$resultAdd = AddProjectPerCli $idempotentPath 'YADFOT' $false
if ($null -ne $resultAdd) {
  Check 'adding an already-listed project returns already_listed' ($resultAdd.already_listed -eq $true) `
    'idempotent: the menu item will be pressed twice'
} else {
  Check 'adding an already-listed project returns already_listed' $false `
    'CLI not responding'
}

# Verify the file was NOT modified (dry-run)
$contentBefore = Get-Content $idempotentPath -Raw
AddProjectPerCli $idempotentPath 'YADFOT' $false | Out-Null
$contentAfterDryRun = Get-Content $idempotentPath -Raw
Check 'dry-run does not modify the file' ($contentAfterDryRun -eq $contentBefore) `
  '--apply flag is required to modify'

# Now test adding a new project with --apply
$resultAddNew = AddProjectPerCli $idempotentPath 'YADFSetup' $true
if ($null -ne $resultAddNew) {
  Check 'adding a new project returns added=true' ($resultAddNew.added -eq $true) `
    'new project should be added with --apply'
} else {
  Check 'adding a new project returns added=true' $false `
    'CLI not responding'
}

# Verify the file WAS modified and the project list is correct
$newProjects = GetProjectsPerCli $idempotentPath
Check 'new project is appended to the list' (($newProjects -join ',') -eq 'YADF,YADFOT,YADFSetup') `
  "got: $($newProjects -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
