unit UChain;

{ G-64: accumulator chains. A class-method fetch that fills a parameter is the fetch-chain idiom (silent);
  a free function and a method that writes its own field stay flagged. }

interface

type
  TRdr = class
  private
    FPos: Integer;
  public
    function Fetch(var AVal: Integer): Boolean;
    function Bump: Boolean;
  end;

function Pop(var AList: Integer): Boolean;
procedure Driver;

implementation

function TRdr.Fetch(var AVal: Integer): Boolean;
begin
  AVal:= 7;
  Result:= True;
end;

function TRdr.Bump: Boolean;
begin
  FPos:= FPos + 1;
  Result:= FPos > 1;
end;

function Pop(var AList: Integer): Boolean;
begin
  AList:= AList - 1;
  Result:= AList > 0;
end;

procedure Driver;
var
  R : TRdr;
  N : Integer;
  Ok: Boolean;
begin
  R := TRdr.Create;
  N := 3;
  Ok:= N > 0;
  Ok:= Ok and R.Fetch(N);                      { RS-CONTROL-1: fetch chain, silent }
  Ok:= Ok and R.Fetch(N);                      { RS-CONTROL-2: fetch chain, silent }
  Ok:= Ok and Pop(N);                          { RS-TRIGGER-1: free function accumulator }
  Ok:= Ok and R.Bump;                          { RS-TRIGGER-2: method writing its own field }
  R.Free;
end;

end.