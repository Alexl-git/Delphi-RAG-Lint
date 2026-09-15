<#
  run_doc_exception_raise_shapes.ps1 -- the three raise shapes the doc miner
  still named wrongly after session 93.

  SIBLING OF run_doc_exception_reraise_var.ps1, which pins the three shapes
  session 93 DID fix (`raise E` through a handler binding, a unit-qualified
  constructor, and a bare local with no binding). This one pins the remainder
  filed in INBOX-doc-raise-shapes-still-unresolved.md.

  RENDER-TIME, CONFIRMED BEFORE EDITING. TDocFactsBuilder.MineRaises /
  MineRaisesDetailed scan the routine's SOURCE LINES when `document` or
  `doc-drift` runs; ResolveRaiseClass and RecordHandlerBinding are plain text
  scanners over one line at a time. Nothing here is extracted at index time, so
  none of it bills DRAGLINT_EXTRACTOR_VERSION (~5h15m re-parse of every
  database).

  THE THREE SHAPES
  --------------------------------------------------------------------------------
  1. `raise Self.FErr;` / `raise Holder.Err;` -- a dotted chain whose LAST
     segment is a FIELD, not a constructor. The resolver took the segment
     BEFORE the last, so it emitted cref="Self" / cref="Holder": a link to a
     class that does not exist. The discriminator is one peek -- a constructor
     call is followed by `(`; a field reference is not. With no `(`, the chain
     is a VARIABLE and its class is not stated anywhere the scanner can see, so
     NOTHING is emitted.

  2. `raise MakeError(42);` -- a function CALL returning an exception, emitted
     as cref="MakeError". It is SYNTACTICALLY IDENTICAL to the cast
     `raise Exception(AcquireExceptionObject)`, which is why the `(`-follows arm
     kept the identifier. Text alone cannot separate them; the INDEX can, and a
     store is already in MineRaises' hand. So: a name the index knows to be a
     ROUTINE and not a type emits nothing; a name it knows as a TYPE is kept;
     and a name it knows NOTHING about keeps the cast reading, which is why
     case 6 below (an RTL type absent from this fixture's index) is a separate
     assertion from case 7 (a type the fixture DOES declare).

  3. `on E:` / `Exception do` split across two lines. The binding was read on
     one line, so a wrapped handler bound nothing and the re-raise then emitted
     no tag. Same pending-state pattern CollectRaiseDetail already uses for a
     wrapped constructor, budget included.

  >>> POSITIVE CONTROLS, AND WHY THEY ARE NOT DECORATION. Every assertion in
  shapes 1 and 2 is an assertion of ABSENCE. An engine that stopped mining
  raises altogether -- or a resolver that returned '' for everything -- passes
  all of them. Cases 5, 6, 7 and 9 are the counterweight: a named cref must
  still be emitted, with its mined message, for the shapes that ARE resolvable.
  If those ever fail together, the fix did not narrow the resolver, it disabled
  it.

  RED-CHECK: against the build at HEAD 63fe8514, cases 1, 2, 3, 4 and 8 FAIL
  (cref="Self", cref="Holder", cref="MakeError", and the wrapped handler
  emitting nothing) and every positive control passes. Verified before the fix
  was written.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ('draglint_doc_raiseshapes_' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $scratch -Force | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }
function Get-DocBlock([string]$Text, [string]$Name) {
  $lines = $Text -split "`r?`n"
  $ix = -1
  for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match "^\s*(procedure|function)\s+$Name\b") { $ix = $i; break } }
  if ($ix -lt 0) { return '' }
  $acc = @()
  for ($j = $ix - 1; $j -ge 0; $j--) { if ($lines[$j] -match '^\s*///') { $acc = ,$lines[$j] + $acc } else { break } }
  return ($acc -join "`n")
}

$src = Join-Path $scratch 'raiseshapes.pas'
$db  = Join-Path $scratch 'r.sqlite'

Write-Ascii $src @'
unit raiseshapes;

interface

uses
  System.SysUtils;

type
  EMine = class(Exception)
  end;

  THolder = class
  private
    FErr: Exception;
  public
    procedure BoomSelf;
  end;

procedure BoomField;
procedure BoomFactory;
procedure BoomCastUnknown;
procedure BoomCastKnown;
procedure BoomWrappedHandler;
procedure PlainCtor;

implementation

var
  GHolder: THolder;

function MakeError(ACode: Integer): Exception;
begin
  Result := Exception.Create('made ' + IntToStr(ACode));
end;

