unit DestructorNotNilSafeFixture;

{ destructor-not-nil-safe: when a constructor raises, the destructor runs on a
  half-built object. A field created after a call that can raise (or only on some
  paths) may still be nil there. HIT lines must fire, OK lines must not. }

interface

uses
  System.Classes;

type
  TImporter = class
  private
    FStream: TFileStream;
    FLines : TStringList;
    FCache : TStringList;
    FLog   : TStringList;
    procedure Flush;
  public
    constructor Create(const AFile: string; AWithLog: Boolean);
    destructor Destroy; override;
  end;

  { every field created before anything can raise }
  TSafeHolder = class
  private
    FA: TStringList;
    FB: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

constructor TImporter.Create(const AFile: string; AWithLog: Boolean);
begin
  inherited Create;
  FCache:= TStringList.Create;
  FStream:= TFileStream.Create(AFile, fmOpenRead);
  FLines:= TStringList.Create;
  if AWithLog then
    FLog:= TStringList.Create;
end;

procedure TImporter.Flush;
begin
  FLines.SaveToFile('x.txt'); {HIT}
end;

destructor TImporter.Destroy;
begin
  Flush;
  FCache.Clear; {OK}
  FLines.Clear; {HIT}
  FLog.Clear; {HIT}
  if Assigned(FLines) then
    FLines.Clear; {OK}
  if (FLog <> nil) and (FLog.Count > 0) then FLog.Clear; {OK}
  FLines.Free; {OK}
  FLog.Free; {OK}
  FStream.Free; {OK}
  FCache.Free;
  inherited Destroy;
end;

constructor TSafeHolder.Create;
begin
  inherited Create;
  FA:= TStringList.Create;
  FB:= TStringList.Create;
end;

destructor TSafeHolder.Destroy;
begin
  FA.Clear; {OK}
  FB.Clear; {OK}
  FA.Free;
  FB.Free;
  inherited Destroy;
end;

end.
