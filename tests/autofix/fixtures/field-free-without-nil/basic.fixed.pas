unit basic;

interface

uses
  System.SysUtils,
  System.Classes;

type
  TCacheOwner = class
  private
    FCache: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
  end;

implementation

constructor TCacheOwner.Create;
begin
  inherited Create;
  FCache:= TStringList.Create;
end;

destructor TCacheOwner.Destroy;
begin
  FCache.Free;
  inherited Destroy;
end;

procedure TCacheOwner.Reset;
begin
  FreeAndNil(FCache);
end;

end.
