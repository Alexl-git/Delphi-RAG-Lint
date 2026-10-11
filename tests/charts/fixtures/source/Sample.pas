unit Sample;

interface

procedure Run;

implementation

{$IFDEF DEBUG}
const Mode = 'debug';
{$ENDIF}

procedure Run;
var
  S: string;
begin
  S:= '{';  // a brace inside a string is not a comment
  (* a comment that
     spans two lines *) S:= S + 'it''s';


  Writeln(S); { trailing } Writeln('//');
end;

end.
