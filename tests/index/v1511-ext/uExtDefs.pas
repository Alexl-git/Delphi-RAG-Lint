unit uExtDefs;

interface

type
  TExtItem = class
  private
    FCount: Integer;
    FText: string;
    procedure SetCount(const pValue: Integer);
  public
    procedure Run; virtual;
    function Calc(const pA: Integer): Integer; virtual;
    property Count: Integer read FCount write SetCount;
    property Text: string read FText write FText;
  end;

  TExtOther = class
  private
    FText: string;
    FCount: Integer;
  public
    property Text: string read FText write FText;
    property Count: Integer read FCount;
  end;

  TExtRec = record
    Alpha: Integer;
    Beta: string;
  end;

  TExtItemArray = array of TExtItem;

function MakeItem: TExtItem;

implementation

function MakeItem: TExtItem;
begin
  Result := TExtItem.Create;
end;

procedure TExtItem.SetCount(const pValue: Integer);
begin
  FCount := pValue;
end;

procedure TExtItem.Run;
begin
  FCount := FCount + 1;
end;

function TExtItem.Calc(const pA: Integer): Integer;
begin
  Result := pA + FCount;
end;

end.
