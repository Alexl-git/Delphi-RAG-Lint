unit UDialogs;

interface

procedure ShowDone;
procedure WrapDone(const AText: string);

implementation

uses
  Vcl.Dialogs;

procedure ShowDone;
begin
  ShowMessage('done');
end;

procedure WrapDone(const AText: string);
begin
  if AText <> '' then ShowDone;
end;

end.
