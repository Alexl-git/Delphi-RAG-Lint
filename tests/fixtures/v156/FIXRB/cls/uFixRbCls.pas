unit uFixRbCls;

{ v156 FIXR-B #6 (REV-1): the declared scalar class of a field / function result is looked up in
  the SCOPE that declares it (owner type + name), never by the bare name alone.
  Fixture only: read by tests\autotest\run_v156_FIXRB.ps1 through the M-xxx markers. }

interface

type
  TOther = class
  private
    FLabel: string;
  public
    property Total: string read FLabel;
  end;

  TShape = record
    CharLength: string;
  end;

  TOrderA = class
  private
    FCode : Integer;
    FSum  : Currency;
    FOther: TOther;
    FSelf : TOrderA;
  public
    function Total: Currency;
    procedure ShowCode;
    procedure TakeOther(pOther: TOther);
    procedure TakeSelf(pOrder: TOrderA);
    procedure TakeRec(const pRec: TShape);
    procedure ViaFields;
    procedure OwnBare;
  end;

  TOrderB = class
  private
    FCode: string;
  public
    procedure ShowCode;
  end;

function CharLength: Integer;
procedure SinkI(V: Integer);
procedure SinkC(V: Currency);
procedure SinkS(const V: string);
procedure ReadRate;
procedure Shadow(const pText: string);
procedure BareCall;

var
  GRate: Currency;

implementation

function CharLength: Integer;
begin
  Result := 0;
end;

procedure SinkI(V: Integer);
begin
end;

procedure SinkC(V: Currency);
begin
end;

procedure SinkS(const V: string);
begin
end;

function TOrderA.Total: Currency;
begin
  Result := FSum;
end;

{ the same field name in two classes: each row takes the class of ITS owner's field }
procedure TOrderA.ShowCode;
begin
  SinkI(FCode); { M-CODE-A }
end;

procedure TOrderB.ShowCode;
begin
  SinkS(FCode); { M-CODE-B }
end;

{ WRONG before the fix: TOther.Total is a string property, TOrderA.Total a Currency function }
procedure TOrderA.TakeOther(pOther: TOther);
begin
  SinkS(pOther.Total); { M-OTHER }
end;

{ POSITIVE CONTROL: the receiver's type declares Total as a Currency function }
procedure TOrderA.TakeSelf(pOrder: TOrderA);
begin
  SinkC(pOrder.Total); { M-SELF }
end;

{ WRONG before the fix: a record field named like a unit function }
procedure TOrderA.TakeRec(const pRec: TShape);
begin
  SinkS(pRec.CharLength); { M-REC }
end;

procedure TOrderA.ViaFields;
begin
  SinkS(FOther.Total); { M-FIELD-OTHER }
  SinkC(FSelf.Total); { M-FIELD-SELF }
end;

{ a bare name inside a method: the owner's own function }
procedure TOrderA.OwnBare;
begin
  SinkC(Total); { M-OWN-BARE }
end;

{ a bare call of a unit function keeps its class }
procedure BareCall;
begin
  SinkI(CharLength); { M-BARE }
end;

{ two variables named GRate in different scopes, of different types }
procedure ReadRate;
begin
  SinkC(GRate); { M-GLOBAL }
end;

procedure Shadow(const pText: string);
var
  GRate: string;
begin
  GRate := pText;
  SinkS(GRate); { M-LOCAL }
end;

end.
