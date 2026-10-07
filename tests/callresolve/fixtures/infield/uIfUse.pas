unit uIfUse;

interface

uses
  uIfBase;

var
  FUnitLevel: Integer;

type
  TIfOther = class
  public
    FOwn: Integer;
    FUnitLevel: Integer;
  end;

  TIfLeaf = class(TIfMiddle)
  private
    FOwn: Integer;
    FP: Integer;
    function GetP: Integer;
  public
    property P: Integer read GetP;
    procedure UseOwn;
    procedure UseAncestor;
    procedure UseParam(FOwn: Integer);
    procedure UseLocal;
    procedure UseNested;
    procedure UseWith(AOther: TIfOther);
    procedure UseControls;
  end;

implementation

function TIfLeaf.GetP: Integer;
begin
  Result:= FP; // F-GETTER
end;

procedure TIfLeaf.UseOwn;
var
  N: Integer;
begin
  N:= FOwn; // F-OWN
  if N > 0 then N:= FUnitLevel; // F-UNRELATED
end;

procedure TIfLeaf.UseAncestor;
var
  N: Integer;
begin
  N:= FMid; // F-ANC1
  N:= N + FBaseCount; // F-ANC2
  if tblFtrs.State = 0 then // F-ANC-RCV
    tblFtrs.Post; // F-ANC-CALL
  with tblFtrs do // F-ANC-WITH
    Post;
end;

procedure TIfLeaf.UseParam(FOwn: Integer);
var
  N: Integer;
begin
  N:= FOwn; // F-SHADOW-PARAM
end;

procedure TIfLeaf.UseLocal;
var
  FMid: Integer;
  N   : Integer;
begin
  FMid:= 1;
  N:= FMid; // F-SHADOW-LOCAL
end;

procedure TIfLeaf.UseNested;
var
  FBaseCount: Integer;

  function Inner: Integer;
  begin
    Result:= FBaseCount + FOwn; // F-NESTED
  end;

begin
  FBaseCount:= Inner;
end;

procedure TIfLeaf.UseWith(AOther: TIfOther);
var
  N: Integer;
begin
  with AOther do
    N:= FOwn; // F-SHADOW-WITH
end;

procedure TIfLeaf.UseControls;
var
  N: Integer;
begin
  N:= Self.FOwn; // F-SELF
  N:= N + P; // F-PROP
  FOwn:= N; // F-WRITE
end;

end.
