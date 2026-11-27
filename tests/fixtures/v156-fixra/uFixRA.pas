unit uFixRA;

interface

uses
  System.SysUtils, System.Classes;

{ the fixture is indexed, never compiled: SetQty / SetG take an Integer and are handed a tainted string, the shape of an untyped property or function result (REV-1 finding 1) }
procedure DriveAll;

implementation

type
  TOrd = class
  private
    FQty : Integer;
    FName: string;
  public
    procedure SetQty(pQty: Integer);
    procedure SetName(const pName: string);
    procedure UseQty;
    procedure UseName;
  end;

var
  GQty : Integer;
  GName: string;

procedure TOrd.SetQty(pQty: Integer);
begin
  FQty:= pQty;
end;

procedure TOrd.SetName(const pName: string);
begin
  FName:= pName;
end;

procedure TOrd.UseQty;
begin
  DeleteFile(Format('%d', [FQty]));                          { FIELDINT }
end;

procedure TOrd.UseName;
begin
  DeleteFile(FName);                                   { FIELDSTR }
end;

procedure SetG(pQty: Integer);
begin
  GQty:= pQty;
end;

procedure SetGS(const pName: string);
begin
  GName:= pName;
end;

procedure UseGlobals;
begin
  DeleteFile(Format('%d', [GQty]));                          { GLOBINT }
  DeleteFile(GName);                                   { GLOBSTR }
end;

procedure DriveAll;
var
  O: TOrd;
begin
  O:= TOrd.Create;
  try
    O.SetQty(GetEnvironmentVariable('X'));
    O.SetName(GetEnvironmentVariable('Y'));
    O.UseQty;
    O.UseName;
  finally
    O.Free;
  end;
  SetG(GetEnvironmentVariable('X'));
  SetGS(GetEnvironmentVariable('Y'));
  UseGlobals;
end;

end.