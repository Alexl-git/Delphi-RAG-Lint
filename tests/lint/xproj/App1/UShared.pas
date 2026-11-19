unit UShared;

{ Compiled by App1 AND App2 (App2 lists ..\App1\UShared.pas). No dl:shared header on purpose:
  the cross-project answer must come from the peer index, not from a marker. }

interface

const
  UsedOnlyByApp2 = 2;
  UsedNowhere = 3;
  UsedByApp1 = 4;

type
  TChunkWriter = class
  public
    procedure WriteChunk(AValue: Integer);
    procedure OnlyLocal(AValue: Integer);
    procedure Flush;
  end;

implementation

var
  GTotal: Integer;

procedure TChunkWriter.WriteChunk(AValue: Integer);
begin
  GTotal:= GTotal + AValue;
end;

procedure TChunkWriter.OnlyLocal(AValue: Integer);
begin
  GTotal:= GTotal - AValue;
end;

procedure TChunkWriter.Flush;
begin
  WriteChunk(GTotal);
  OnlyLocal(GTotal);
end;

end.
