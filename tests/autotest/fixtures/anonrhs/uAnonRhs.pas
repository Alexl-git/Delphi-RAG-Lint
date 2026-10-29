unit uAnonRhs;

interface

uses
  System.SysUtils;

type
  TFeedProc = reference to procedure(const pText: string);
  TIntFunc = reference to function: Integer;

  THost = record
    FeedHarvest: TFeedProc;
    Counter: TIntFunc;
    Plain: Integer;
    FeedPaths: TProc<TArray<string>>;
  end;

procedure Wire(var pHost: THost);
procedure WireInline(var pHost: THost);

implementation

procedure Wire(var pHost: THost);
var
  LHost: THost;
begin
  LHost.FeedHarvest := procedure(const pText: string)
    begin
      if pText = '' then
        Exit;
    end;
  LHost.Counter := function: Integer
    begin
      Result := 1;
    end;
  LHost.Plain := 1;
  pHost := LHost;
end;

procedure WireInline(var pHost: THost);
begin
  var LHost: THost;
  LHost.FeedPaths:= procedure(APaths: TArray<string>)
    var
      LErrs: TArray<string>;
    begin
      LErrs:= APaths;
    end;
  LHost.Plain:= 2;
  pHost:= LHost;
end;

end.