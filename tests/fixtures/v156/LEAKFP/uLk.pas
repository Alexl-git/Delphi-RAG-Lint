unit uLk;

interface

type
  TMyRec = record
    FValue: Integer;
    class function Create(pValue: Integer): TMyRec; static;
    function Twice: Integer;
  end;

function UseRecord: Integer;
function UseRtlRecord: string;
function UseFmt: Char;
function LeakClass: Integer;

implementation

uses
  System.Classes, System.Hash, System.SysUtils;

class function TMyRec.Create(pValue: Integer): TMyRec;
begin
  Result.FValue := pValue;
end;

function TMyRec.Twice: Integer;
begin
  Result := FValue * 2;
end;

function UseRecord: Integer;
var
  VRec: TMyRec;
begin
  VRec := TMyRec.Create(3);
  Result := VRec.Twice;
end;

function UseRtlRecord: string;
var
  VHash: THashMD5;
begin
  VHash := THashMD5.Create;
  VHash.Update('abc');
  Result := VHash.HashAsString;
end;

function UseFmt: Char;
var
  VFmt: TFormatSettings;
begin
  VFmt := TFormatSettings.Create;
  Result := VFmt.DecimalSeparator;
end;

function LeakClass: Integer;
var
  VList: TStringList;
begin
  VList := TStringList.Create; // FIRE object-leak
  VList.Add('x');
  Result := VList.Count;
end;

end.
