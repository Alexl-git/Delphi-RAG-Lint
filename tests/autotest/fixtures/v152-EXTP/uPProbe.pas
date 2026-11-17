unit uPProbe;

interface

uses
  System.SysUtils, System.Classes, uPDefs;

type
  TPProbe = class
  private
    edtF1: TPEdit;
    edtF2: TPEdit;
    FArr: array of TPItem;
    FTag: Integer;
  public
    procedure WriteChain(const pName: string);
    procedure WriteSelfChain(const pName: string);
    function ReadChain: string;
    procedure WriteBare;
    function ReadIndexed(const pIdx: Integer): Integer;
    function AnonUse: Integer;
    procedure AnonUnused;
    procedure NamedUnused(pUnused: Integer);
    procedure TryIt;
    procedure WriteOnly;
  end;

implementation

procedure TPProbe.WriteChain(const pName: string);
begin
  edtF1.DataBinding.DataField := pName;
end;

procedure TPProbe.WriteSelfChain(const pName: string);
begin
  Self.edtF2.DataBinding.DataField := pName;
end;

function TPProbe.ReadChain: string;
begin
  Result := edtF1.DataBinding.DataField;
end;

procedure TPProbe.WriteBare;
begin
  edtF2 := nil;
end;

function TPProbe.ReadIndexed(const pIdx: Integer): Integer;
begin
  Result := FArr[pIdx].Count;
end;

function TPProbe.AnonUse: Integer;
var
  lF: TPFunc;
begin
  lF := function(const pA: Integer; pB: string): Integer
    begin
      Result := pA + Length(pB);
    end;
  Result := lF(1, 'x');
end;

procedure TPProbe.AnonUnused;
var
  lP: TPProc;
begin
  lP := procedure(pSender: TObject)
    begin
      FTag := 1;
    end;
  lP(nil);
end;

procedure TPProbe.NamedUnused(pUnused: Integer);
begin
  FTag := 2;
end;

procedure TPProbe.TryIt;
begin
  try
    FTag := StrToInt('x');
  except
    on E: EConvertError do
      raise Exception.Create(E.Message);
    on EUnused: EAbort do
      FTag := 0;
  end;
end;

procedure TPProbe.WriteOnly;
var
  lDead: Integer;
begin
  lDead := 3;
end;

end.
