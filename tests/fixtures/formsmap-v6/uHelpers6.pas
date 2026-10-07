unit uHelpers6;

interface

procedure OpenAssignGroups;
procedure OpenAfter6;

implementation

uses
  uGroups6, uAfter6;

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

procedure OpenAfter6;
begin
  TfrmAfter6.Create(nil).ShowModal;
end;

end.