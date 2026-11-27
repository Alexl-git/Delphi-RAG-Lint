unit DRagLint.V156.DFMR.Support;

{ Wave v156 lane DFM-R -- helpers of DRagLint.V156.DFMR (G-35 dfm-god-handler, G-36 dfm-control-overlap).
  Pure functions over the form-file object tree of DRagLint.V151.DFMB.Support (TDfmModel / TDfmObj): no files,
  no stores, no configuration. Everything here is decided from the stored text of the form file only. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.V151.DFMB.Support
  , DRagLint.V151.Dfm.Common
  ;

type
  /// <summary>One event handler that is wired to many events of a form file.</summary>
  /// <remarks>Plain value; Obj is borrowed from the model that produced it (do not free).</remarks>
  TGodHandler = record
    /// <summary>Handler method name as first spelled in the form file.</summary>
    Handler: string;
    /// <summary>Number of event bindings that name this handler.</summary>
    Bindings: Integer;
    /// <summary>Number of different event names (OnClick, OnChange, ...) among the bindings.</summary>
    EventKinds: Integer;
    /// <summary>First binding: the component that holds it.</summary>
    Obj: TDfmObj;
    /// <summary>First binding: 1-based line of the event property.</summary>
    Line: Integer;
    /// <summary>First binding: 1-based column of the event property.</summary>
    Col: Integer;
  end;

  /// <summary>One control that covers a sibling that precedes it in the form file.</summary>
  /// <remarks>Plain value; Obj and Other are borrowed from the model that produced it (do not free).</remarks>
  TOverlap = record
    /// <summary>The later sibling (drawn on top).</summary>
    Obj: TDfmObj;
    /// <summary>The first earlier sibling it covers.</summary>
    Other: TDfmObj;
    /// <summary>How many earlier siblings Obj covers.</summary>
    Covered: Integer;
  end;

const
  /// <summary>Fewest event bindings of one handler that count as "many" when the project sets no threshold.</summary>
  DEFAULT_GOD_HANDLER_BINDINGS = 5;
  /// <summary>Two rectangles must share more than this many pixels in BOTH directions to count as covering each other.</summary>
  OVERLAP_TOLERANCE_PX = 1;

/// <summary>Reads one property of a form-file object as an integer.</summary>
/// <param name="AObj">Form-file object.</param>
/// <param name="AName">Property name.</param>
/// <param name="ADefault">Value when the property is not stored.</param>
/// <param name="AOk">False when the property is stored but is not a plain integer.</param>
/// <returns>The stored value, ADefault when absent.</returns>
function IntProp(const AObj: TDfmObj; const AName: string; ADefault: Integer; out AOk: Boolean): Integer;

/// <summary>Tells whether a stored property is an event binding and names the event.</summary>
/// <param name="AProp">One property of a form-file object.</param>
/// <param name="AEvent">The event name (the part after the last dot, e.g. OnClick); '' when not an event.</param>
/// <returns>True when the name is On + capital letter and the value is a bare method identifier.</returns>
function IsEventBinding(const AProp: TDfmProp; out AEvent: string): Boolean;

/// <summary>Finds the handlers that a form file wires to at least AThreshold events of at least two kinds.</summary>
/// <param name="AModel">Parsed form file.</param>
/// <param name="AThreshold">Fewest bindings that count (values below 2 are treated as 2).</param>
/// <returns>One entry per handler, in file order of its first binding.</returns>
/// <remarks>A handler shared by many controls for ONE event (every OnClick of a row of buttons, a Sender
/// dispatcher) is the common deliberate pattern and is not reported.</remarks>
function FindGodHandlers(const AModel: TDfmModel; AThreshold: Integer): TArray<TGodHandler>;

/// <summary>True when the class lays out its children itself or stacks them on purpose.</summary>
/// <param name="AClass">Class name of the parent.</param>
/// <returns>True for page controls, notebooks, card / grid / flow / stack panels, layout controls and tool bars.</returns>
function IsStackingParent(const AClass: string): Boolean;

/// <summary>True when the class is drawn behind other controls on purpose (bevel, shape, group box, panel, image).</summary>
/// <param name="AClass">Class name.</param>
/// <returns>True for a backdrop class.</returns>
function IsBackdropClass(const AClass: string): Boolean;

/// <summary>Gives the screen rectangle of a control whose position is fixed by its stored Left, Top, Width and Height.</summary>
/// <param name="AObj">Form-file object.</param>
/// <param name="ALeft">Left edge.</param>
/// <param name="ATop">Top edge.</param>
/// <param name="ARight">Right edge (exclusive).</param>
/// <param name="ABottom">Bottom edge (exclusive).</param>
/// <returns>False for a non-visual component, a hidden control, an aligned or anchored-to-stretch control, a
/// splitter, or a control without a stored Width and Height.</returns>
function FixedRect(const AObj: TDfmObj; out ALeft, ATop, ARight, ABottom: Integer): Boolean;

/// <summary>Finds the controls that cover an earlier visible sibling under the same parent.</summary>
/// <param name="AModel">Parsed form file.</param>
/// <returns>One entry per covering control, in file order.</returns>
/// <remarks>Silent under stacking parents, for a pair where a backdrop contains the other control, and for
/// overlaps of one pixel (border sharing).</remarks>
function FindOverlaps(const AModel: TDfmModel): TArray<TOverlap>;

implementation

uses
  System.StrUtils
  , System.Math
  , System.Character
  , DRagLint.V154.DFM.Support
  ;

type
  /// <summary>Running count of the bindings of one handler: the first binding plus the event kinds seen, '|'-delimited.</summary>
  TTally = record
    Head : TGodHandler;
    Kinds: string;
  end;

  /// <summary>Fixed rectangle of one sibling, edges exclusive on the right and bottom.</summary>
  TBox = record
    Obj: TDfmObj;
    L, T, R, B: Integer;
  end;

function IntProp(const AObj: TDfmObj; const AName: string; ADefault: Integer; out AOk: Boolean): Integer;
begin
  AOk:= True;
  if not AObj.Has(AName) then Exit(ADefault);
  AOk:= TryStrToInt(Trim(AObj.Val(AName)), Result);
  if not AOk then Result:= ADefault;
end;

function IsIdent(const AText: string): Boolean;
begin
  Result:= AText <> '';
  if not Result then Exit;
  if not (AText[1].IsLetter or (AText[1] = '_')) then Exit(False);
  for var C: Char in AText do
    if not (C.IsLetterOrDigit or (C = '_')) then Exit(False);
end;

function IsEventName(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 2) and AName.StartsWith('On') and AName[3].IsUpper;
end;

function IsEventBinding(const AProp: TDfmProp; out AEvent: string): Boolean;
begin
  AEvent:= AProp.Name;
  var Dot: Integer:= LastDelimiter('.', AEvent);
  if Dot > 0 then AEvent:= Copy(AEvent, Dot + 1, MaxInt);
  var Value: string:= Trim(AProp.Value);
  Result:= IsEventName(AEvent) and IsIdent(Value) and not MatchText(Value, ['True', 'False', 'nil']);
  if not Result then AEvent:= '';
end;

function FindGodHandlers(const AModel: TDfmModel; AThreshold: Integer): TArray<TGodHandler>;
begin
  var Floor: Integer:= Max(AThreshold, 2);
  var Tally: TDictionary<string, TTally>:= TDictionary<string, TTally>.Create;
  var Order: TList<string>:= TList<string>.Create;
  var Found: TList<TGodHandler>:= TList<TGodHandler>.Create;
  try
    for var O: TDfmObj in AModel.All do
      for var P: TDfmProp in O.Props do
      begin
        var Event: string;
        if not IsEventBinding(P, Event) then Continue;
        var Key: string:= LowerCase(Trim(P.Value));
        var T: TTally;
        if Tally.TryGetValue(Key, T) then
        begin
          Inc(T.Head.Bindings);
          if not T.Kinds.Contains('|' + Event + '|') then T.Kinds:= T.Kinds + Event + '|';
        end
        else
        begin
          T:= Default(TTally);
          T.Head.Handler  := Trim(P.Value);
          T.Head.Bindings := 1;
          T.Head.Obj      := O;
          T.Head.Line     := P.Line;
          T.Head.Col      := P.Col;
          T.Kinds         := '|' + Event + '|';
          Order.Add(Key);
        end;
        Tally.AddOrSetValue(Key, T);
      end;
    for var Key: string in Order do
    begin
      var T: TTally:= Tally[Key];
      T.Head.EventKinds:= Length(T.Kinds.Split(['|'], TStringSplitOptions.ExcludeEmpty));
      if (T.Head.Bindings >= Floor) and (T.Head.EventKinds >= 2) then Found.Add(T.Head);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Order.Free;
    Tally.Free;
  end;
end;
function IsStackingParent(const AClass: string): Boolean;
begin
  var Leaf: string:= ClassLeaf(AClass);
  Result:= False;
  for var Part: string in ['PageControl', 'Notebook', 'CardPanel', 'GridPanel', 'FlowPanel', 'StackPanel',
    'RelativePanel', 'Layout', 'PageList', 'TabControl', 'ToolBar', 'ControlBar', 'Wizard', 'DockSite', 'Splitter'] do
    if ContainsText(Leaf, Part) then Exit(True);
end;

function IsBackdropClass(const AClass: string): Boolean;
begin
  var Leaf: string:= ClassLeaf(AClass);
  Result:= False;
  for var Part: string in ['Bevel', 'Shape', 'GroupBox', 'Panel', 'Box', 'Image', 'PaintBox', 'Frame'] do
    if ContainsText(Leaf, Part) then Exit(True);
end;

function IsPositionedByStoredRect(const AObj: TDfmObj): Boolean;
begin
  var Align: string:= Trim(AObj.Val('Align'));
  var Anchors: string:= AObj.Val('Anchors');
  var Stretches: Boolean:= ContainsText(Anchors, 'akRight') or ContainsText(Anchors, 'akBottom');
  var Aligned: Boolean:= (Align <> '') and not SameText(Align, 'alNone');
  var Shown: Boolean:= not BoolPropIs(AObj, 'Visible', False);
  var HasSize: Boolean:= AObj.Has('Width') and AObj.Has('Height');
  var IsSplitter: Boolean:= ContainsText(ClassLeaf(AObj.ClsName), 'Splitter');
  Result:= HasSize and Shown and not Aligned and not Stretches and not IsSplitter;
end;

function FixedRect(const AObj: TDfmObj; out ALeft, ATop, ARight, ABottom: Integer): Boolean;
begin
  ALeft:= 0;
  ATop:= 0;
  ARight:= 0;
  ABottom:= 0;
  Result:= IsPositionedByStoredRect(AObj);
  if not Result then Exit;
  var OkL, OkT, OkW, OkH: Boolean;
  ALeft:= IntProp(AObj, 'Left', 0, OkL);
  ATop := IntProp(AObj, 'Top', 0, OkT);
  var W: Integer:= IntProp(AObj, 'Width', 0, OkW);
  var H: Integer:= IntProp(AObj, 'Height', 0, OkH);
  Result:= OkL and OkT and OkW and OkH;
  Result:= Result and (W > 0) and (H > 0);
  if Result then
  begin
    ARight := ALeft + W;
    ABottom:= ATop + H;
  end;
end;
function Contains(const AOuter, AInner: TBox): Boolean;
begin
  Result:= (AOuter.L <= AInner.L) and (AOuter.T <= AInner.T) and (AOuter.R >= AInner.R) and (AOuter.B >= AInner.B);
end;

function Covers(const A, B: TBox): Boolean;
begin
  Result:= (Min(A.R, B.R) - Max(A.L, B.L) > OVERLAP_TOLERANCE_PX) and (Min(A.B, B.B) - Max(A.T, B.T) > OVERLAP_TOLERANCE_PX);
  if not Result then Exit;
  if Contains(A, B) and IsBackdropClass(A.Obj.ClsName) then Exit(False);
  if Contains(B, A) and IsBackdropClass(B.Obj.ClsName) then Exit(False);
end;

function FindOverlaps(const AModel: TDfmModel): TArray<TOverlap>;
begin
  var Found: TList<TOverlap>:= TList<TOverlap>.Create;
  try
    for var Parent: TDfmObj in AModel.All do
    begin
      if IsStackingParent(Parent.ClsName) then Continue;
      var Boxes: TList<TBox>:= TList<TBox>.Create;
      try
        for var K: TDfmObj in Parent.Kids do
        begin
          var X: TBox:= Default(TBox);
          X.Obj:= K;
          if FixedRect(K, X.L, X.T, X.R, X.B) then Boxes.Add(X);
        end;
        for var I: Integer:= 1 to Boxes.Count - 1 do
        begin
          var Hit: TOverlap:= Default(TOverlap);
          for var J: Integer:= 0 to I - 1 do
            if Covers(Boxes[I], Boxes[J]) then
            begin
              if Hit.Covered = 0 then
              begin
                Hit.Obj  := Boxes[I].Obj;
                Hit.Other:= Boxes[J].Obj;
              end;
              Inc(Hit.Covered);
            end;
          if Hit.Covered > 0 then Found.Add(Hit);
        end;
      finally
        Boxes.Free;
      end;
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

end.
