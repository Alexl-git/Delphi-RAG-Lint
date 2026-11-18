unit uFpsFrames;

{ v152 FPS: RefTypeRules.DescentOf on a class whose base TFrame is a library homonym.
  TAmbigFrame = class(TFrame): one TFrame descends TCustomFrame, the other does not, so the
  descent is not decidable (tdUnknown) and blocking-call-in-main-thread keeps the
  spelling verdict (fires). Controls: TSoleKidFrame (unique base, descends: tdYes, fires);
  TPlainKidFrame (unique base, provably not a frame or form: tdNo, quiet). }

interface

uses
  Winapi.Windows, System.SyncObjs, FpsVclForms;

type
  TAmbigFrame = class(TFrame)
    procedure Run;
  private
    FDone: TEvent;
  end;

  TSoleKidFrame = class(TSoleFrame)
    procedure Run;
  private
    FDone: TEvent;
  end;

  TPlainKidFrame = class(TPlainFrame)
    procedure Run;
  private
    FDone: TEvent;
  end;

implementation

{$R *.dfm}

procedure TAmbigFrame.Run;
begin
  FDone.WaitFor(INFINITE); // fires
end;

procedure TSoleKidFrame.Run;
begin
  FDone.WaitFor(INFINITE); // fires
end;

procedure TPlainKidFrame.Run;
begin
  FDone.WaitFor(INFINITE); // quiet
end;

end.