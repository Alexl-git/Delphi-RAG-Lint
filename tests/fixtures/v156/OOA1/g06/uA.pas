unit uA;

interface

type
  TWidget = class
    procedure Show;
  end;
  TAlias = Integer;

function Normalize(const S: string): string;
procedure Both(I: Integer); overload;

implementation

procedure TWidget.Show;
begin
end;

function Normalize(const S: string): string;
begin
  Result := Trim(S);
end;

procedure Both(I: Integer);
begin
end;

end.