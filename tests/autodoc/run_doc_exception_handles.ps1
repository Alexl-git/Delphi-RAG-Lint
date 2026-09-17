<#
  run_doc_exception_handles.ps1 --
  docs\INBOX-report-exceptions-raised-and-handled.md, gap 3 (the exceptions a
  routine HANDLES). PLAN-SESSION-95-OPEN-NOTES.md section 3.

  WHAT IT PINS. A routine with a try..except gets ONE 'Catches:' line in its
  managed facts block, one entry per (exception class, disposition):

      Catches: EConvertError (dialog: ShowMessage); EFOpenError (swallowed);
               Exception (re-raise)

  Five dispositions, decided from the handler BODY:
      re-raise         a bare `raise;` or `raise <the handler variable>`
      raises <Class>   the handler raises a DIFFERENT class (a translation);
                       the plan listed four dispositions and this shape fits
                       none of them -- reporting `raise EBar.Create(..)` as
                       "swallowed" would be a lie in the direction that hides
                       a contract, so it is the fifth
      dialog: <name>   a call to a routine on docs.dialog_routines, naming the
                       routine that matched so the fact carries a WITNESS
      empty            no statement at all (overlaps the empty-except rule on
                       purpose: the rule says it is wrong, the fact tells the
                       CALLER what the contract is)
      swallowed        anything else

  THE LABEL IS 'Catches:', NOT A SECOND 'Handles:'. The plan wrote 'Handles:'
  beside the DFM event-wiring line of the same name; Doc.SharedFacts bounds a
  fact's slice in the flattened stored block BY LABEL (ALL_LABELS), so two
  lines under one label would collide there. Distinct label, registered.

  THE KNOB IS docs.dialog_routines / docs.max_handles IN THE MANIFEST, not the
  lint config's "exceptions" object the plan pointed at: every other doc-fact
  knob (max_callers, complexity_min) lives in the manifest's docs block, and
  that is the one place `document`, doc-drift, hover and the LSP all already
  read from. A knob the checker cannot see is how writer and checker drift.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}
