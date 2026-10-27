unit DisallowedType;

interface

type
  TLegacyList = class
  end;

implementation

uses
  System.Classes;

procedure Probe;
var
  L: TStringList;
  Q: TLegacyList;
  S: string;
begin
  L:= TStringList.Create;
  Q:= TLegacyList.Create;
  S:= 'TStringList in a string';
  // TStringList in a comment
  L.Free;
end;

end.
