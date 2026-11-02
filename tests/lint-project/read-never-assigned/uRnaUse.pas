unit uRnaUse;

{ Second unit of the read-never-assigned fixture: the cross-unit reads and
  writes of the fields and globals uRnaDecl declares. }

interface

uses
  uRnaDecl;

function Compute(const pObj: TObject): Integer;

implementation

function Compute(const pObj: TObject): Integer;
var
  H: TRnaHolder;
  R: TRnaRec;
begin
  H:= TRnaHolder.Create;
  H.FSetElsewhere:= 2;
  TRnaHolder(pObj).FCast:= 3;
  with H do FWith:= 5;
  H.Size:= 6;
  R.RX:= 1;
  Result:= H.Total + GLimit + GInitSec + GInitVal + GAbs + GCounter + CTyped + R.RX;
end;

end.
