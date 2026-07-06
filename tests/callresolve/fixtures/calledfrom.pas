unit calledfrom;

// D5 Task 7 fixture: TAlpha.Run and TBeta.Run share the name 'Run'. Three
// callers exercise the resolved Called-from:
//   CallsAlpha  -> FAlpha.Run  (FAlpha: TAlpha)  resolves certain to TAlpha.Run
//   CallsBeta   -> FBeta.Run   (FBeta: TBeta)    resolves certain to TBeta.Run
//   CallsUnknown-> U.Run        (U: untyped/unresolvable) -> no edge -> '?' bucket
// TAlpha.Run's Called-from must INCLUDE CallsAlpha (plain), EXCLUDE CallsBeta,
// and list CallsUnknown with a trailing '?' (name-match, receiver untypable).

interface

type
  TAlpha = class
    procedure Run;
  end;

  TBeta = class
    procedure Run;
  end;

  TDispatcher = class
  private
    FAlpha: TAlpha;
    FBeta : TBeta ;
  public
    procedure CallsAlpha;
    procedure CallsBeta;
    procedure CallsUnknown;
  end;

implementation

procedure TAlpha.Run;
begin
end;

procedure TBeta.Run;
begin
end;

procedure TDispatcher.CallsAlpha;
begin
  FAlpha.Run;          // field receiver TAlpha -> certain TAlpha.Run
end;

procedure TDispatcher.CallsBeta;
begin
  FBeta.Run;           // field receiver TBeta -> certain TBeta.Run
end;

procedure TDispatcher.CallsUnknown;
var
  U: IUnknownThing;
begin
  U.Run;               // receiver type IUnknownThing is undeclared -> no edge -> '?'
end;

end.
