unit upo;
interface
type
  TBase = class
    procedure Go(Used, Unused: Integer); virtual;
  end;
  TDer = class(TBase)
    procedure Go(Used, Unused: Integer); override;
  end;
implementation
procedure TBase.Go(Used, Unused: Integer); begin WriteLn(Used); end;
procedure TDer.Go(Used, Unused: Integer); begin WriteLn(Used); end;
end.