procedure THolder.BoomSelf;
begin
  raise Self.FErr;
end;

procedure BoomField;
begin
  raise GHolder.FErr;
end;

procedure BoomFactory;
begin
  raise MakeError(42);
end;

procedure BoomCastUnknown;
begin
  raise Exception(AcquireExceptionObject);
end;

procedure BoomCastKnown;
begin
  raise EMine(AcquireExceptionObject);
end;

procedure BoomWrappedHandler;
begin
  try
    Beep;
  except
    on E:
      Exception do
      raise E;
  end;
end;

procedure PlainCtor;
begin
  raise EPlainThing.Create('plain message');
end;

end.
'@

$md5Orig = Get-FileMd5 $src

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)
  $md5First = Get-FileMd5 $src
  $text = [IO.File]::ReadAllText($src)
  Write-Host '--- applied file ---' -ForegroundColor DarkGray
  Write-Host $text -ForegroundColor DarkGray

  # === SHAPE 1 -- a dotted chain ending in a FIELD names nothing ==============
  Check '1. `raise Self.FErr` does not emit cref="Self"' `
    (-not ($text -match '<exception cref="Self">')) '(file-wide) cref="Self" is present'
  $b = Get-DocBlock $text 'BoomSelf'
  Check '2. BoomSelf: `raise Self.FErr` emits NO <exception> at all' `
    (-not ($b -match '<exception')) $b
  $b = Get-DocBlock $text 'BoomField'
  Check '3. BoomField: `raise GHolder.FErr` emits NO <exception> (not cref="GHolder")' `
    (-not ($b -match '<exception')) $b

  # === SHAPE 2 -- a factory CALL is not a class ==============================
  $b = Get-DocBlock $text 'BoomFactory'
  Check '4. BoomFactory: `raise MakeError(42)` emits NO <exception> (not cref="MakeError")' `
    (-not ($b -match '<exception')) $b
  Check '   ...and cref="MakeError" appears nowhere in the file' `
    (-not ($text -match '<exception cref="MakeError">')) '(file-wide) cref="MakeError" is present'

  # >>> POSITIVE CONTROLS for shape 2. The cast shape is syntactically identical
  #     to the factory call; if these fail with case 4, the resolver was
  #     disabled rather than narrowed.
  $b = Get-DocBlock $text 'BoomCastUnknown'
  Check '5. CONTROL: `raise Exception(AcquireExceptionObject)` (name unknown to this index) KEEPS cref="Exception"' `
    ($b -match '<exception cref="Exception">') $b
  $b = Get-DocBlock $text 'BoomCastKnown'
  Check '6. CONTROL: `raise EMine(AcquireExceptionObject)` (a TYPE this index knows) KEEPS cref="EMine"' `
    ($b -match '<exception cref="EMine">') $b

  # === SHAPE 3 -- a WRAPPED `on E:` / `Exception do` still binds ==============
  $b = Get-DocBlock $text 'BoomWrappedHandler'
  Check '7. BoomWrappedHandler: `on E:` wrapped onto the next line -> cref="Exception"' `
    ($b -match '<exception cref="Exception">') $b
  Check '   ...and never cref="E"' `
    (-not ($b -match '<exception cref="E">')) $b

  # === POSITIVE CONTROL -- the shape session 93 fixed must stay fixed =========
  $b = Get-DocBlock $text 'PlainCtor'
  Check '8. CONTROL: PlainCtor keeps cref="EPlainThing" WITH its mined message' `
    ($b -match '<exception cref="EPlainThing"><!-- drag-lint:auto exc -->plain message</exception>') $b

  # === idempotency + encoding + strip inverse ================================
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  & $exePath document --unit $src --db $db --apply 2>$null | Out-Null
  Check '9. IDEMPOTENT: reindex + a second --apply is byte-identical' `
    ((Get-FileMd5 $src) -eq $md5First) ("first=$md5First second=" + (Get-FileMd5 $src))

  Check '10. every emitted /// line is 7-bit ASCII' `
    (@([IO.File]::ReadAllLines($src) | Where-Object { $_ -match '^\s*///' -and ($_.ToCharArray() | Where-Object { [int]$_ -gt 126 }) }).Count -eq 0)

  & $exePath document --unit $src --db $db --strip --apply 2>$null | Out-Null
  Check '11. INVERSE: strip(apply(original)) is byte-identical to the original' `
    ((Get-FileMd5 $src) -eq $md5Orig) ("orig=$md5Orig strip=" + (Get-FileMd5 $src))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
