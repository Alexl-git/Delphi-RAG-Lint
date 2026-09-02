unit tryhandlerreadsbodylocal;

{ Fixture for C1 -- an assignment inside a try body whose ONLY reader is the
  except handler.

  TAKEN FROM THE REAL CODE, NOT PARAPHRASED. The paraphrase in
  INBOX-flow-analysis-fps-that-are-dangerous-to-act-on.md was built as a
  synthetic three-liner, came back silent, and was read as "probably already
  fixed" -- it was not. What the paraphrase dropped is the BRANCH: the real
  routine (DataCopy uMahrRoutines.pas, the block around 704-712) has an
  `if ... then begin ... exit; end;` between the try entry and the assignment,
  so the assignment lands in a LATER basic block than the try region entry.

  That is the whole defect. DRagLint.Analysis.Cfg wires only

      Cfg.Blocks[BodyIdx].AddSucc(HdrIdx);   // try entry -> handler

  so a handler read is reachable only from the try ENTRY block. An assignment
  in any later block of the body has no path to the handler at all, the
  handler's read is invisible to it, and the store reads as dead. }

interface

type
  TThing = class
  private
    FLogged: string;
    function RollBackOutput: Boolean;
    procedure DoWork;
    procedure ReportChanged;
  public
    function Transfer(const AFile: string; out AMess: string): Boolean;
    { Control: the SAME shape with no branch, so the assignment stays in the
      try entry block. This one was never broken, and it must stay silent -- if
      a fix makes THIS fire, the fix is wrong. }
    function TransferNoBranch(out AMess: string): Boolean;
    { POSITIVE CONTROL: a genuinely dead store, in a try body, read by nobody --
      not by the handler, not after the try. This MUST still be reported, or a
      "fix" that simply stops analysing try bodies would pass. }
    function TransferDeadStore: Boolean;
  end;

implementation

uses
  System.SysUtils;

function TThing.RollBackOutput: Boolean;
begin
  Result := True;
end;

procedure TThing.DoWork;
begin
end;

procedure TThing.ReportChanged;
begin
end;

function TThing.Transfer(const AFile: string; out AMess: string): Boolean;
var
  LOpened : Boolean;
  LWritten: Boolean;
  LChanged: Boolean;
begin
  Result   := False;
  LOpened  := False;
  LWritten := False;
  try
    LOpened := True;
    DoWork;
    LChanged := AFile = '';
    { THE BRANCH. This is what puts the assignments below into a later basic
      block than the try region entry, and it is exactly what the synthetic
      paraphrase left out. }
    if LChanged then
    begin
      ReportChanged;
      Exit;
    end;
    { Both of these are read ONLY by the handler below. Neither is a dead
      store, and neither may be reported. }
    LOpened  := False;
    LWritten := True;
    DoWork;
  except
    on E: Exception do
    begin
      Result := False;
      if LOpened and (not RollBackOutput) then
        AMess := 'partial block left behind';
      if LWritten then
        AMess := AMess + ' (rows were written)';
    end;
  end;
end;

function TThing.TransferNoBranch(out AMess: string): Boolean;
var
  LOpened: Boolean;
begin
  Result  := False;
  LOpened := False;
  try
    LOpened := True;
    DoWork;
  except
    on E: Exception do
      if LOpened then AMess := 'was open';
  end;
end;

function TThing.TransferDeadStore: Boolean;
var
  LUnread: Integer;
  LFlag  : Boolean;
begin
  Result := False;
  LFlag  := False;
  try
    DoWork;
    { The same BRANCH as Transfer, so LUnread below lands in a later basic block
      too. Without it this control would only prove that dead stores in the try
      ENTRY block are still caught, which is not the property under test. }
    if LFlag then
    begin
      DoWork;
      Exit;
    end;
    { Overwritten on every path before any read. The handler deliberately reads
      NOTHING from the try body, so no amount of extra body->handler edges can
      make this store live. A real dead store, and it must stay reported. }
    LUnread := 41;
    LUnread := 42;
    Result  := LUnread > 0;
  except
    on E: Exception do
      Result := False;
  end;
end;

end.
