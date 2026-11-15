unit LibFxUse;

{ Project side of run_v151_LIBFX_lib_effects.ps1: every routine calls one
  library routine of LibFxLib, so its verdict depends on the library summary. }

interface

uses
  LibFxLib;

function Wrap: Boolean;
function CheckBoth(AFlag: Boolean): Boolean;
function SumWrap(A: Integer): Integer;
function CheckPure(AFlag: Boolean): Boolean;
function VirtWrap(AObj: TLibFxObj): Boolean;
function CheckVirt(AFlag: Boolean; AObj: TLibFxObj): Boolean;
procedure FreeWrap;

implementation

function Wrap: Boolean;
begin
  Result := BumpCounter();
end;

function CheckBoth(AFlag: Boolean): Boolean;
begin
  Result := AFlag and Wrap();
end;

function SumWrap(A: Integer): Integer;
begin
  Result := PlainSum(A, 1);
end;

function CheckPure(AFlag: Boolean): Boolean;
begin
  Result := AFlag and (SumWrap(2) > 0);
end;

function VirtWrap(AObj: TLibFxObj): Boolean;
begin
  AObj.VirtBump();
  Result := True;
end;

function CheckVirt(AFlag: Boolean; AObj: TLibFxObj): Boolean;
begin
  Result := AFlag and VirtWrap(AObj);
end;

procedure FreeWrap;
begin
  FreeTemp();
end;

end.
