unit EnumUser;

interface

uses
  System.Classes;

type
  TEnumUser = class(TObject)
  public
    procedure Run;
  end;

implementation

procedure TEnumUser.Run;
var
  C: TPlatCursor;
  G: TGoneCursor;
  S: TStuckOld;
begin
  C:= pcrDefault; { pcrDefault stays in this comment }
  C:= pcrHourGlass;
  C:= pcrSQLWait;
  C:= pcrAdded;
  C:= pcrOther;
  G:= gcoWait;
  S:= stkA;
end;

end.
