unit ElemTypes;

{ Fixture of tests\autotest\run_rename_element_type.ps1: the types whose fields are read through a subscript. }

interface

uses
  System.Generics.Collections, ElemGeneric;

type
  TTok = record
    Kind: Integer;
    Text: string;
    Hard: Integer;
  end;
  TTokList = TList<TTok>;

  TThing = class
  public
    Kind: Integer;
    Length: Integer;
    Tally: Integer;
    procedure Ping;
  end;

  TOtherRec = record
    Kind: Integer;
  end;

  THolder = class
  public
    FToks: TTokList;
    constructor Create;
    destructor Destroy; override;
    property Toks: TTokList read FToks;
  end;

  TBox<T: TThing> = class
  public
    FL: TList<T>;
    function First: Integer;
  end;

var
  GToks: TTokList;
  GDirect: TList<TTok>;
  GNested: TList<TArray<TTok>>;

function MakeTok(pKind: Integer): TTok;

implementation

function MakeTok(pKind: Integer): TTok;
begin
  Result:= Default(TTok);
  Result.Kind:= pKind;
  Result.Text:= 'tok';
  Result.Hard:= pKind + 1;
end;

procedure TThing.Ping;
begin
  Inc(Tally);
end;

constructor THolder.Create;
begin
  inherited Create;
  FToks:= TTokList.Create;
end;

destructor THolder.Destroy;
begin
  FToks.Free;
  inherited Destroy;
end;

function TBox<T>.First: Integer;
begin
  Result:= FL[0].Tally;
end;

end.