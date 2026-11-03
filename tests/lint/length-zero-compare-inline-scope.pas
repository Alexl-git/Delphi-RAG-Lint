unit LZCInlineScope;

interface

implementation

{ INLINEVAR-SCOPE: two routines each declare S, one in its var section as a
  string, one as an inline TArray<Integer> inside a block. A flat file-wide
  type map makes S ambiguous everywhere and silences the string rule in P;
  scoped lookup keeps each S to its own routine / block. }
procedure P;
var
  S: string;
begin
  S:= 'x';
  if Length(S) = 0 then
    WriteLn('a');
end;

procedure Q;
begin
  begin
    var S: TArray<Integer>;
    S:= [1];
    if Length(S) = 0 then
      WriteLn('b');
  end;
end;

end.
