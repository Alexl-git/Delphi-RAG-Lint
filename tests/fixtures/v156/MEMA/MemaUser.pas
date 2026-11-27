unit MemaUser;

{ Fixture of 1.56 lane MEM-A: the item class lives in another unit (MemaItems).
  With the project index the class is known and the rule reports; without it the rule stays silent. }

interface

uses
  System.Generics.Collections, MemaItems;

procedure LeakOtherUnitClass;
procedure OkOtherUnitRecord;

implementation

procedure LeakOtherUnitClass;
var
  L: TList<TFoo>;
begin
  L:= TList<TFoo>.Create;
  try
    L.Add(TFoo.Create); // FIRE container-items-leak
  finally
    L.Free;
  end;
end;

procedure OkOtherUnitRecord;
var
  L: TList<TRec>;
begin
  L:= TList<TRec>.Create;
  try
    L.Add(TRec.Create(2));
  finally
    L.Free;
  end;
end;

end.
