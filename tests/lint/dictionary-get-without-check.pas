unit DictionaryGetWithoutCheck;

interface

uses
  System.Generics.Collections;

type
  TPrices = TDictionary<string, Integer>;

  TShop = class
  private
    FPrices: TPrices;
    FOwners: TObjectDictionary<string, TObject>;
  public
    function Price(const AKey: string): Integer;
    function SafePrice(const AKey: string): Integer;
    function Owner(const AKey: string): TObject;
    procedure Fill;
    function Total: Integer;
  end;

implementation

function TShop.Price(const AKey: string): Integer;
begin
  Result := FPrices[AKey]; // MUST-FIRE alias type
end;

function TShop.SafePrice(const AKey: string): Integer;
begin
  if FPrices.ContainsKey(AKey) then
    Result := FPrices[AKey] // guarded
  else
    Result := 0;
end;

function TShop.Owner(const AKey: string): TObject;
begin
  Result := FOwners.Items[AKey]; // MUST-FIRE Items form
end;

procedure TShop.Fill;
begin
  FPrices['a'] := 1; // write target, silent
  FPrices.Add('b', 2);
  FPrices['b'] := FPrices['b'] + 1; // silent: added before in this routine
end;

function TShop.Total: Integer;
var
  K: string;
begin
  Result := 0;
  for K in FPrices.Keys do
    Inc(Result, FPrices[K]); // silent: keys enumerated
end;

procedure Local;
var
  D: TDictionary<Integer, string>;
  S: string;
begin
  D := TDictionary<Integer, string>.Create;
  try
    S := D[42]; // MUST-FIRE local
  finally
    D.Free;
  end;
end;

procedure Guarded;
var
  D: TDictionary<Integer, string>;
  S: string;
begin
  D := TDictionary<Integer, string>.Create;
  try
    if D.TryGetValue(7, S) then
      S := D[7];
  finally
    D.Free;
  end;
end;

procedure NotADictionary;
var
  L: TStringList;
  Arr: array[0..3] of string;
begin
  Arr[1] := 'x';
  L := nil;
end;

end.
