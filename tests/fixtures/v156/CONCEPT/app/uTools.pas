unit uTools;

interface

uses
  Data.DB;

procedure CopyName(pDs: TDataSet);

implementation

procedure CopyName(pDs: TDataSet);
begin
  pDs.FieldByName('NAME').AsString := pDs.FieldByName('ID').AsString;
end;

end.
