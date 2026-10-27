unit dtor;

interface

uses
  System.Classes;

type
  TFixable = class
  private
    FX: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  System.SysUtils;

constructor TFixable.Create;
begin
  inherited Create;
  FX:= TStringList.Create;
end;

destructor TFixable.Destroy;
begin
  inherited Destroy;
end;

end.
