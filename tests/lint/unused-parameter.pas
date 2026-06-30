unit up;
interface
type
  TBase = class
    procedure Go(Used, Unused: Integer); virtual;
  end;
  TDer = class(TBase)
    procedure Go(Used, Unused: Integer); override;
  end;
procedure Plain(A, B: Integer);
implementation
procedure Plain(A, B: Integer); begin WriteLn(A); end;
procedure TBase.Go(Used, Unused: Integer); begin WriteLn(Used); end;
procedure TDer.Go(Used, Unused: Integer); begin WriteLn(Used); end;
end.
