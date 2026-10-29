unit uRefInitDefs;

{ Lane REFTYPE fixture: the constants and types uRefInitProbe names only in
  initializer / bound / default-value / attribute-argument positions. }

interface

type
  TRiEnum = (riK1, riK2);
  TRiRec = record
    F: Integer;
  end;
  TRiSz = record
    G: Int64;
  end;
  RiAttrAttribute = class(TCustomAttribute)
  public
    constructor Create(pValue: Integer);
  end;

const
  RiA = 1;
  RiB = 2;
  RiC1 = 3;
  RiC2 = 4;
  RiD = 5;
  RiE = 6;
  RiF = 7;
  RiG = 8;
  RiH = 9;
  RiJ = 10;
  RiLo = 11;
  RiHi = 12;
  RiLo2 = 13;
  RiHi2 = 14;
  RiS = 'text';

implementation

constructor RiAttrAttribute.Create(pValue: Integer);
begin
  inherited Create;
  if pValue = 0 then Exit;
end;

end.