unit uRtUse;

interface

uses
  uRtBase;

procedure IsTests(ALeaf: TRtLeaf; ABase: TRtBase; const AObj: TObject);
procedure CastTests(ALeaf: TRtLeaf; ABase: TRtBase);
procedure WithTests(ALeaf: TRtLeaf; AOwner: TComponent);
procedure HolderTests(AComp: TRtCompThing; ACounted: TRtCountedThing; ARef: TRtRefThing);
procedure NarrowTests(AWide: Int64; AKey: TRtKey2; ASmall: Integer; ADouble: Double);
procedure RedundantTests(ALeaf: TRtLeaf; ABase: TRtBase);
procedure RedundantShadow;
procedure RedundantVarParam(Sender: TObject; var ALibProps: TcxLibProps; var ALeaf2: TdlgLocal);
procedure RedundantUntypedVar(var ALeaf);
procedure UnsafeTests(ALeaf: TRtLeaf; ABase: TRtBase);

implementation

procedure UnsafeTests(ALeaf: TRtLeaf; ABase: TRtBase);
var
  Sink: Integer;
begin
  Sink:= TRtMid(ALeaf.Base).Tag;  // TRIGGER-UNSAFE-CHAIN
  Sink:= TRtMid(MakeBase).Tag;  // TRIGGER-UNSAFE-RESULT
  Sink:= TRtMid(ABase).Tag;  // TRIGGER-UNSAFE-LEXICAL
  Sink:= TRtBase(ALeaf).Tag;  // CONTROL-UNSAFE-LEXICALUP
  Sink:= TRtBase(ALeaf.Link).Tag + Sink;  // CONTROL-UNSAFE-CHAINUP
  if ALeaf.Link.Base is TRtMid then
    Sink:= TRtMid(ALeaf.Link.Base).Tag;  // CONTROL-UNSAFE-GUARDED
end;

procedure RedundantTests(ALeaf: TRtLeaf; ABase: TRtBase);
var
  Sink: Integer;
  GShadow: TRtLeaf;
begin
  Sink:= TRtLeaf(ALeaf).Tag;  // TRIGGER-REDUNDANT-LEXICAL
  Sink:= TRtLeaf(ALeaf.Link).Tag;  // TRIGGER-REDUNDANT-CHAIN
  Sink:= TRtLeaf(MakeLeaf).Tag;  // TRIGGER-REDUNDANT-RESULT
  Sink:= (ALeaf as TRtLeaf).Tag;  // TRIGGER-REDUNDANT-AS
  Sink:= TRtLeaf(ALeaf.Base).Tag;  // CONTROL-REDUNDANT-CHAINDOWN // TRIGGER-UNSAFE-DOWN
  Sink:= (ABase as TRtLeaf).Tag;  // CONTROL-REDUNDANT-ASDOWN
  Sink:= TRtBase(ALeaf.Link).Tag;  // CONTROL-REDUNDANT-UP
  GShadow:= ALeaf;
  Sink:= GShadow.Tag;
end;

procedure RedundantShadow;
var
  Sink: Integer;
begin
  Sink:= TRtLeaf(GShadow).Tag;  // CONTROL-REDUNDANT-SHADOW // TRIGGER-UNSAFE-SHADOW
  Sink:= Sink + 1;
end;

{ E-CAST (OperatorList.pas:380): the miss was never the var parameter; the callee's second letter is lower case, the
  shape of every DevExpress type and of this project's dialogs. TcxLibProps is declared nowhere, as a library type is
  not in a project index. }
procedure RedundantVarParam(Sender: TObject; var ALibProps: TcxLibProps; var ALeaf2: TdlgLocal);
begin
  if ALibProps is TcxLibProps then TcxLibProps(ALibProps).Tag:= 1;  // TRIGGER-REDUNDANT-LOWERLIB
  TdlgLocal(ALeaf2).Tag:= 1;  // TRIGGER-REDUNDANT-LOWERLOCAL
  Trim(ALeaf2);  // CONTROL-REDUNDANT-LOWERCALL
end;

