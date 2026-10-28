unit sibling;

{ A converted field becomes a property in place; a later sibling field that stays a field (it is an
  Inc target) would then follow a property: E2169 "Field definition not allowed after methods or
  properties". The fixer must decline the earlier sibling too. Found by the ORM3 --fix --apply
  build proof (uBroadcastServer.TBroadcastSub). }

interface

type
  TBox = class
  public
    Name: string;
    Hits: Integer;
  end;

implementation

procedure Run(B: TBox);
begin
  Inc(B.Hits);
end;

end.
