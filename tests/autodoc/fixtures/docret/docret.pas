unit docret;
interface

function Pick(A: Integer): Integer; overload;
function Pick(const A: string): string; overload;

/// <summary>Existing doc carrying a hand-written returns.</summary>
/// <returns>The doubled value.</returns>
function Doubler(X: Integer): Integer;

function Flag(B: Boolean): string;
function UseFlag: string;

implementation

function UseFlag: string;
begin
  Result:= Flag(True);
end;

function Pick(A: Integer): Integer;
begin
  Result:= A;
end;

function Pick(const A: string): string;
begin
  Result:= A;
end;

function Doubler(X: Integer): Integer;
begin
  Result:= X * 2;
end;

function Flag(B: Boolean): string;
begin
  if B then Result:= 'yes' else Result:= 'no';
end;

end.
