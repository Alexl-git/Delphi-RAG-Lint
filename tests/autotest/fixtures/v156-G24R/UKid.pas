unit UKid;

{ Descendant of UTight.TBase in ANOTHER unit, plus an unrelated caller. }

interface

uses
  UTight;

type
  TKid = class(TBase)
  public
    procedure Work(Other: TBase);
  end;

procedure CallAll(B: TBase);

implementation

procedure TKid.Work(Other: TBase);
begin
  ForKids;
  ForKidsPublic;
  Other.ForKidsOtherInstance;
end;

procedure CallAll(B: TBase);
begin
  B.UsedByAll;
end;

end.
