unit ueh;
{ Fixture: event-handler Sender-first guard for unused-parameter rule. }
interface
type
  TObject = class end;
  TShiftState = set of (ssShift, ssCtrl, ssAlt);
  TForm1 = class
    procedure Button1Click(Sender: TObject);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
  end;
procedure Plain(A, B: Integer);
implementation
{ Event handler with only Sender -- Sender unused, whole method skipped. }
procedure TForm1.Button1Click(Sender: TObject);
begin
end;
{ Event handler with multiple unused params (X, Y, Shift) -- whole method
  skipped because first param is Sender. }
procedure TForm1.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
end;
{ Non-event-handler: B is genuinely unused -- must still fire. }
procedure Plain(A, B: Integer);
begin
  WriteLn(A);
end;
end.
