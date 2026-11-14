unit uRttiGeneric;

{ Fixture of run_v151_RTTI2_generic.ps1: RTTI and classic streaming of generic types.
  Every construct here compiles with dcc64 (Delphi 13); lines tagged EXPECT (sub-kind, severity)
  must fire, lines tagged CONTROL must stay silent, lines tagged LIBONLY fire only with the library index. }

interface

uses
  System.Classes
  , System.SysUtils
  , System.Generics.Collections
  , uLibGeneric
  ;

type
  TGenEvent<T> = procedure(Sender: TObject; AValue: T) of object;

  TPersistentList<T> = class(TPersistent)
  private
    FCount: Integer;
  published
    property Count: Integer read FCount write FCount;
  end;

  TCodes = class(TPersistent)
  private
    FList : TList<Integer>;
    FDict : TDictionary<string, Integer>;
    FArr  : TArray<Integer>;
    FProc : TProc<Integer>;
    FPred : TPredicate<string>;
    FOwned: TObjectList<TPersistent>;
    FEvt  : TGenEvent<Integer>;
    FPList: TPersistentList<Integer>;
    FPair : TLibPair<string, Integer>;
    FBag  : TLibBag<Integer>;
    FCount: Integer;
  protected
    procedure DefineProperties(Filer: TFiler); override;
  public
    procedure Visit<X>(const AValue: X); // CONTROL: a public generic method
  published
    procedure Apply<X>(const AValue: X); // EXPECT published-generic-method warning
    class procedure Make<X>; // EXPECT published-generic-method warning
    procedure Plain; // CONTROL
    function Items: TList<Integer>; // CONTROL: a generic result type, not a generic method
    property List: TList<Integer> read FList write FList; // EXPECT published-unstreamable-generic warning
    property Dict: TDictionary<string, Integer> read FDict write FDict; // EXPECT published-unstreamable-generic warning
    property Arr: TArray<Integer> read FArr write FArr; // EXPECT published-unstreamable-generic warning
    property Proc: TProc<Integer> read FProc write FProc; // EXPECT published-unstreamable-generic warning
    property Pred: TPredicate<string> read FPred write FPred; // EXPECT published-unstreamable-generic warning
    property Owned: TObjectList<TPersistent> read FOwned write FOwned; // EXPECT published-unstreamable-generic info
    property Evt: TGenEvent<Integer> read FEvt write FEvt; // CONTROL: a method pointer streams by name
    property PList: TPersistentList<Integer> read FPList write FPList; // CONTROL: a TPersistent generic class
    property Pair: TLibPair<string, Integer> read FPair write FPair; // LIBONLY published-record-property warning
    property Bag: TLibBag<Integer> read FBag write FBag; // LIBONLY published-unstreamable-generic warning
    property Count: Integer read FCount write FCount; // CONTROL
  end;

  TBox<T: record> = class(TPersistent)
  private
    FValue: T;
  published
    property Value: T read FValue write FValue; // EXPECT published-unstreamable-generic warning
  end;

  TAnyBox<T> = class(TPersistent)
  private
    FValue: T;
  published
    property Value: T read FValue write FValue; // CONTROL: depends on the instantiation
  end;

  TObjBox<T: class> = class(TPersistent)
  private
    FValue: T;
  published
    property Value: T read FValue write FValue; // CONTROL: a class-constrained parameter
  end;

implementation

procedure TCodes.DefineProperties(Filer: TFiler);
begin
  inherited;
  Filer.DefineProperty('Owned', nil, nil, False);
end;

procedure TCodes.Visit<X>(const AValue: X);
begin
end;

procedure TCodes.Apply<X>(const AValue: X);
begin
end;

class procedure TCodes.Make<X>;
begin
end;

procedure TCodes.Plain;
begin
end;

function TCodes.Items: TList<Integer>;
begin
  Result:= FList;
end;

end.
