unit uSealFwd;

interface

type
  IFwdFace = interface
    ['{3B6F1C2D-7E4A-4F10-9A2B-5C6D7E8F9A01}']
  end;

  TFwdSealed = class;
  TFwdOpen = class;

  TFwdUser = class
    FS: TFwdSealed;
    FO: TFwdOpen;
  end;

  TFwdSealed = class sealed
  end;

  TFwdOpen = class
  end;

procedure Probe(I: IFwdFace);

implementation

procedure Probe(I: IFwdFace);
begin
  if I is TFwdSealed then Exit;
  if I is uSealFwd.TFwdSealed then Exit;
  if I is TFwdOpen then Exit;
end;

end.
