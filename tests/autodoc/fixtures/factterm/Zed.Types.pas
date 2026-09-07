unit Zed.Types;

// FIXTURE for run_doc_fact_terminator.ps1. That runner's header records why
// each shape below is here; the rationale lives THERE and not next to the
// declarations, for two reasons that are both load-bearing:
//
//   1. A comment sitting immediately above a declaration is HARVESTED into a
//      <summary>. A declaration that has a summary never produces an EMPTY
//      fresh render, and the empty-render branch is exactly where the phantom
//      -block defect lives -- decl-adjacent comments MASK it. Measured: with
//      summaries the decayed blocks reap correctly and the guard goes green
//      against the unfixed engine.
//   2. Harvested prose that MENTIONS an inbound label is itself a defect under
//      test (D4). Keeping label text out of this unit leaves Echo.Client.Gamma
//      as the only place D4 can fire.
//
// So: do not add a comment directly above any declaration in this file, and do
// not write an inbound label's text anywhere in it.

interface

uses
  System.Generics.Collections;

type
  TOuter = class
    private
      type
        TInner = record
          Verdict: Integer;
        end;
    var
      FItems: TList<TInner>;
    public
      constructor Create;
      destructor Destroy; override;
      procedure Ping;
      function Pong: TInner;
  end;

  TRep = record
    Verdict: Integer;
  end;

  TMode = (mFast, mSlow);

  TWide = record
    Verdict: Integer;
  end;

function Probe(AMax: Integer = 3): TRep;
function Mode(AFlag: Boolean): TMode;
function Wide: TWide;

implementation

constructor TOuter.Create;
begin
  inherited Create;
  FItems := TList<TInner>.Create;
end;

destructor TOuter.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TOuter.Ping;
var
  R: TInner;
begin
  R.Verdict := 1;
  FItems.Add(R);
end;

function TOuter.Pong: TInner;
begin
  Result := FItems.Last;
end;

function Probe(AMax: Integer = 3): TRep;
begin
  Result.Verdict := AMax;
end;

function Mode(AFlag: Boolean): TMode;
begin
  if AFlag then Result := mFast else Result := mSlow;
end;

function Wide: TWide;
begin
  Result.Verdict := 0;
end;

end.
