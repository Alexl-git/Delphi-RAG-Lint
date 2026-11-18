unit fpProps;

interface

type
  TItem = class
  private
    FNumber: Integer;
  public
    procedure Show;
    property Number: Integer read FNumber write FNumber;
  end;

  TNamed = class
  private
    FName: string;
    procedure SetName(const pValue: string);
  public
    procedure Show;
    property Name: string read FName write SetName;
  end;

  TSelfProp = class
  private
    FNumber: Integer;
  public
    constructor Create;
    procedure Show;
    property Number: Integer read FNumber write FNumber;
  end;

  TSelfSet = class
  private
    FName: string;
    procedure SetName(const pValue: string);
  public
    constructor Create;
    procedure Show;
    property Name: string read FName write SetName;
  end;

  TCondSet = class
  private
    FName: string;
    procedure SetName(const pValue: string);
  public
    constructor Create;
    procedure Show;
    property Name: string read FName write SetName;
  end;

  TUnwritten = class
  private
    FNever: Integer;
  public
    procedure Show;
    property Never: Integer read FNever write FNever;
  end;

  TSideHolder = class
  private
    FSide: string;
  public
    procedure Show;
    property Side: string read FSide write FSide;
  end;

  TReadOnly = class
  private
    FRo: Integer;
  public
    procedure Show;
    property Ro: Integer read FRo;
  end;

implementation

procedure TItem.Show;
begin
  Writeln(FNumber);    // USE-ITEM
end;

procedure TNamed.SetName(const pValue: string);
begin
  FName:= pValue;
end;

procedure TNamed.Show;
begin
  Writeln(FName);    // USE-NAMED
end;

constructor TSelfProp.Create;
begin
  inherited Create;
  Number:= 1;
end;

procedure TSelfProp.Show;
begin
  Writeln(FNumber);    // USE-SELFPROP
end;

procedure TSelfSet.SetName(const pValue: string);
begin
  FName:= pValue;
end;

constructor TSelfSet.Create;
begin
  inherited Create;
  Name:= 'x';
end;

procedure TSelfSet.Show;
begin
  Writeln(FName);    // USE-SELFSET
end;

procedure TCondSet.SetName(const pValue: string);
begin
  if pValue <> '' then
    FName:= pValue;
end;

constructor TCondSet.Create;
begin
  inherited Create;
  Name:= 'x';
end;

procedure TCondSet.Show;
begin
  Writeln(FName);    // USE-CONDSET
end;

procedure TUnwritten.Show;
begin
  Writeln(FNever);    // USE-UNWRITTEN
end;

procedure TSideHolder.Show;
begin
  Writeln(FSide);    // USE-SIDE
end;

procedure TReadOnly.Show;
begin
  Writeln(FRo);    // USE-READONLY
  Writeln(Ro);    // USE-READONLY-PROP
end;

end.