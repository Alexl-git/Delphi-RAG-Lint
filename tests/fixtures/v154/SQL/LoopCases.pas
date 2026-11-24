unit LoopCases;
interface
uses SqlStubs;
type
  TRepo = class
  private
    FCache: TObject;
    function Cached(I: Integer): Integer;
    function Lookup(I: Integer): Integer;
    function Indirect(I: Integer): Integer;
    function Text(I: Integer): string;
    procedure TwoDown(I: Integer);
  public
    procedure Fires(Q, D: TFDQuery);
    procedure Silent(Q, D: TFDQuery; List: TArray<TFDQuery>; Mem: TFDMemTable; Names: TArray<string>);
  end;
implementation

function TRepo.Lookup(I: Integer): Integer;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT A FROM ORDERS WHERE ID = :ID';
  Q.ParamByName('ID').AsInteger := I;
  Q.Open;
  Result := Q.FieldByName('A').AsInteger;
end;

function TRepo.Cached(I: Integer): Integer;
var
  Q: TFDQuery;
begin
  if FCache.TryGetValue(I, Result) then Exit;
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT A FROM ORDERS WHERE ID = :ID';
  Q.ParamByName('ID').AsInteger := I;
  Q.Open;
end;

function TRepo.Indirect(I: Integer): Integer;
begin
  Result := Lookup(I) + 1;
end;

procedure TRepo.TwoDown(I: Integer);
begin
  Indirect(I);
end;

function TRepo.Text(I: Integer): string;
begin
  Result := 'SELECT A FROM ORDERS WHERE ID = 1';
end;

procedure TRepo.Fires(Q, D: TFDQuery);
var
  I: Integer;
begin
  while not Q.Eof do
  begin
    D.Close;
    D.Open; // FIRE query-in-loop
    Q.Next;
  end;
  for I := 0 to Q.Tag do
  begin
    D.ParamByName('A').AsInteger := I; // FIRE field-by-name-in-loop
    D.ExecSQL; // FIRE query-in-loop
    Lookup(I); // FIRE query-in-loop
    Indirect(I); // FIRE query-in-loop
    if I > 2 then D.Active := True; // FIRE query-in-loop
  end;
  repeat
    D.ExecSQL; // FIRE query-in-loop
    Q.Next;
  until Q.Eof;
end;

procedure TRepo.Silent(Q, D: TFDQuery; List: TArray<TFDQuery>; Mem: TFDMemTable; Names: TArray<string>);
var
  I: Integer;
begin
  for var DS in List do DS.Open;
  for I := 0 to High(List) do List[I].Open;
  for I := 1 to 3 do D.ExecSQL;
  for var S in ['A', 'B'] do D.ExecSQL;
  repeat
    try
      Q.Open;
      Break;
    except
      I := I + 1;
    end;
  until I > 3;
  while not Terminated do D.ExecSQL;
  while not Q.Eof do
  begin
    Mem.Open;
    Cached(I);
    Text(I);
    TwoDown(I);
    if not D.Active then D.Open;
    Q.Next;
  end;
  for I := 0 to High(Names) do
  begin
    D.SQL.Text := Names[I];
    D.ExecSQL;
  end;
  for I := 0 to High(Names) do
    if Names[I] = 'X' then
    begin
      D.Open;
      Exit;
    end;
  for I := 0 to High(Names) do
  begin
    D.DatabaseName := Names[I];
    D.Open;
  end;
  D.Open;
  for I := 0 to High(Names) do
    Later(procedure begin D.Open; end);
end;

end.