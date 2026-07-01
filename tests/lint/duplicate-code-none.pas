unit dupnone;

interface

implementation

function Greet(const AName: string): string;
begin
  Result := 'Hello, ' + AName + '!';
end;

procedure Countdown(AFrom: Integer);
var
  n: Integer;
begin
  n := AFrom;
  while n > 0 do
  begin
    Writeln(n);
    Dec(n);
  end;
end;

end.
