unit uTools;

{ v156 CON-Q fixture: field names used through a parameter (by name only). }

interface

uses
  uMain;

/// <summary>Copies the buyer from one row to another.</summary>
procedure CopyName(pDs: TDataSetStub);

implementation

procedure CopyName(pDs: TDataSetStub);
var
  Text: string;
begin
  Text:= pDs.FieldByName('NAME').AsString;
  Text:= Text + pDs.FieldByName('ID').AsString;
  Text:= Text + pDs.FieldByName('ID').AsString;
  Text:= Text + pDs.FieldByName('ID').AsString;
  Text:= Text + pDs.FieldByName('ID').AsString;
end;

end.