{ An untyped parameter has no type: the name in another routine's parameter list says nothing about this one. }
procedure RedundantUntypedVar(var ALeaf);
begin
  TRtLeaf(ALeaf).Tag:= 1;  // CONTROL-REDUNDANT-UNTYPEDVAR
end;

procedure NarrowTests(AWide: Int64; AKey: TRtKey2; ASmall: Integer; ADouble: Double);
const
  CFit = Int64(5);
var
  Narrow: Integer;
begin
  TakeInt(AWide);  // TRIGGER-NARROW-VARIABLE
  TakeInt(AKey);  // TRIGGER-NARROW-ALIAS
  TakeInt(WideResult);  // TRIGGER-NARROW-RESULT
  TakeTwo(AWide, ASmall);  // TRIGGER-NARROW-SECOND
  TakeSingle(ADouble);  // TRIGGER-NARROW-FLOAT
  TakeInt(ASmall);  // CONTROL-NARROW-SAME
  TakeTwo(ASmall);  // CONTROL-NARROW-WIDENS
  TakeVar(Narrow);  // CONTROL-NARROW-VAR
  TakeOver(AWide);  // CONTROL-NARROW-OVERLOAD
  TakeInt(CFit);  // CONTROL-NARROW-CONST
  TakeInt(Integer(AWide));  // CONTROL-NARROW-EXPLICIT
  TakeInt(AWide div 2);  // CONTROL-NARROW-EXPRESSION
end;

procedure HolderTests(AComp: TRtCompThing; ACounted: TRtCountedThing; ARef: TRtRefThing);
var
  Thing: IRtThing;
  Obj  : TRtComp;
begin
  Thing:= AComp;  // TRIGGER-HOLDER-VARIABLE
  Thing:= AComp as IRtThing;  // TRIGGER-HOLDER-AS
  Thing:= TRtCompThing.Create(nil);  // TRIGGER-HOLDER-CTOR
  Thing:= ACounted;  // CONTROL-HOLDER-OWNCOUNT
  Thing:= ARef;  // CONTROL-HOLDER-COUNTED
  Obj:= AComp;  // CONTROL-HOLDER-OBJECTVAR
  Thing:= Thing;  // CONTROL-HOLDER-SAME
end;

procedure WithTests(ALeaf: TRtLeaf; AOwner: TComponent);
begin
  with TRtPlain.Create do  // TRIGGER-WITH-CTOR
    Tag:= 1;
  with TRtPlain.Create(7) do  // TRIGGER-WITH-CTORARGS
    Tag:= 1;
  with TRtComp.Create(nil) do  // TRIGGER-WITH-NILOWNER
    Tag:= 1;
  with TRtPlain.Create do  // CONTROL-WITH-FREED
    try
      Tag:= 1;
    finally
      Free;
    end;
  with TRtComp.Create(AOwner) do  // CONTROL-WITH-OWNER
    Tag:= 1;
  with TRtWorker.Create(False) do  // CONTROL-WITH-THREAD
    Tag:= 1;
  with MakeLeaf do  // CONTROL-WITH-RESULT
    Tag:= 1;
  with ALeaf do  // CONTROL-WITH-VARIABLE
    Tag:= 1;
end;

procedure CastTests(ALeaf: TRtLeaf; ABase: TRtBase);
var
  Sink: Integer;
begin
  Sink:= TRtLeaf(TRtBase(ALeaf)).Tag;  // TRIGGER-UPDOWN-CALL
  Sink:= ((ALeaf as TRtBase) as TRtMid).Tag;  // TRIGGER-UPDOWN-AS
  Sink:= TRtMid(TObject(ALeaf)).Tag;  // TRIGGER-UPDOWN-OBJECT
  Sink:= TRtLeaf(ABase).Tag;  // CONTROL-UPDOWN-ONECAST
  Sink:= TRtLeaf(TRtMid(ABase)).Tag;  // CONTROL-UPDOWN-INNERNARROWS // TRIGGER-UNSAFE-INNER
  Sink:= TRtBase(TRtMid(ALeaf)).Tag + Sink;  // CONTROL-UPDOWN-BOTHUP
end;

procedure NeverTests(ALeaf: TRtLeaf; ABase: TRtBase; AOther: TRtOther; ASealed: TRtSealed; AFaced: TRtFaced;
  AOpen: TRtOpen; AFace: IRtFace; AUnf: TRtUnfollowed);
var
  Holder: TRtLeaf;
begin
  Holder:= ALeaf;
  if ALeaf is TRtOther then Exit;  // TRIGGER-NEVER-SIBLING
  if AOther is TRtBase then Exit;  // TRIGGER-NEVER-SIBLINGREV
  if Holder.Link is TRtOther then Exit;  // TRIGGER-NEVER-CHAIN
  if ASealed is IRtFace then Exit;  // TRIGGER-NEVER-SEALEDINTF
  if AFace is TRtSealed then Exit;  // TRIGGER-NEVER-INTFSEALED
  if ABase is TRtLeaf then Exit;  // CONTROL-NEVER-DOWN
  if AOpen is IRtFace then Exit;  // CONTROL-NEVER-OPENINTF
  if AFaced is IRtFace then Exit;  // CONTROL-NEVER-IMPLEMENTS
  if AFace is TRtOpen then Exit;  // CONTROL-NEVER-INTFOPEN
  if AFace is TRtFaced then Exit;  // CONTROL-NEVER-INTFIMPLEMENTS
  if AFace is IRtOther then Exit;  // CONTROL-NEVER-INTFINTF
  if AUnf is TRtOther then Exit;  // CONTROL-NEVER-INCOMPLETE
end;

{ Micronite2027 sgSManager.pas:591 was the rule's only real finding and it was false: the name after
  `absolute` was emitted as a second local, so B read as a TRtOther. }
procedure NeverAbsolute;
var
  B: TRtBase;
  O: TRtOther absolute B;
begin
  if B is TRtLeaf then Exit;  // CONTROL-NEVER-ABSOLUTE
  O.Free;
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
