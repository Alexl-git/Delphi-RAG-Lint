unit uResUse;

{ Project side of the run_v1511_RES_*.ps1 runners. Every routine names one
  declaration of the library unit ResLib; the runners find a site by its
  routine and its text, so lines may move. }

interface

uses
  ResLib;

procedure OpenInline;
procedure OpenInlineCall;
procedure OpenParens;
procedure OpenBare;
procedure OpenChain;
procedure OpenParam(AReg: TResStore);
procedure OpenShadow(ResReg: TObject);
procedure ReadApp;
function CheckBump(AFlag: Boolean): Boolean;
function WrapBare: Boolean;
function AddrOnly: Pointer;
function ArgOnly: Pointer;

implementation

procedure OpenInline;
begin
  var Reg := ResReg;
  Reg.OpenKey;
end;

procedure OpenInlineCall;
begin
  var RegC := ResReg();
  RegC.OpenKey;
end;

procedure OpenParens;
begin
  ResReg().OpenKey;
end;

procedure OpenBare;
begin
  ResReg.OpenKey;
end;

procedure OpenChain;
begin
  ResReg.Sub.OpenKey;
end;

procedure OpenParam(AReg: TResStore);
begin
  AReg.OpenKey;
end;

procedure OpenShadow(ResReg: TObject);
begin
  if ResReg.ClassType = nil then Exit;
end;

procedure ReadApp;
begin
  GResApp.OpenKey;
end;

function CheckBump(AFlag: Boolean): Boolean;
begin
  Result := False;
  if AFlag and ResBump then Result := True;
end;

function WrapBare: Boolean;
begin
  Result := ResBump;
end;

function AddrOnly: Pointer;
begin
  Result := @ResBump;
end;

function ArgOnly: Pointer;
begin
  Result := @ResNeedsArg;
end;

end.
