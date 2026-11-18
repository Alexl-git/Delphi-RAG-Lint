unit UOther;

{ Not used by ConsoleProg: its Hello shows a dialog, and must not leak into the program's closure. }

interface

procedure Hello;

implementation

uses
  Vcl.Dialogs;

procedure Hello;
begin
  ShowMessage('hello');
end;

end.
