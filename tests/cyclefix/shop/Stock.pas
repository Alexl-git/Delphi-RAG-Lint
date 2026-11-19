unit Stock;

interface

procedure CheckStock;

implementation

uses
  AppMain;

procedure CheckStock;
begin
  if AppMainForm.Ready then
    AppMainForm.Note('stock checked');
end;

end.
