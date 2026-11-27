unit uB;

interface

type
  TWidget = class
    procedure Hide;
  end;
  TAlias = Integer;

function Normalize(const S: string): string;
procedure Both(S: string); overload;

implementation

procedure TWidget.Hide;
begin
end;

function Normalize(const S: string): string;
begin
  Result := UpperCase(S);
end;

procedure Both(S: string);
begin
end;

end.