unit uPDefs;

interface

uses
  System.SysUtils, System.Classes;

type
  TPBinding = class
  public
    DataField: string;
  end;

  TPEdit = class
  private
    FBinding: TPBinding;
  public
    property DataBinding: TPBinding read FBinding;
  end;

  TPItem = class
  public
    Count: Integer;
    Text: string;
  end;

  TPHolder = class
  public
    class var Seed: Integer;
    class constructor Create;
    class destructor Destroy;
    constructor Create(pA: Integer); overload;
    destructor Destroy; override;
  end;

  TPFunc = reference to function(const pA: Integer; pB: string): Integer;
  TPProc = reference to procedure(pSender: TObject);

implementation

class constructor TPHolder.Create;
var
  lClassSeed: Integer;
begin
  lClassSeed := 1;
  Seed := lClassSeed;
end;

class destructor TPHolder.Destroy;
begin
  Seed := 0;
end;

constructor TPHolder.Create(pA: Integer);
var
  lInstSeed: Integer;
begin
  inherited Create;
  lInstSeed := pA;
  Seed := lInstSeed;
end;

destructor TPHolder.Destroy;
begin
  inherited;
end;

end.
