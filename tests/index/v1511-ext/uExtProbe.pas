unit uExtProbe;

interface

uses
  uExtDefs;

type
  TExtChild = class(TExtItem)
  private
    FItems: TExtItemArray;
    FObjs: array of TObject;
    FCount2: Integer;
    function GetShown: Integer;
  public
    procedure Run; override;
    function Calc(const pA: Integer): Integer; override;
    function ProbeResult: Integer;
    function ProbeIndexer(const pIdx: Integer): string;
    function ProbeCast(const pIdx: Integer): string;
    function ProbeForIn: Integer;
    property Shown: Integer read GetShown;
    property Mirror: Integer read FCount2 write FCount2;
  end;

const
  cExtRec: TExtRec = (Alpha: 1; Beta: 'b');
  cExtRecs: array[0..1] of TExtRec = ((Alpha: 2; Beta: 'c'), (Alpha: 3; Beta: 'd'));

implementation

function TExtChild.GetShown: Integer;
begin
  Result := FCount2;
end;

procedure TExtChild.Run;
begin
  inherited Run;
  inherited;
end;

function TExtChild.Calc(const pA: Integer): Integer;
begin
  Result := inherited Calc(pA) + 1;
end;

function TExtChild.ProbeResult: Integer;
begin
  Result := MakeItem().Count;
  Result := Result + MakeItem.Count;
end;

function TExtChild.ProbeIndexer(const pIdx: Integer): string;
begin
  Result := FItems[pIdx].Text;
  FItems[pIdx].Count := 4;
end;

function TExtChild.ProbeCast(const pIdx: Integer): string;
begin
  Result := TExtOther(FObjs[pIdx]).Text;
  Result := Result + (FObjs[pIdx] as TExtOther).Text;
  if TExtItem(FObjs[pIdx]).Count > 0 then
    Result := '';
end;

function TExtChild.ProbeForIn: Integer;
var
  lItem: TExtItem;
begin
  Result := 0;
  for lItem in FItems do
    Result := Result + lItem.Count;
  for var lInl in FItems do
    Result := Result + lInl.Count;
end;

end.
