unit inlinelarge;
interface

function Tiny(A: Integer): Integer; inline;
function WithTry(A: Integer): Integer; inline;
function Long(A: Integer): Integer; inline;
function Edge(A: Integer): Integer; inline;
function NotInline(A: Integer): Integer;
function Ovl(A: Integer): Integer; overload; inline;
function Ovl(A, B: Integer): Integer; overload;

implementation

function Tiny(A: Integer): Integer;
begin
  Result := A + 1;
end;

function WithTry(A: Integer): Integer;
begin
  try
    Result := A + 1;
  except
    Result := 0;
  end;
end;

function Long(A: Integer): Integer;
begin
  Result := A;
  Result := Result + 1;
  Result := Result + 2;
  Result := Result + 3;
  Result := Result + 4;
  Result := Result + 5;
  Result := Result + 6;
  Result := Result + 7;
  Result := Result + 8;
  Result := Result + 9;
  Result := Result + 10;
  Result := Result + 11;
  Result := Result + 12;
  Result := Result + 13;
  Result := Result + 14;
  Result := Result + 15;
  Result := Result + 16;
  Result := Result + 17;
  Result := Result + 18;
  Result := Result + 19;
  Result := Result + 20;
end;

function Edge(A: Integer): Integer;
begin
  Result := A;
  Result := Result + 1;
  Result := Result + 2;
  Result := Result + 3;
  Result := Result + 4;
  Result := Result + 5;
  Result := Result + 6;
  Result := Result + 7;
  Result := Result + 8;
  Result := Result + 9;
  Result := Result + 10;
  Result := Result + 11;
  Result := Result + 12;
  Result := Result + 13;
  Result := Result + 14;
  Result := Result + 15;
  Result := Result + 16;
end;

function NotInline(A: Integer): Integer;
begin
  try
    Result := A;
  finally
    Result := Result + 1;
  end;
end;

function Ovl(A: Integer): Integer;
begin
  Result := A;
end;

function Ovl(A, B: Integer): Integer;
begin
  try
    Result := A + B;
  except
    Result := 0;
  end;
end;

end.
