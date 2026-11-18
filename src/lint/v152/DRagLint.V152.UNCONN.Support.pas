unit DRagLint.V152.UNCONN.Support;

{ Wave v152 lane UNCONN -- helpers of DRagLint.V152.UNCONN (private to the lane).
  The .dfm and .pas models come from DRagLint.V151.DFMA.Support (LoadDfm /
  LoadPas); this unit adds only what the two rules need on top of them:
  * the default-event control table of ruling D12 and the "is this node wired
    in its own form file" test (event, Action, data binding, LiveBindings ...);
  * identifier counts over the raw unit text (the evidence when no index is
    available, and for FindComponent('Name') strings that no index records);
  * the by-name reference count across the project index. }

interface

uses
  System.Generics.Collections
  , DRagLint.Core.Interfaces
  , DRagLint.V151.DFMA.Support
  ;

type
  /// <summary>Lower-case identifier -> number of occurrences in one source text.</summary>
  /// <remarks>Counts every identifier-shaped token, including those inside string
  /// literals and comments: a name in `FindComponent('btnOk')` or in a comment counts
  /// as a use. Over-counting only silences a finding, never adds one.</remarks>
  TUcIdentCounts = TDictionary<string, Integer>;

/// <summary>True when AClass is a control class with a default event that ruling D12
/// reports (buttons, menu and toolbar items, check / radio boxes, edits, combos, lists).</summary>
/// <param name="AClass">The .dfm class name, e.g. TButton; compared case-insensitively.</param>
/// <returns>False for every passive class (labels, panels, bevels, layout items ...).</returns>
function UcIsDefaultEventClass(const AClass: string): Boolean;

/// <summary>True when node AIndex of ADfm is wired inside its own form file, or is a
/// variant that never acts on its own.</summary>
/// <param name="ADfm">The loaded form file.</param>
/// <param name="AIndex">Index of the node in ADfm.Nodes.</param>
/// <param name="ALines">The lines of the same .dfm (string values such as Caption are '' in the
/// node model, so a separator caption is read from its line); may be empty.</param>
/// <returns>True for: any On* event property; Action; DataSource / DataField / DataBinding.*;
/// ModalResult other than 0 / mrNone; a BitBtn Kind; a DropdownMenu / DropDownMenu / MenuItem;
/// a node with child nodes (a sub-menu); a separator menu item (Caption '-') or tool button
/// (Style tbsSeparator / tbsDivider); and a node named by another node's LiveBindings
/// property (Control, Component, SourceComponent, ControlComponent).</returns>
function UcNodeWiredInDfm(const ADfm: TDfmDoc; AIndex: Integer; const ALines: TArray<string>): Boolean;

/// <summary>Counts the identifier tokens of AText.</summary>
/// <param name="AText">Source text of a unit (any decoding that keeps ASCII intact).</param>
/// <returns>A new dictionary keyed by the lower-case identifier; the caller frees it.</returns>
function UcCountIdents(const AText: string): TUcIdentCounts;

/// <summary>Number of occurrences of AName in ACounts (0 when absent).</summary>
/// <param name="ACounts">Counts from UcCountIdents; must not be nil.</param>
/// <param name="AName">Identifier; compared case-insensitively.</param>
/// <returns>The count.</returns>
function UcIdentCount(const ACounts: TUcIdentCounts; const AName: string): Integer;

/// <summary>For each name, True when the project index holds at least one reference
/// whose name is that name, in any file and of any kind (code read, write, call,
/// member access, and the event-binding rows the indexer writes for .dfm On* lines).</summary>
/// <param name="AStore">Project index; must not be nil.</param>
/// <param name="ANames">Names to look up; one indexed query for all of them.</param>
/// <returns>One flag per name, same order.</returns>
/// <remarks>By name, not by resolved symbol: a homonym anywhere in the project counts as
/// a use. That keeps both rules on the silent side when resolution is incomplete.</remarks>
function UcNamesReferenced(const AStore: ISymbolStore; const ANames: TArray<string>): TArray<Boolean>;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Math
  , DRagLint.V151.Dfm.Common
  ;

const
  { Ruling D12: controls whose purpose is an event (their default event). Lower case. }
  DEFAULT_EVENT_CLASSES: array[0..45] of string = (
    'tbutton', 'tbitbtn', 'tspeedbutton', 'ttoolbutton', 'tmenuitem',
    'tcheckbox', 'tradiobutton', 'tradiogroup', 'tedit', 'tmaskedit',
    'tlabelededit', 'tbuttonededit', 'tmemo', 'trichedit', 'tcombobox',
    'tcomboboxex', 'tlistbox', 'tchecklistbox', 'tspinedit', 'ttrackbar',
    'tdatetimepicker', 'tupdown', 'tcxbutton', 'tcxcheckbox',
    'tcxradiobutton', 'tcxradiogroup', 'tcxtextedit', 'tcxmaskedit', 'tcxmemo',
    'tcxcombobox', 'tcxspinedit', 'tcxdateedit', 'tcxcurrencyedit', 'tcxcalcedit',
    'tcxbuttonedit', 'tcxlookupcombobox', 'tcxchecklistbox', 'tcxlistbox', 'tcxtrackbar',
    'tcxtimeedit', 'tcxcheckcombobox', 'tcxhyperlinkedit', 'tdxbarbutton', 'tdxbarlargebutton',
    'tdxbarcombo', 'tdxbaredit');

  { Properties of ANOTHER node that bind this control (LiveBindings links). Lower case. }
  BINDING_REF_PROPS: array[0..3] of string = ('control', 'component', 'sourcecomponent', 'controlcomponent');

  { Own properties that wire a control whatever their value. Lower case. }
  WIRING_PROPS: array[0..4] of string = ('action', 'datasource', 'datafield', 'dropdownmenu', 'menuitem');

