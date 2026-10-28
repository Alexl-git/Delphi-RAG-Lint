unit uGetterFx;

{ Fixture for the `property-getter-with-effect` project lint rule (backlog
  1.37.0 lane B-EFFECT; INBOX-lint-rules-from-new-facts-2026-09-23 rule 6).

  Reading a property should not change state. A read accessor METHOD with a
  PROVEN self-field (s) or global (g) write fires at the property
  declaration, unless it is a lazy initialiser or a memo: an `if` whose
  condition tests nil / Assigned or a name the getter itself assigns. The
  runner reads each line number from its PG-TRIGGER-n / PG-CONTROL-n marker. }

interface

uses
  System.Classes;

type
  TCounter = class
  private
    FHits  : Integer;
    FList  : TStringList;
    FLoaded: Boolean;
    FCache : Integer;
    FName  : string;
    function GetHits: Integer;
    function GetNext: Integer;
    function GetList: TStringList;
    function GetCache: Integer;
    function GetName: string;
    function GetGuess: string;
  public
    property Hits : Integer     read GetHits;              { PG-TRIGGER-1: s }
    property Next : Integer     read GetNext;              { PG-TRIGGER-2: g }
    property List : TStringList read GetList;              { PG-CONTROL-1: lazy init (nil test) }
    property Cache: Integer     read GetCache;             { PG-CONTROL-2: memo flag }
    property Name : string      read GetName write FName;  { PG-CONTROL-3: effect-free getter }
    property Guess: string      read GetGuess;             { PG-CONTROL-4: summary '?' only }
    property Raw  : Integer     read FHits;                { PG-CONTROL-5: field accessor }
  end;

var
  GSeq: Integer;

implementation

function TCounter.GetHits: Integer;
begin
  FHits:= FHits + 1;
  Result:= FHits;
end;

function TCounter.GetNext: Integer;
begin
  GSeq:= GSeq + 1;
  Result:= GSeq;
end;

function TCounter.GetList: TStringList;
begin
  if FList = nil then
    FList:= TStringList.Create;
  Result:= FList;
end;

function TCounter.GetCache: Integer;
begin
  if not FLoaded then
  begin
    FCache := 42;
    FLoaded:= True;
  end;
  Result:= FCache;
end;

function TCounter.GetName: string;
begin
  Result:= FName;
end;

function TCounter.GetGuess: string;
begin
  Result:= Trim(FName);
end;

end.
