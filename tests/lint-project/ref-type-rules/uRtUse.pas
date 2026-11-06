unit uRtUse;

interface

uses
  uRtBase;

procedure IsTests(ALeaf: TRtLeaf; ABase: TRtBase; const AObj: TObject);
procedure CastTests(ALeaf: TRtLeaf; ABase: TRtBase);

implementation

procedure CastTests(ALeaf: TRtLeaf; ABase: TRtBase);
var
  Sink: Integer;
begin
  Sink:= TRtLeaf(TRtBase(ALeaf)).Tag;  // TRIGGER-UPDOWN-CALL
  Sink:= ((ALeaf as TRtBase) as TRtMid).Tag;  // TRIGGER-UPDOWN-AS
  Sink:= TRtMid(TObject(ALeaf)).Tag;  // TRIGGER-UPDOWN-OBJECT
  Sink:= TRtLeaf(ABase).Tag;  // CONTROL-UPDOWN-ONECAST
  Sink:= TRtLeaf(TRtMid(ABase)).Tag;  // CONTROL-UPDOWN-INNERNARROWS
  Sink:= TRtBase(TRtMid(ALeaf)).Tag + Sink;  // CONTROL-UPDOWN-BOTHUP
end;

procedure IsTests(ALeaf: TRtLeaf; ABase: TRtBase; const AObj: TObject);
var
  Holder: TRtLeaf;
  Items : array of TRtLeaf;
begin
  Holder:= ALeaf;
  if ALeaf is TRtLeaf then Exit;  // TRIGGER-ALWAYS-SAME
  if ALeaf is TRtBase then Exit;  // TRIGGER-ALWAYS-ANCESTOR
  if Holder.Link is TRtMid then Exit;  // TRIGGER-ALWAYS-CHAIN
  if MakeLeaf is TRtBase then Exit;  // TRIGGER-ALWAYS-RESULT
  if ALeaf is TObject then Exit;  // TRIGGER-ALWAYS-ROOT
  if ABase is TRtLeaf then Exit;  // CONTROL-ALWAYS-DOWN
  if AObj is TRtBase then Exit;  // CONTROL-ALWAYS-OBJECT
  if Holder.Base is TRtMid then Exit;  // CONTROL-ALWAYS-CHAINDOWN
  if MakeBase is TRtLeaf then Exit;  // CONTROL-ALWAYS-RESULTDOWN
  if Items[0] is TRtBase then Exit;  // CONTROL-ALWAYS-SUBSCRIPT
  with Holder do
    if Link is TRtBase then Exit;  // CONTROL-ALWAYS-WITH
end;

end.