function UcIsDefaultEventClass(const AClass: string): Boolean;
begin
  var L: string:= LowerCase(AClass);
  for var C in DEFAULT_EVENT_CLASSES do
    if C = L then Exit(True);
  Result:= False;
end;

/// True when the value of a ModalResult property means "closes the modal form".
function ModalResultActs(const AValue: string): Boolean;
begin
  var V: string:= Trim(AValue);
  Result:= (V <> '') and (V <> '0') and not SameText(V, 'mrNone');
end;

/// True when node N has a property that wires it (see UcNodeWiredInDfm).
/// True when the Caption property P of a node is the menu separator '-'; the node model
/// keeps string values as '', so the .dfm line itself is read.
function IsSeparatorCaption(const P: TDfmProp; const ALines: TArray<string>): Boolean;
begin
  Result:= InRange(P.Line, 1, Length(ALines)) and SameText(Trim(ALines[P.Line - 1]), 'Caption = ''-''');
end;

/// True when the one property P of node N wires the node (see UcNodeWiredInDfm).
function PropWires(const N: TDfmNode; const P: TDfmProp; const ALines: TArray<string>): Boolean;
begin
  var Name: string:= LowerCase(P.Name);
  var Last: string:= LowerCase(LastSegment(P.Name));
  var V   : string:= Trim(P.Value);
  if StartsStr('on', Last) and (Length(Last) > 2) then Exit(V <> '');
  if MatchStr(Name, WIRING_PROPS) or StartsStr('databinding.', Name) then Exit(True);
  if Name = 'modalresult' then Exit(ModalResultActs(V));
  if Name = 'kind' then Exit(SameText(N.CompClass, 'TBitBtn'));
  if Name = 'style' then Exit(SameText(V, 'tbsSeparator') or SameText(V, 'tbsDivider'));
  Result:= (Name = 'caption') and IsSeparatorCaption(P, ALines);
end;

/// True when node N has a property that wires it (see UcNodeWiredInDfm).
function OwnPropsWire(const N: TDfmNode; const ALines: TArray<string>): Boolean;
begin
  for var P in N.Props do
    if PropWires(N, P, ALines) then Exit(True);
  Result:= False;
end;

function UcNodeWiredInDfm(const ADfm: TDfmDoc; AIndex: Integer; const ALines: TArray<string>): Boolean;
begin
  var N: TDfmNode:= ADfm.Nodes[AIndex];
  if OwnPropsWire(N, ALines) then Exit(True);
  for var I: Integer:= 0 to High(ADfm.Nodes) do
  begin
    if ADfm.Nodes[I].Parent = AIndex then Exit(True);  // a sub-menu / container item
    if I = AIndex then Continue;
    for var P in ADfm.Nodes[I].Props do
      for var B in BINDING_REF_PROPS do
        if SameText(LastSegment(P.Name), B) and SameText(Trim(P.Value), N.Name) then Exit(True);
  end;
  Result:= False;
end;

/// True for A-Z, a-z, 0-9 and underscore.
function IsIdentChar(C: Char): Boolean;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function UcCountIdents(const AText: string): TUcIdentCounts;
begin
  Result:= TUcIdentCounts.Create;
  var I: Integer:= 1;
  var Len: Integer:= Length(AText);
  while I <= Len do
  begin
    if IsIdentChar(AText[I]) and not CharInSet(AText[I], ['0'..'9']) then
    begin
      var S: Integer:= I;
      while (I <= Len) and IsIdentChar(AText[I]) do Inc(I);
      var Key: string:= LowerCase(Copy(AText, S, I - S));
      var N: Integer;
      if Result.TryGetValue(Key, N) then Result[Key]:= N + 1
      else Result.Add(Key, 1);
    end
    else if CharInSet(AText[I], ['0'..'9']) then
    begin
      while (I <= Len) and IsIdentChar(AText[I]) do Inc(I);  // a number with a suffix is not an identifier
    end
    else Inc(I);
  end;
end;

function UcIdentCount(const ACounts: TUcIdentCounts; const AName: string): Integer;
begin
  if not ACounts.TryGetValue(LowerCase(AName), Result) then Result:= 0;
end;

function UcNamesReferenced(const AStore: ISymbolStore; const ANames: TArray<string>): TArray<Boolean>;
begin
  SetLength(Result, Length(ANames));
  if Length(ANames) = 0 then Exit;
  var Counts: TArray<Integer>:= AStore.CountCallerSitesByNames(ANames);
  for var I: Integer:= 0 to High(ANames) do
    Result[I]:= (I <= High(Counts)) and (Counts[I] > 0);
end;

end.
