unit uExtShapes;

interface

uses
  uExtDefs;

type
  TExtPoint = record
    PosX: Integer;
    PosY: Integer;
  end;

  TExtBox = record
    Origin: TExtPoint;
    Title: string;
  end;

  PExtBox = ^TExtBox;
  PExtLate = ^TExtLate;

  TExtLate = record
    Next: PExtLate;
    Mark: ^TExtPoint;
  end;

  IExtNamed = interface
    function GetTitle: string;
    property Title: string read GetTitle;
  end;

  TExtHolder = class(TExtItem)
  private
    FBox: TExtBox;
    FBoxes: array of TExtBox;
    FNamed: IExtNamed;
    FGrid: array of TExtItemArray;
    FPair: array[0..1] of TExtBox;
    FCount3: Integer;
    function GetCell(const pIdx: Integer): TExtItem;
    procedure SetCell(const pIdx: Integer; const pValue: TExtItem);
    function IsStored: Boolean;
  public
    procedure Run; override;
    function Shapes(const pIdx: Integer; pBox: PExtBox): Integer;
    property Cells[const pIdx: Integer]: TExtItem read GetCell write SetCell; default;
    property BoxTitle: string read FBox.Title write FBox.Title;
    property Kept: Integer read FCount3 write FCount3 stored IsStored default 0;
    property FirstTitle: string read FPair[0].Title;
    property OriginX: Integer read FBox.Origin.PosX;
  end;

const
  cExtBox: TExtBox = (Origin: (PosX: 1; PosY: 2); Title: 't');

function MakeHolder(const pSeed: Integer): TExtHolder;

implementation

function MakeHolder(const pSeed: Integer): TExtHolder;
begin
  Result := TExtHolder.Create;
  Result.FCount3 := pSeed;
end;

function TExtHolder.GetCell(const pIdx: Integer): TExtItem;
begin
  Result := FGrid[0][pIdx];
end;

procedure TExtHolder.SetCell(const pIdx: Integer; const pValue: TExtItem);
begin
  FGrid[0][pIdx] := pValue;
end;

function TExtHolder.IsStored: Boolean;
begin
  Result := FCount3 <> 0;
end;

procedure TExtHolder.Run;
begin
  inherited Count := 2;
  if inherited Count > 1 then
    inherited Text := 'x';
  inherited Run();
end;

function TExtHolder.Shapes(const pIdx: Integer; pBox: PExtBox): Integer;
var
  lObj: TObject;
  lItem: TExtItem;
begin
  Result := MakeHolder(1).Cells[0].Count;
  Result := Result + MakeHolder(2)[1].Count;
  Result := Result + FGrid[pIdx][0].Count;
  Result := Result + FBoxes[pIdx].Origin.PosX;
  Result := Result + pBox^.Origin.PosY;
  Result := Result + Self[pIdx].Count;
  lObj := Self;
  TExtHolder(lObj).FCount3 := 5;
  TExtItem(TExtHolder(lObj).Cells[0]).Count := 6;
  Result := Result + Length(TExtHolder(lObj).FNamed.Title);
  Result := Result + Length((lObj as TExtHolder).BoxTitle);
  with TExtHolder(lObj) do
    Result := Result + FCount3;
  for lItem in MakeHolder(3).FGrid[0] do
    Result := Result + lItem.Count;
  for lItem in TExtHolder(lObj).FGrid[0] do
    Inc(Result, lItem.Count);
  FBoxes[pIdx].Title := 'n';
  FBoxes[pIdx].Origin.PosX := 7;
end;

end.
