unit uOpaque;

{ Fixture for the opaque-to-analysis project rule. The expected verdicts are
  pinned by tests\autotest\run_opaque_to_analysis.ps1. }

interface

uses
  System.SysUtils, System.Classes;

type
  TCallback = procedure(AValue: Integer);

  TThing = class
  public
    procedure Alpha;
    procedure Beta;
  end;

  TWorker = class(TComponent)
  private
    FCb: TCallback;
    function Lookup(const AName: string): TObject;
    procedure Step1;
    procedure Step2;
    procedure Step3;
    procedure Step4;
    procedure Step5;
    procedure Step6;
  public
    procedure HitOpaque(ACb: TCallback);
    procedure HitAtThreshold(ACb: TCallback);
    procedure QuietJustBelowShare(ACb: TCallback);
    procedure QuietLibraryOnly(AStream: TStream; AWorker: TWorker);
    procedure QuietMostlyResolved(ACb: TCallback);
    procedure QuietTooFew(ACb: TCallback);
    procedure QuietAllResolved(AThing: TThing);
  end;

implementation

procedure TThing.Alpha;
begin
end;

procedure TThing.Beta;
begin
end;

function TWorker.Lookup(const AName: string): TObject;
begin
  Result:= nil;
end;

procedure TWorker.Step1;
begin
end;

procedure TWorker.Step2;
begin
end;

procedure TWorker.Step3;
begin
end;

procedure TWorker.Step4;
begin
end;

procedure TWorker.Step5;
begin
end;

procedure TWorker.Step6;
begin
end;

procedure TWorker.HitOpaque(ACb: TCallback);
begin
  ACb(1);
  FCb(2);
  ACb(3);
  FCb(4);
  ACb(5);
  FCb(6);
  Step1;
  Format('library calls stay out of the denominator');
end;

procedure TWorker.HitAtThreshold(ACb: TCallback);
begin
  ACb(1);
  ACb(2);
  ACb(3);
  Step1;
  Step2;
end;

procedure TWorker.QuietJustBelowShare(ACb: TCallback);
begin
  ACb(1);
  ACb(2);
  ACb(3);
  Step1;
  Step2;
  Step3;
end;

procedure TWorker.QuietLibraryOnly(AStream: TStream; AWorker: TWorker);
begin
  AStream.ReadBuf;
  AStream.WriteBuf;
  AStream.Seek;
  AStream.Flush;
  AStream.Reset;
  Loaded;
  Notify;
  Update;
  Refresh;
  AWorker.Update;
  AWorker.Refresh;
  Application.Notify;
  Application.Refresh;
  TThing(AWorker);
  TStream(AWorker);
  Format('a');
  Format('b');
  Exit;
end;

procedure TWorker.QuietMostlyResolved(ACb: TCallback);
begin
  ACb(1);
  ACb(2);
  ACb(3);
  Step1;
  Step2;
  Step3;
  Step4;
  Step5;
  Step6;
  Lookup('a');
  Lookup('b');
end;

procedure TWorker.QuietTooFew(ACb: TCallback);
begin
  ACb(1);
  ACb(2);
end;

procedure TWorker.QuietAllResolved(AThing: TThing);
begin
  AThing.Alpha;
  AThing.Beta;
  Step1;
  Step2;
end;

end.
