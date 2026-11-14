unit DictionaryGetWithoutCheckClean;

interface

implementation

uses
  System.Classes, System.Generics.Collections;

procedure Guarded;
var
  D: TDictionary<Integer, string>;
  S: string;
begin
  D := TDictionary<Integer, string>.Create;
  try
    if D.TryGetValue(7, S) then
      S := D[7];
    D[1] := 'x';
  finally
    D.Free;
  end;
end;

procedure Lists(const AList: TStringList);
var
  Arr: array[0..3] of string;
begin
  Arr[1] := AList[0];
end;

function MakeMap: TDictionary<string, Integer>;
begin
  Result := TDictionary<string, Integer>.Create;
end;

function MakeArr: TArray<Integer>;
begin
  SetLength(Result, 2);
  Result[0] := 1;
  Result[1] := Result[0]; // Result is an array here, not the dictionary of MakeMap
end;

end.
