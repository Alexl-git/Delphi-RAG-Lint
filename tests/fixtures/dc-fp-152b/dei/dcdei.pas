unit dcdei;

{ wave 152b lane DC: default-encoding-io must match the callee by its NAME
  SEGMENTS, never by a substring: SetCurrentStreamWriter ends in
  "...tStreamWriter" but is a plain procedure. TRIGGER-* must fire,
  CONTROL-* must stay silent. }

interface

uses
  System.Classes, System.SysUtils;

procedure SetCurrentStreamWriter(AWriter: TObject);
procedure SetCurrentStreamReader(AReader: TObject);
procedure Run(const AFile: string; AList: TStringList);

implementation

threadvar
  GWriter: TObject;

procedure SetCurrentStreamWriter(AWriter: TObject);
begin
  GWriter := AWriter;
end;

procedure SetCurrentStreamReader(AReader: TObject);
begin
  GWriter := AReader;
end;

procedure Run(const AFile: string; AList: TStringList);
var
  W: TStreamWriter;
  R: TStreamReader;
begin
  SetCurrentStreamWriter(nil);                           // CONTROL-SETWRITER
  SetCurrentStreamReader(nil);                           // CONTROL-SETREADER
  W := TStreamWriter.Create(AFile);                      // TRIGGER-WRITER
  R := TStreamReader.Create(AFile);                      // TRIGGER-READER
  AList.LoadFromFile(AFile);                             // TRIGGER-LOAD
  W.Free;
  W := TStreamWriter.Create(AFile, False, TEncoding.UTF8); // CONTROL-ENCODED
  W.Free;
  R.Free;
end;

end.
