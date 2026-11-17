unit evgData;

interface

type
  TEvgCb = procedure;

  TEvgCfg = class
  public
    FName: string;
    class var CInstances: Integer;
  public
    procedure Init;
    property Name: string read FName write FName;
  end;

  TEvgRec = record
    RVal: Integer;
  end;

const
  cEvgTyped: Integer = 3;

var
  GCache: TObject;
  GCount: Integer;
  GPtr: Pointer;
  GIntf: IInterface;
  GProc: TEvgCb;
  GAmb: Integer;
  GNever: Integer;
  GRec: TEvgRec;

procedure SetUp;
procedure CallA;
procedure CallB;
procedure Reset;
procedure UseIt;

implementation

uses
  System.SysUtils;

procedure SetUp;
begin
  GCache := TObject.Create;
  GCount := 1;
end;

procedure CallA;
begin
  SetUp;
end;

procedure CallB;
begin
  SetUp;
end;

procedure Reset;
begin
  GCache := nil;
  GPtr := nil;
  GIntf := nil;
  GProc :=
    nil;
  FreeAndNil(GCache);
end;

procedure UseIt;
var
  L: Integer;
begin
  if Assigned(GCache) then
    GCache.Free;
  if GPtr <> nil then
    L := GCount + GNever
  else
    L := GAmb;
  if GProc = nil then
    Exit;
  L := L + TEvgCfg.CInstances + GRec.RVal + cEvgTyped;
end;

procedure TEvgCfg.Init;
begin
  FName := 'x';
  CInstances := CInstances + 1;
end;

end.
