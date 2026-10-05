unit uHelpers6;

interface

procedure OpenAssignGroups;

implementation

uses
  uGroups6;

procedure OpenAssignGroups;
var
  F: TfrmGroups6;
begin
  F := TfrmGroups6.Create(nil);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.