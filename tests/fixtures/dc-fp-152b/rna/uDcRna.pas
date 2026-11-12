unit uDcRna;

{ wave 152b lane DC: read-never-assigned must count a field passed to an
  out / var formal of a PROCEDURAL-type callee (a parameter or a field whose
  type is `reference to function(out ..)` or `procedure(var ..) of object`)
  as a write. Markers: TRIGGER-* must fire, CONTROL-* must stay silent. }

interface

uses
  System.SysUtils;

type
  TFolderLoader = reference to function(out ABytes: TBytes; out ARows: Integer; out AErr: string): Boolean;
  TCounterProc = procedure(var ACount: Integer; AStep: Integer) of object;

  TBenchSession = class
  private
    FFolders: TBytes;       // CONTROL-OUTBYTES
    FFolderRows: Integer;   // CONTROL-OUTREF
    FHits: Integer;         // CONTROL-VAROBJ
    FStep: Integer;         // TRIGGER-VALUEARG
    FNever: Integer;        // TRIGGER-READONLY
    FCounter: TCounterProc;
  public
    function Load(ALoadFolders: TFolderLoader): Boolean;
    procedure Count;
    function Total: Integer;
  end;

implementation

function TBenchSession.Load(ALoadFolders: TFolderLoader): Boolean;
var
  Err: string;
begin
  Result := Assigned(ALoadFolders) and ALoadFolders(FFolders, FFolderRows, Err);
end;

procedure TBenchSession.Count;
begin
  if Assigned(FCounter) then
    FCounter(FHits, FStep);
end;

function TBenchSession.Total: Integer;
begin
  Result := FFolderRows + FHits + FStep + FNever + Length(FFolders);
end;

end.
