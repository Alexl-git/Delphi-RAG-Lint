unit uTtThreads;

{ Fixture of ui-access-in-thread-typed: Execute of a TThread descendant, direct and two
  levels down. A TRIGGER line fires, a CONTROL line stays silent, and nothing else fires. }

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, uTtForm;

type
  TTtHolder = class
  public
    Caption: string;
    procedure Hide;
  end;

  TTtWorker = class(TThread)
  public
    FForm: TTtForm;
    FLabel: TLabel;
    FObj: TObject;
    FRect: TFmxRect;
    FLst: TStringList;
    FStrings: TStrings;
    FBmp: TBitmap;
    FCanvas: TCanvas;
    FHolder: TTtHolder;
    FHom: THomonym;
    FLabels: array[0..1] of TLabel;
  protected
    procedure Execute; override;
    procedure Relay;
    procedure Calc;
  end;

  TTtDeep = class(TTtWorker)
  protected
    procedure Execute; override;
  end;

  TTtNotAThread = class
  public
    FLabel: TLabel;
    procedure Execute;
  end;

implementation

procedure TTtHolder.Hide;
begin
end;

procedure TTtWorker.Relay;
begin
  FForm.TouchUi;
end;

procedure TTtWorker.Calc;
begin
  FLst.Add('x');
end;

procedure TTtWorker.Execute;
var
  P: TProc;
begin
  FForm.Label1.Caption := 'write'; // TRIGGER-UIT-WRITE
  if FForm.Label1.Visible then Terminate; // TRIGGER-UIT-READ
  FLabel.Repaint; // TRIGGER-UIT-CALL
  TLabel(FObj).Hide; // TRIGGER-UIT-CAST
  (FObj as TLabel).Hide; // TRIGGER-UIT-AS
  Application.ProcessMessages; // TRIGGER-UIT-APPLICATION
  Screen.Cursor := 1; // TRIGGER-UIT-SCREEN
  FRect.Position := 1; // TRIGGER-UIT-FMX
  FForm.Close; // TRIGGER-UIT-FORM-CALL
  FLabel := TLabel.Create(nil); // TRIGGER-UIT-CONTROL-CREATE
  FForm.TouchUi; // TRIGGER-UIT-HOP-1
  Relay; // TRIGGER-UIT-HOP-2

  FForm.FCount := 1; // CONTROL-UIT-PLAIN-FIELD-OF-FORM
  FForm.Pure; // CONTROL-UIT-HOP-PURE
  FForm.Guarded; // CONTROL-UIT-HOP-GUARDED
  FForm.SelfMarshalled; // CONTROL-UIT-HOP-MARSHALLED
  Calc; // CONTROL-UIT-HOP-CALC
  FLst.Add('x'); // CONTROL-UIT-STRINGLIST
  FStrings.Clear; // CONTROL-UIT-STRINGS
  FBmp.Canvas.Lock; // CONTROL-UIT-BITMAP
  FCanvas.Lock; // CONTROL-UIT-CANVAS
  FHolder.Caption := 'x'; // CONTROL-UIT-HOLDER-CAPTION
  FHolder.Hide; // CONTROL-UIT-HOLDER-METHOD
  FHom.Caption := 'x'; // CONTROL-UIT-HOMONYM
  FLabel.Tag := 1; // CONTROL-UIT-TAG
  if FLabel.Name = '' then Terminate; // CONTROL-UIT-NAME
  if FLabel.ClassName = '' then Terminate; // CONTROL-UIT-CLASSNAME
  if Application.Terminated then Terminate; // CONTROL-UIT-APP-TERMINATED
  FLabels[0].Hide; // CONTROL-UIT-UNTYPED-SUBSCRIPT
  FObj.Hide; // CONTROL-UIT-UNTYPED-RECEIVER
  with FLabel do Hide; // CONTROL-UIT-WITH
  P := procedure
    begin
      FLabel.Hide; // CONTROL-UIT-STORED-LAMBDA
    end;
  Synchronize(
    procedure
    begin
      FLabel.Hide; // CONTROL-UIT-SYNCHRONIZE-LAMBDA
    end);
  Synchronize(FForm.TouchUi); // CONTROL-UIT-SYNCHRONIZE-NAMED
  Queue(nil, FForm.TouchUi); // CONTROL-UIT-QUEUE-NAMED-METHOD
  TThread.Queue(nil, FLabel.Hide); // CONTROL-UIT-THREAD-QUEUE
  TThread.ForceQueue(nil, FForm.TouchUi); // CONTROL-UIT-FORCEQUEUE
end;

procedure TTtDeep.Execute;
begin
  FLabel.Hide; // TRIGGER-UIT-DEEP-DESCENDANT
end;

procedure TTtNotAThread.Execute;
begin
  FLabel.Hide; // CONTROL-UIT-NOT-A-THREAD
end;

end.
