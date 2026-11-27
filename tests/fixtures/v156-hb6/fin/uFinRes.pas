unit uFinRes;

{ v156 HB6 fixture: --preset finalization. Each global is freed (or not) by this unit's
  finalization section; who uses it afterwards differs per variable. }

interface

uses
  System.Classes, System.SysUtils;

var
  GLog: TStringList;
  GCache: TStringList;
  GLate: TStringList;
  GPlain: TStringList;
  GHelper: TStringList;
  GOrder1: TStringList;
  GOrder2: TStringList;

procedure Log(const pText: string);
procedure Cleanup5;

implementation

procedure Log(const pText: string);
begin
  GLog.Add(pText);
end;

procedure Cleanup5;
begin
  FreeAndNil(GHelper);
end;

initialization
  GLog := TStringList.Create;
  GCache := TStringList.Create;
  GLate := TStringList.Create;
  GPlain := TStringList.Create;
  GHelper := TStringList.Create;
  GOrder1 := TStringList.Create;
  GOrder2 := TStringList.Create;

finalization
  FreeAndNil(GLog);
  GCache.Free;
  FreeAndNil(GLate);
  Cleanup5;
  GOrder1.Add('last');
  FreeAndNil(GOrder1);
  FreeAndNil(GOrder2);
  GOrder2.Add('late');
end.
