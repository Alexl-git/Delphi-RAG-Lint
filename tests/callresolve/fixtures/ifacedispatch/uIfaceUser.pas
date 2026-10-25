unit uIfaceUser;

{ Fixture for run_interface_dispatch_bind.ps1 -- the CALL SITES. Each call is on
  its own line, found by the guard through its exact trimmed text. }

interface

uses
  uIfaceCopy;

type
  THolder = class
  private
    FCopy: ICopy;
    function GetCopy: ICopy;
    function GetImpl: TImplCopy;
  public
    property Copy: ICopy read FCopy;
    procedure ViaField;
    procedure ViaProp;
    procedure ViaMethodResult;
  end;

procedure ViaLocal;
procedure ViaParam(const P: ICopy);
procedure ViaDerived(const D: ICopy2);
procedure ViaClass;
procedure ViaSubClass;
procedure ViaFreeResult;
procedure ViaShadowedResult;
function MakeCopy: ICopy;
function MakeImpl: TImplCopy;

implementation

procedure ViaLocal;
var
  M: ICopy;
begin
  M:= TImplCopy.Create;
  M.TransferFile('local');
end;

procedure ViaParam(const P: ICopy);
begin
  P.TransferFile('param');
end;

procedure ViaDerived(const D: ICopy2);
begin
  D.TransferFile('derived');
end;

procedure ViaClass;
var
  C: TImplCopy;
begin
  C:= TImplCopy.Create;
  C.TransferFile('class');
end;

procedure ViaSubClass;
var
  S: TSubCopy;
begin
  S:= TSubCopy.Create;
  S.TransferFile('subclass');
end;

function MakeCopy: ICopy;
begin
  Result:= TImplCopy.Create;
end;

function MakeImpl: TImplCopy;
begin
  Result:= TImplCopy.Create;
end;

procedure ViaFreeResult;
begin
  MakeCopy.TransferFile('free');
  MakeCopy().TransferFile('parens');
  MakeImpl.TransferFile('implresult');
end;

procedure ViaShadowedResult;
var
  MakeCopy: TOtherCopy;
begin
  MakeCopy:= TOtherCopy.Create;
  MakeCopy.TransferFile('shadow');
end;

function THolder.GetCopy: ICopy;
begin
  Result:= FCopy;
end;

function THolder.GetImpl: TImplCopy;
begin
  Result:= nil;
end;

procedure THolder.ViaField;
begin
  FCopy.TransferFile('field');
end;

procedure THolder.ViaProp;
begin
  Copy.TransferFile('prop');
end;

procedure THolder.ViaMethodResult;
begin
  GetCopy.TransferFile('method');
  GetImpl.TransferFile('implmethod');
end;

end.