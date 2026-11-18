unit PtwUse;

// Fixture of tests\autotest\run_v152_PTW.ps1 (lane v152 PTW, ruling B7).
// Every routine body below uses only pP.MidOp, so each could take TMid. A trailing marker says what the rule does:
//   FIRE <type>        the rule reports it and the autofix narrows it to <type>
//   SILENT <class>     a twin with the same body that the rule must skip; <class> is the skip class

interface

uses
  PtwLeaf;

type
  TLeafEvent = procedure(pP: TLeaf) of object;
  TLeafProc = procedure(pP: TLeaf);

  ILeafTaker = interface
    ['{4ED12AD3-E9AE-40E5-9D2C-F368CF7DA82C}']
    procedure Take(pP: TLeaf);
  end;

  THost = class
  private
    FOnLeaf: TLeafEvent;
  public
    procedure ViaMid(pP: TLeaf); // FIRE TMid
    procedure AsEvent(pP: TLeaf); // SILENT routine-as-value
    procedure Wire;
  end;

  TBaseHost = class
  public
    procedure Handle(pP: TLeaf); virtual; // SILENT virtual-routine
  end;

  TDerivedHost = class(TBaseHost)
  public
    procedure Handle(pP: TLeaf); override; // SILENT virtual-routine
  end;

  TTaker = class(TInterfacedObject, ILeafTaker)
  public
    procedure Take(pP: TLeaf); // SILENT implements-interface
  end;

procedure FreeMid(pP: TLeaf); // FIRE TMid
procedure FreeAsValue(pP: TLeaf); // SILENT routine-as-value
procedure RunAll;

implementation

procedure THost.ViaMid(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure THost.AsEvent(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure THost.Wire;
begin
  FOnLeaf:= AsEvent;
end;

procedure TBaseHost.Handle(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure TDerivedHost.Handle(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure TTaker.Take(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure FreeMid(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure FreeAsValue(pP: TLeaf);
begin
  pP.MidOp;
end;

procedure RunAll;
var
  Proc: TLeafProc;
begin
  Proc:= FreeAsValue;
  Proc(nil);
  FreeMid(nil);
end;

end.