function WriteAscii([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_doc_exception_handles'
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'exchandles.pas'
$formPas = Join-Path $scratch 'uCatchForm.pas'
$formDfm = Join-Path $scratch 'uCatchForm.dfm'
$db     = Join-Path $scratch 'exchandles.sqlite'

WriteAscii $target @'
unit exchandles;

interface

uses
  System.SysUtils;

type
  EGhost = class(Exception);
  EDup   = class(Exception);
  EAlpha = class(Exception);
  EZulu  = class(Exception);
  EOne   = class(Exception);
  ETwo   = class(Exception);
  EThree = class(Exception);
  EFour  = class(Exception);
  EFive  = class(Exception);
  ESix   = class(Exception);
  ESeven = class(Exception);
  EEight = class(Exception);
  ENine  = class(Exception);
  ETen   = class(Exception);

procedure Log(const AMsg: string);
procedure ShowMessage(const AMsg: string);
procedure DialogHandler;
procedure SwallowHandler;
procedure ReraiseHandler;
procedure ReraiseVarHandler;
procedure EmptyHandler;
procedure EmptyOnHandler;
procedure ElseHandler;
procedure TranslateHandler;
procedure NoHandler;
procedure CommentedHandler;
procedure WrappedHandler;
procedure OrderHandler;
procedure DupHandler;
procedure CapHandler;
procedure DottedDialogHandler;
procedure IfElseHandler;
procedure FinallyOnly;

implementation

procedure Log(const AMsg: string);
begin
  WriteLn(AMsg);
end;

procedure ShowMessage(const AMsg: string);
begin
  WriteLn('dialog: ' + AMsg);
end;

procedure DialogHandler;
begin
  try
    Log('work');
  except
    on E: EConvertError do ShowMessage(E.Message);
  end;
end;

procedure SwallowHandler;
begin
  try
    Log('work');
  except
    on E: EFOpenError do
    begin
      Log(E.Message);
    end;
  end;
end;

procedure ReraiseHandler;
begin
  try
    Log('work');
  except
    on E: Exception do
    begin
      Log(E.Message);
      raise;
    end;
  end;
end;

procedure ReraiseVarHandler;
begin
  try
    Log('work');
  except
    on E: EInOutError do raise E;
  end;
end;

procedure EmptyHandler;
begin
  try
    Log('work');
  except
  end;
end;

procedure EmptyOnHandler;
begin
  try
    Log('work');
  except
    on E: EAbort do ;
  end;
end;

procedure ElseHandler;
begin
  try
    Log('work');
  except
    on E: EAbort do Log(E.Message);
    else ShowMessage('unexpected');
  end;
end;

procedure TranslateHandler;
begin
  try
    Log('work');
  except
    on E: EAlpha do raise EZulu.Create(E.Message);
  end;
end;

procedure NoHandler;
begin
  Log('no try at all');
end;

procedure CommentedHandler;
begin
  { try Log('x'); except on E: EGhost do ShowMessage(E.Message); end; }
  // try Log('x'); except on E: EGhost do ShowMessage(E.Message); end;
  (* try Log('x'); except on E: EGhost do ShowMessage(E.Message); end; *)
  Log('try except on E: EGhost do ShowMessage(E.Message); end;');
end;

procedure WrappedHandler;
begin
  try
    Log('work');
  except
    on E:
      EConvertError do
      Log(E.Message);
  end;
end;

procedure OrderHandler;
begin
  try
    Log('work');
  except
    on E: EZulu do Log('z');
    on E: EAlpha do Log('a');
  end;
end;

procedure DupHandler;
begin
  try
    Log('first');
  except
    on E: EDup do Log('one');
  end;
  try
    Log('second');
  except
    on E: EDup do Log('two');
  end;
end;

procedure CapHandler;
begin
  try
    Log('work');
  except
    on E: EOne do Log('1');
    on E: ETwo do Log('2');
    on E: EThree do Log('3');
    on E: EFour do Log('4');
    on E: EFive do Log('5');
    on E: ESix do Log('6');
    on E: ESeven do Log('7');
    on E: EEight do Log('8');
    on E: ENine do Log('9');
    on E: ETen do Log('10');
  end;
end;

procedure DottedDialogHandler;
begin
  try
    Log('work');
  except
    on E: Exception do Application.MessageBox('failed', 'title');
  end;
end;

procedure IfElseHandler;
begin
  try
    Log('work');
  except
    on E: EAlpha do
      if Length(E.Message) > 0 then Log('long') else Log('short');
  end;
end;

procedure FinallyOnly;
begin
  try
    Log('work');
  finally
    Log('done');
  end;
end;

end.
'@

WriteAscii $formPas @'
unit uCatchForm;

interface

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, System.Classes, System.SysUtils;

type
  TCatchForm = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TCatchForm.Button1Click(Sender: TObject);
begin
  try
    Caption := 'clicked';
  except
    on E: Exception do ShowMessage(E.Message);
  end;
end;

end.
'@

WriteAscii $formDfm @'
object CatchForm: TCatchForm
  Caption = 'CatchForm'
  object Button1: TButton
    Caption = 'Go'
    OnClick = Button1Click
  end
end
'@

function DocFor([string]$QName) {
  return (& $exePath document --qname $QName --db $db 2>$null | Out-String)
}
# The emitter wraps long lines across `/// ` continuations; flatten before
# asserting on content (same idiom as run_doc_exception_message.ps1).
function Flat([string]$Doc) {
  return (($Doc -replace "`r?`n\s*///\s?", ' ') -replace '\s+', ' ')
}
function CatchesOf([string]$Doc) {
  $m = [regex]::Match((Flat $Doc), 'Catches: ([^<]*?)\s*(?=<|$)')
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value.Trim()
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null
  Check 'fixture indexed' (Test-Path $db)

  Write-Host ''
  Write-Host 'THE ASK: one Catches: line, one entry per handler, disposition from the body' -ForegroundColor Cyan
  $dlg = DocFor 'exchandles.DialogHandler'
  Check 'dialog: `on E: EConvertError do ShowMessage(..)` -> EConvertError (dialog: ShowMessage)' `
    ((CatchesOf $dlg) -eq 'EConvertError (dialog: ShowMessage)') `
    "got: '$(CatchesOf $dlg)'`n$dlg"

  $swl = DocFor 'exchandles.SwallowHandler'
  Check 'swallowed: a handler that only logs -> EFOpenError (swallowed)' `
    ((CatchesOf $swl) -eq 'EFOpenError (swallowed)') "got: '$(CatchesOf $swl)'"

  $rer = DocFor 'exchandles.ReraiseHandler'
  Check 're-raise: a bare `raise;` in the handler -> Exception (re-raise)' `
    ((CatchesOf $rer) -eq 'Exception (re-raise)') "got: '$(CatchesOf $rer)'"

  $rev = DocFor 'exchandles.ReraiseVarHandler'
  Check 're-raise: `raise E` through the handler variable -> EInOutError (re-raise)' `
    ((CatchesOf $rev) -eq 'EInOutError (re-raise)') "got: '$(CatchesOf $rev)'"

  $emp = DocFor 'exchandles.EmptyHandler'
  Check 'empty: a bare `except end` is an implicit catch-all -> Exception (empty)' `
    ((CatchesOf $emp) -eq 'Exception (empty)') "got: '$(CatchesOf $emp)'"

  $emo = DocFor 'exchandles.EmptyOnHandler'
  Check 'empty: `on E: EAbort do ;` -> EAbort (empty)' `
    ((CatchesOf $emo) -eq 'EAbort (empty)') "got: '$(CatchesOf $emo)'"

  $els = DocFor 'exchandles.ElseHandler'
  Check 'else clause counts as `on Exception`, and keeps its own disposition' `
    ((CatchesOf $els) -eq 'EAbort (swallowed); Exception (dialog: ShowMessage)') "got: '$(CatchesOf $els)'"

  $trn = DocFor 'exchandles.TranslateHandler'
  Check 'raises: a handler raising a DIFFERENT class -> EAlpha (raises EZulu)' `
    ((CatchesOf $trn) -eq 'EAlpha (raises EZulu)') "got: '$(CatchesOf $trn)'"

  $dot = DocFor 'exchandles.DottedDialogHandler'
  Check 'dialog witness keeps the dotted source spelling: Application.MessageBox' `
    ((CatchesOf $dot) -eq 'Exception (dialog: Application.MessageBox)') "got: '$(CatchesOf $dot)'"

  $wrp = DocFor 'exchandles.WrappedHandler'
  Check 'a handler binding WRAPPED across lines (`on E:` / `EConvertError do`) is still seen' `
    ((CatchesOf $wrp) -eq 'EConvertError (swallowed)') "got: '$(CatchesOf $wrp)'"

  $ife = DocFor 'exchandles.IfElseHandler'
  Check 'an `else` that belongs to an `if` inside the handler is NOT an except-else' `
    ((CatchesOf $ife) -eq 'EAlpha (swallowed)') "got: '$(CatchesOf $ife)'"

  Write-Host ''
  Write-Host 'POSITIVE CONTROLS: absence where nothing is handled' -ForegroundColor Cyan
  $non = DocFor 'exchandles.NoHandler'
  Check 'a routine with no try..except gets NO Catches: line (fabrication control)' `
    ($null -eq (CatchesOf $non)) "a blanket decorator would pass every arm above; got:`n$non"

  $fin = DocFor 'exchandles.FinallyOnly'
  Check 'a try..finally contributes nothing' `
    ($null -eq (CatchesOf $fin)) "got: '$(CatchesOf $fin)'"

  $cmt = DocFor 'exchandles.CommentedHandler'
  Check 'a handler inside { }, //, (* *) or a string literal is NOT reported' `
    (($null -eq (CatchesOf $cmt)) -and (-not ((Flat $cmt) -match 'EGhost'))) `
    "five recorded text-scan-misreads-comments defects say this is the likeliest regression; got:`n$cmt"

  Write-Host ''
  Write-Host 'DETERMINISM AND CAPS' -ForegroundColor Cyan
  $ord = DocFor 'exchandles.OrderHandler'
  Check 'entries are ordered by class name, case-insensitive, NOT source order' `
    ((CatchesOf $ord) -eq 'EAlpha (swallowed); EZulu (swallowed)') "got: '$(CatchesOf $ord)'"

  $dup = DocFor 'exchandles.DupHandler'
  Check 'two handlers of one class with one disposition are ONE entry' `
    ((CatchesOf $dup) -eq 'EDup (swallowed)') "got: '$(CatchesOf $dup)'"

  $cap = DocFor 'exchandles.CapHandler'
  $capVal = CatchesOf $cap
  Check 'ten handlers are capped at the default 8 with a VISIBLE (+2 more)' `
    (($null -ne $capVal) -and ($capVal -match '\(\+2 more\)$') -and (@([regex]::Matches($capVal, '\(swallowed\)')).Count -eq 8)) `
    "got: '$capVal'"
  Check 'the cap keeps the FIRST eight by name (EThree and ETwo are the ones dropped)' `
    (($null -ne $capVal) -and ($capVal -notmatch 'EThree') -and ($capVal -notmatch 'ETwo') -and ($capVal -match '^EEight')) `
    "got: '$capVal'"

  Write-Host ''
  Write-Host 'THE DFM LINE SURVIVES: both producers emit, under DIFFERENT labels' -ForegroundColor Cyan
  $frm = DocFor 'uCatchForm.TCatchForm.Button1Click'
  Check 'the DFM event-wiring line is still there: Handles: Button1.OnClick' `
    ((Flat $frm) -match 'Handles: Button1\.OnClick') "the new producer stomped the old; got:`n$frm"
  Check 'and the handler fact is beside it: Catches: Exception (dialog: ShowMessage)' `
    ((CatchesOf $frm) -eq 'Exception (dialog: ShowMessage)') "got: '$(CatchesOf $frm)'"

  Write-Host ''
  Write-Host 'CONVERGENCE: document --apply twice; the second pass changes nothing' -ForegroundColor Cyan
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $h1 = (Get-FileHash $target -Algorithm SHA256).Hash
  $applied = [IO.File]::ReadAllText($target)
  Check 'apply #1 wrote a Catches: line into the unit' ($applied -match 'Catches: EConvertError \(dialog: ShowMessage\)') `
    'the fact must reach the file, not only --qname output'
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $h2 = (Get-FileHash $target -Algorithm SHA256).Hash
  Check 'apply #2 after a reindex is byte-identical (a non-convergent fact is definitely wrong)' ($h1 -eq $h2)
}
finally { Pop-Location }

Write-Host ''
Write-Host 'CONFIG CONTROLS: the knob is really consulted (a DOTTED .drag-lint.json in the cwd)' -ForegroundColor Cyan
$cfgDir = Join-Path $scratch 'cfg'
New-Item -ItemType Directory -Path $cfgDir | Out-Null
function DocUnderConfig([string]$Json, [string]$QName) {
  WriteAscii (Join-Path $cfgDir '.drag-lint.json') $Json
  Push-Location $cfgDir
  try { return (& $exePath document --qname $QName --db $db 2>$null | Out-String) }
  finally { Pop-Location }
}
$off = DocUnderConfig '{ "docs": { "dialog_routines": [] } }' 'exchandles.DialogHandler'
Check 'dialog_routines: [] is the OFF switch -- the dialog handler becomes (swallowed)' `
  ((CatchesOf $off) -eq 'EConvertError (swallowed)') "got: '$(CatchesOf $off)'"
$cus = DocUnderConfig '{ "docs": { "dialog_routines": ["Log"] } }' 'exchandles.SwallowHandler'
Check 'a custom list replaces the built-in one -- Log becomes the dialog witness' `
  ((CatchesOf $cus) -eq 'EFOpenError (dialog: Log)') "got: '$(CatchesOf $cus)'"
$cs2 = DocUnderConfig '{ "docs": { "dialog_routines": ["log"] } }' 'exchandles.SwallowHandler'
Check 'the match is case-insensitive and the witness keeps the SOURCE spelling' `
  ((CatchesOf $cs2) -eq 'EFOpenError (dialog: Log)') "got: '$(CatchesOf $cs2)'"
$cp3 = DocUnderConfig '{ "docs": { "max_handles": 3 } }' 'exchandles.CapHandler'
Check 'max_handles: 3 caps at three with (+7 more)' `
  (((CatchesOf $cp3) -match '\(\+7 more\)$') -and (@([regex]::Matches((CatchesOf $cp3), '\(swallowed\)')).Count -eq 3)) `
  "got: '$(CatchesOf $cp3)'"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
