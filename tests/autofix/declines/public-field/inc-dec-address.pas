unit incdec;

{ A public field used with Inc/Dec/@ must stay a field: a property is not a variable, so
  `Inc(B.Hits)` / `Dec(B.Misses)` / `@B.Raw` stop compiling (E2081 in a for-in body). Found by
  the ORM3 --fix --apply build proof (uBroadcastServer: Inc(Sub.MissCount)). The fixer declines
  all three fields; the rule still fires. }

interface

type
  TBox = class
  public
    Hits: Integer;
    Misses: Integer;
    Raw: Integer;
  end;

implementation

procedure Run(B: TBox);
var
  P: PInteger;
begin
  Inc(B.Hits);
  Dec(B.Misses, 2);
  P:= @B.Raw;
  P^:= 0;
end;

end.
