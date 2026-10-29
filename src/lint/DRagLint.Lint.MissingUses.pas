unit DRagLint.Lint.MissingUses;

{ Rule unit-missing-from-uses: an identifier the index could not bind, that
  no declaration in scope explains, but that a unit the file does NOT use
  declares in its interface -- the IDE's "Undeclared identifier: 'CodeSite'"
  with the answer attached: "'CodeSite' is declared in unit CodeSiteLogging --
  add it to the implementation uses clause".

  The section is the interface when ANY such use of the name sits in the
  interface section, else the implementation. Adding the unit is then checked
  against the uses graph of the file's own index before it is offered: an
  interface edge that closes an interface-only cycle (E2047) is redirected to
  the implementation clause, and any other cycle the edge would close is
  named in the message as a warning.

  PRECISION FIRST. A name is reported only when every one of these holds:
  the index left the site unbound (refs.symbol_id NULL); it has no receiver
  (a member after a dot is never a candidate); the source still holds the name
  at the indexed position (a stale index answers nothing); no declaration of
  that name exists in this file (locals, fields, generic parameters...); no
  unit-level interface declaration of it lives in this unit, in System/SysInit
  or in any unit the text already uses; and at least one does live in some
  other unit. Inside a method body a name that is a member of ANY class is
  skipped (an inherited member the index could not see), and inside a routine
  holding a `with` a name that is a member of any type is skipped. Code in an
  inactive preprocessor branch has no refs, so it is never reported. Several
  candidate units are listed in the message and get no fix. }

interface

uses
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Core.UsesInsert;

const
  /// <summary>The rule id.</summary>
  MISSING_USES_RULE = 'unit-missing-from-uses';

type
  /// <summary>One offered edit for a unit-missing-from-uses finding.</summary>
  TMissingUsesFix = record
    /// <summary>The clause the edit extends or creates.</summary>
    Section  : TUsesSection;
    /// <summary>The text insertion (1-based position, CRLF text).</summary>
    Insertion: TUsesInsertion;
    /// <summary>Code-action title; names a cycle the edit would create.</summary>
    Title    : string;
    /// <summary>True for the edit the message recommends.</summary>
    Preferred: Boolean;
  end;

  /// <summary>A finding plus what is needed to fix it.</summary>
  TMissingUsesFinding = record
    /// <summary>The lint finding (rule, position, severity, message).</summary>
    Finding : TLintFinding;
    /// <summary>The unit to add; '' when several units declare the name.</summary>
    UnitName: string;
    /// <summary>The clause the message recommends.</summary>
    Section : TUsesSection;
    /// <summary>The offered edits, recommended first; empty for an ambiguous
    /// name or when the text has no clause to extend or create.</summary>
    Fixes   : TArray<TMissingUsesFix>;
  end;

  /// <summary>The unit-missing-from-uses checker.</summary>
  /// <remarks>Store-backed: reads the file's refs, symbols and uses from the
  /// store that indexes it, and looks the unresolved names up in every lookup
  /// store (the project index and the platform library). Read-only; never
  /// writes a store. Not thread-safe across calls sharing a store only in the
  /// sense ISymbolStore itself is not.</remarks>
  TMissingUsesChecker = class
  public
    /// <summary>The findings of AFile, each with its fixes.</summary>
    /// <param name="AFile">The text to check (the file, or a stand-in snapshot of it).</param>
    /// <param name="AFileStore">The store that indexes the file; nil -> no findings.</param>
    /// <param name="AFileId">The file's id in AFileStore; 0 -> no findings.</param>
    /// <param name="ALookup">Stores to look names up in; AFileStore is used
    /// when it is not among them. nil entries are ignored.</param>
    /// <returns>One finding per unresolved use, in ref order.</returns>
    class function Analyze(const AFile: string; const AFileStore: ISymbolStore; AFileId: Int64;
      const ALookup: TArray<ISymbolStore>): TArray<TMissingUsesFinding>; static;
    /// <summary>The plain findings of Analyze, for the lint verbs.</summary>
    /// <param name="AFile">As Analyze.</param>
    /// <param name="AFileStore">As Analyze.</param>
    /// <param name="AFileId">As Analyze.</param>
    /// <param name="ALookup">As Analyze.</param>
    /// <returns>The findings.</returns>
    class function Check(const AFile: string; const AFileStore: ISymbolStore; AFileId: Int64;
      const ALookup: TArray<ISymbolStore>): TArray<TLintFinding>; static;
    /// <summary>The uses cycle a new edge AFromUnit -> AToUnit would close.</summary>
    /// <param name="AStore">The store whose uses graph is walked (the file's own index).</param>
    /// <param name="AFromFid">The file id of AFromUnit in AStore.</param>
    /// <param name="AFromUnit">The unit gaining the edge.</param>
    /// <param name="AToUnit">The unit being added to its uses.</param>
    /// <param name="AInterfaceOnly">True to follow interface uses only (the
    /// cycles the compiler rejects with E2047).</param>
    /// <returns>'From -> To -> ... -> From', or '' when no path leads back
    /// (including when AToUnit is not indexed in AStore, e.g. a library unit).</returns>
    class function CyclePath(const AStore: ISymbolStore; AFromFid: Int64; const AFromUnit, AToUnit: string;
      AInterfaceOnly: Boolean): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  System.Math,
  DRagLint.Core.LiveDocs,
  DRagLint.Refactor.TextEdit,
  DRagLint.Lint.Autofix;

const
  MAX_LISTED_CANDIDATES = 5;
  MAX_CYCLE_VISITS      = 20000;
  MAX_NESTING           = 32; { routine nesting walked out of before giving up }

type
  TNameInfo = record
    InScope       : Boolean;
    Candidates    : TArray<string>;
    HasClassMember: Boolean;
    HasAnyMember  : Boolean;
  end;

  TOccurrence = record
    Ref      : TReference;
    Interface_: Boolean;
  end;

{ Names the compiler supplies without any declaration a library index holds. }
function IsIntrinsicName(const AName: string): Boolean;
begin
  Result:= MatchText(AName, ['Result', 'Self', 'Exit', 'Break', 'Continue', 'Halt', 'Inc', 'Dec',
    'Length', 'High', 'Low', 'SizeOf', 'Ord', 'Chr', 'Assigned', 'New', 'Dispose', 'SetLength',
    'Copy', 'Include', 'Exclude', 'Assert', 'TypeInfo', 'Default', 'Succ', 'Pred', 'Odd',
    'Hi', 'Lo', 'Abs', 'Round', 'Trunc', 'Ptr', 'Addr', 'Str', 'Val', 'Concat', 'Insert',
    'Delete', 'Initialize', 'Finalize', 'GetTypeKind', 'IsManagedType', 'HasWeakRef',
    'TypeOf', 'Swap', 'Slice', 'Inherited', 'True', 'False', 'nil', 'Write', 'Writeln',
    'Read', 'Readln', 'FillChar', 'Move', 'SetString', 'UniqueString', 'Name', 'Value', 'MaxInt',
    'MaxLongint',
    { built-in types and file routines the compiler supplies to System without a
      declaration the library index holds }
    'Pointer', 'Extended', 'LongWord', 'LongInt', 'Cardinal', 'Integer', 'Int64', 'UInt64', 'Byte',
    'Word', 'ShortInt', 'SmallInt', 'Boolean', 'ByteBool', 'WordBool', 'LongBool', 'Char',
    'AnsiChar', 'WideChar', 'string', 'AnsiString', 'WideString', 'UnicodeString', 'ShortString',
    'RawByteString', 'UTF8String', 'Single', 'Double', 'Real', 'Real48', 'Comp', 'Currency',
    'NativeInt', 'NativeUInt', 'Variant', 'OleVariant', 'PChar', 'PAnsiChar', 'PWideChar', 'Text',
    'TextFile', 'File', 'AssignFile', 'CloseFile', 'Assign', 'Close', 'Reset', 'Rewrite', 'Append',
    'Eof', 'Eoln', 'Seek', 'BlockRead', 'BlockWrite', 'FileSize', 'FilePos', 'Erase', 'Rename',
    'IOResult', 'Flush', 'Truncate', 'ParamStr', 'ParamCount', 'Random', 'Randomize', 'Exp', 'Ln',
    'Sqrt', 'Sqr', 'Sin', 'Cos', 'ArcTan', 'Frac', 'Int', 'Pi', 'UpCase', 'Pos', 'StringOfChar',
    'Fixed', 'Absolute']);
end;

{ Names the text itself declares where the index records no symbol -- anonymous
  method parameters, inline vars, labels: Left, Right: Integer. Any name
  written before a lone ':' (optionally in a comma list) counts. A case label
  of an enum value counts too, which only ever silences a finding. }
procedure AddTextDeclaredNames(const ALines: TArray<string>; ANames: TDictionary<string, Boolean>);
begin
  for var L: string in ALines do
  begin
    if not L.Contains(':') then Continue;
    var S: string:= TRegEx.Replace(L, '''[^'']*''', '''''');
    var C: Integer:= Pos('//', S);
    if C > 0 then S:= Copy(S, 1, C - 1);
    for var M: TMatch in TRegEx.Matches(S, '([A-Za-z_][A-Za-z0-9_]*)(?=(\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*\s*:(?!=))') do
      ANames.AddOrSetValue(LowerCase(M.Groups[1].Value), True);
  end;
end;

function IsRefKindOfInterest(const AKind: string): Boolean;
begin
  Result:= MatchText(AKind, ['read', 'write', 'call', 'type_use']);
end;

function IsTopLevelKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skClass, skInterface, skRecord, skEnum, skProcedure, skFunction, skVarDecl,
    skConstDecl, skTypeAlias];
end;

function IsMemberKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skMethod, skConstructor, skDestructor, skProperty, skField];
end;

function IsTypeKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skClass, skInterface, skRecord];
end;

function PlatformFiltered(const ACands, AUsed: TArray<string>): TArray<string>;
const
  FOREIGN: array[0..4] of string = ('Posix.', 'Macapi.', 'Androidapi.', 'iOSapi.', 'Linuxapi.');
var
  UsesVcl: Boolean;
  UsesFmx: Boolean;
begin
  UsesVcl:= False;
  UsesFmx:= False;
  for var U: string in AUsed do
  begin
    if StartsText('Vcl.', U) then UsesVcl:= True;
    if StartsText('FMX.', U) then UsesFmx:= True;
  end;
  Result:= nil;
  for var C: string in ACands do
  begin
    var Drop: Boolean:= False;
    for var F: string in FOREIGN do
      if StartsText(F, C) then
      begin
        Drop:= True;
        for var U: string in AUsed do
          if StartsText(F, U) then Drop:= False;
      end;
    if UsesVcl and (not UsesFmx) and StartsText('FMX.', C) then Drop:= True;
    if UsesFmx and (not UsesVcl) and StartsText('Vcl.', C) then Drop:= True;
    if not Drop then Result:= Result + [C];
  end;
end;

{ True when the line still holds AName at 1-based column ACol. }
function NameAt(const ALines: TArray<string>; ALine, ACol: Integer; const AName: string): Boolean;
begin
  Result:= InRange(ALine, 1, Length(ALines)) and (ACol >= 1) and
    SameText(Copy(ALines[ALine - 1], ACol, Length(AName)), AName);
end;

class function TMissingUsesChecker.CyclePath(const AStore: ISymbolStore; AFromFid: Int64;
  const AFromUnit, AToUnit: string; AInterfaceOnly: Boolean): string;
var
  FidOf  : TDictionary<string, Int64>;
  NameOf : TDictionary<Int64, string>;
  Parent : TDictionary<Int64, Int64>;
  Queue  : TQueue<Int64>;

  function UnitFid(const AUnit: string): Int64;
  begin
    if FidOf.TryGetValue(LowerCase(AUnit), Result) then Exit;
    Result:= 0;
    for var S: TSymbol in AStore.FindSymbolsByExactName(AUnit) do
      if (S.Kind = skUnit) and SameText(S.Name, AUnit) then
      begin
        Result:= S.FileId;
        Break;
      end;
    FidOf.Add(LowerCase(AUnit), Result);
    if Result > 0 then NameOf.AddOrSetValue(Result, AUnit);
  end;

begin
  Result:= '';
  if (AStore = nil) or (AFromFid <= 0) or (AToUnit = '') then Exit;
  FidOf := TDictionary<string, Int64>.Create;
  NameOf:= TDictionary<Int64, string>.Create;
  Parent:= TDictionary<Int64, Int64>.Create;
  Queue := TQueue<Int64>.Create;
  try
    var Start: Int64:= UnitFid(AToUnit);
    if (Start <= 0) or (Start = AFromFid) then Exit;
    Parent.Add(Start, 0);
    Queue.Enqueue(Start);
    while Queue.Count > 0 do
    begin
      if Parent.Count > MAX_CYCLE_VISITS then Exit;
      var Cur: Int64:= Queue.Dequeue;
      for var U: TUnitUse in AStore.GetUnitUsesForFile(Cur) do
      begin
        if AInterfaceOnly and (U.Section <> uusInterface) then Continue;
        var Nxt: Int64:= UnitFid(U.UnitName);
        if (Nxt <= 0) or Parent.ContainsKey(Nxt) then Continue;
        Parent.Add(Nxt, Cur);
        if Nxt = AFromFid then
        begin
          { walk back: AFromFid <- ... <- Start }
          var Chain: TArray<string>:= [AFromUnit];
          var P: Int64:= Cur;
          while P <> 0 do
          begin
            var Nm: string;
            if not NameOf.TryGetValue(P, Nm) then Nm:= '?';
            Chain:= [Nm] + Chain;
            P:= Parent[P];
          end;
          Result:= AFromUnit + ' -> ' + string.Join(' -> ', Chain);
          Exit;
        end;
        Queue.Enqueue(Nxt);
      end;
    end;
  finally
    Queue.Free;
    Parent.Free;
    NameOf.Free;
    FidOf.Free;
  end;
end;

class function TMissingUsesChecker.Analyze(const AFile: string;  // dl:ok cyclomatic-complexity@162c -- REVIEWED 2026-10-29: the body is the rule's ordered list of precision guards, one Continue each; splitting it scatters the contract the unit header states
  const AFileStore: ISymbolStore; AFileId: Int64;
  const ALookup: TArray<ISymbolStore>): TArray<TMissingUsesFinding>;
var
  Lines    : TArray<string>;
  Stores   : TArray<ISymbolStore>;
  OwnNames : TDictionary<string, Boolean>;
  Infos    : TDictionary<string, TNameInfo>;
  Parents  : TDictionary<string, TSymbol>;    { 'storeIdx|id' -> symbol }
  Occs     : TDictionary<string, TArray<TOccurrence>>;
  Order    : TList<string>;
  WithCache: TDictionary<Int64, Boolean>;
  Used     : TArray<string>;
  ThisUnit : string;
  ImplLine : Integer;
  GuardState: Integer; { 0 not asked, 1 every used unit is indexed, 2 not }

  function ParentOf(AStoreIdx: Integer; AId: Int64): TSymbol;
  begin
    var Key: string:= IntToStr(AStoreIdx) + '|' + IntToStr(AId);
    if Parents.TryGetValue(Key, Result) then Exit;
    Result:= if AId > 0 then Stores[AStoreIdx].GetSymbolById(AId) else Default(TSymbol);
    Parents.Add(Key, Result);
  end;

  function IsUsed(const AUnit: string): Boolean;
  begin
    if SameText(AUnit, 'System') or SameText(AUnit, 'SysInit') or SameText(AUnit, ThisUnit) then Exit(True);
    for var U: string in Used do
      if TUsesText.SameUnit(U, AUnit) then Exit(True);
    Result:= False;
  end;

  { The unit whose interface makes S visible to other units, or ''. }
  function DeclaringUnit(AStoreIdx: Integer; const S: TSymbol): string;
  begin
    Result:= '';
    if not SameText(S.Section, 'interface') then Exit;
    var P: TSymbol:= ParentOf(AStoreIdx, S.ParentId);
    if IsTopLevelKind(S.Kind) and (P.Kind = skUnit) then Exit(P.Name);
    if (S.Kind = skEnumValue) and (P.Kind = skEnum) and SameText(P.Section, 'interface')
      and not ContainsText(P.Directives, 'scopedenums') then
    begin
      var PP: TSymbol:= ParentOf(AStoreIdx, P.ParentId);
      if PP.Kind = skUnit then Exit(PP.Name);
    end;
  end;

  { True when some lookup store indexes a unit AEntry names, trying the
    default VCL unit scope names for an unscoped entry (SysUtils). }
  function KnownUnit(const AEntry: string): Boolean;
  const
    SCOPES: array[0..9] of string = ('', 'System.', 'Winapi.', 'Vcl.', 'Data.', 'Xml.', 'Datasnap.',
      'Soap.', 'Web.', 'System.Win.');
  begin
    for var Pfx: string in SCOPES do
      for var St: ISymbolStore in Stores do
        for var S: TSymbol in St.FindSymbolsByExactName(Pfx + AEntry) do
          if (S.Kind = skUnit) and SameText(S.Name, Pfx + AEntry) then Exit(True);
    Result:= False;
  end;

  function InfoOf(const AName: string): TNameInfo;
  begin
    if Infos.TryGetValue(LowerCase(AName), Result) then Exit;
    Result:= Default(TNameInfo);
    for var Si: Integer:= 0 to High(Stores) do
      for var S: TSymbol in Stores[Si].FindSymbolsByExactName(AName) do
      begin
        if not SameText(S.Name, AName) then Continue;
        if IsMemberKind(S.Kind) then
        begin
          Result.HasAnyMember:= True;
          if ParentOf(Si, S.ParentId).Kind = skClass then Result.HasClassMember:= True;
          Continue;
        end;
        var U: string:= DeclaringUnit(Si, S);
        if U = '' then Continue;
        if IsUsed(U) then
        begin
          Result.InScope:= True;
          Continue;
        end;
        if not MatchText(U, Result.Candidates) then Result.Candidates:= Result.Candidates + [U];
      end;
    Result.Candidates:= PlatformFiltered(Result.Candidates, Used);
    { top-ranked: a re-declaration in a framework (Spring's TBytes alias) loses to the one RTL unit }
    if Length(Result.Candidates) > 1 then
    begin
      var Rtl: TArray<string>:= nil;
      for var C: string in Result.Candidates do
        if StartsText('System.', C) then Rtl:= Rtl + [C];
      if Length(Rtl) = 1 then Result.Candidates:= Rtl;
    end;
    Infos.Add(LowerCase(AName), Result);
  end;

  { The routine whose body holds the ref, walking out of nested routines to
    the outermost one; Default when the ref is outside any routine. }
  function OuterRoutine(AId: Int64; out AIsMethod: Boolean): TSymbol;
  begin
    AIsMethod:= False;
    Result   := Default(TSymbol);
    var Cur: TSymbol:= if AId > 0 then AFileStore.GetSymbolById(AId) else Default(TSymbol);
    var Guard: Integer:= 0;
    while (Cur.Id > 0) and (Guard < MAX_NESTING) do
    begin
      Inc(Guard);
      if Cur.Kind in [skMethod, skConstructor, skDestructor] then
      begin
        AIsMethod:= True;
        Exit(Cur);
      end;
      if Cur.Kind in [skProcedure, skFunction] then Result:= Cur else Exit;
      var P: TSymbol:= if Cur.ParentId > 0 then AFileStore.GetSymbolById(Cur.ParentId) else Default(TSymbol);
      if IsTypeKind(P.Kind) then
      begin
        AIsMethod:= True;
        Exit;
      end;
      Cur:= P;
    end;
  end;

  function RoutineHasWith(const ARoutine: TSymbol): Boolean;
  begin
    if ARoutine.Id <= 0 then Exit(False);
    if WithCache.TryGetValue(ARoutine.Id, Result) then Exit;
    Result:= False;
    var A: Integer:= if ARoutine.ImplStartLine > 0 then ARoutine.ImplStartLine else ARoutine.StartLine;
    var B: Integer:= if ARoutine.ImplEndLine > 0 then ARoutine.ImplEndLine else ARoutine.EndLine;
    for var L: Integer:= A to B do
      if InRange(L, 1, Length(Lines)) then
      begin
        var T: string:= Lines[L - 1];
        var C: Integer:= Pos('//', T);
        if C > 0 then T:= Copy(T, 1, C - 1);
        if TRegEx.IsMatch(T, '(^|[^A-Za-z0-9_&])with\s', [roIgnoreCase]) then
        begin
          Result:= True;
          Break;
        end;
      end;
    WithCache.Add(ARoutine.Id, Result);
  end;

  procedure CollectOwnNames;
  begin
    for var S: TSymbol in AFileStore.FindSymbolsByFile(AFileStore.GetFilePath(AFileId)) do
    begin
      if S.Kind = skUnit then ThisUnit:= S.Name;
      if S.Name <> '' then OwnNames.AddOrSetValue(LowerCase(S.Name), True);
      if S.GenericParams <> '' then
        for var M: TMatch in TRegEx.Matches(S.GenericParams, '[A-Za-z_][A-Za-z0-9_]*') do
          OwnNames.AddOrSetValue(LowerCase(M.Value), True);
    end;
  end;

  function BuildFinding(const AName: string; const AOccs: TArray<TOccurrence>; const AOcc: TOccurrence;
    const AInfo: TNameInfo): TMissingUsesFinding;
  begin
    Result:= Default(TMissingUsesFinding);
    var F: TLintFinding:= Default(TLintFinding);
    F.RuleId    := MISSING_USES_RULE;
    F.FilePath  := AFile;
    F.Severity  := 'warning';
    F.StartLine := AOcc.Ref.StartLine;
    F.StartCol  := AOcc.Ref.StartCol;
    F.EndLine   := AOcc.Ref.StartLine;
    F.EndCol    := AOcc.Ref.StartCol + Length(AOcc.Ref.NameText);
    F.SymbolName:= AName;
    var NeedIntf: Boolean:= False;
    for var O: TOccurrence in AOccs do
      if O.Interface_ then NeedIntf:= True;
    if Length(AInfo.Candidates) > 1 then
    begin
      var Listed: TArray<string>:= Copy(AInfo.Candidates, 0, MAX_LISTED_CANDIDATES);
      var More: string:= if Length(AInfo.Candidates) > MAX_LISTED_CANDIDATES then
        Format(' (+%d more)', [Length(AInfo.Candidates) - MAX_LISTED_CANDIDATES]) else '';
      F.Message:= Format('''%s'' is declared in units %s%s -- add one of them to the uses clause',
        [AName, string.Join(', ', Listed), More]);
      Result.Finding:= F;
      Result.Section:= if NeedIntf then usInterface else usImplementation;
      Exit;
    end;
    var U: string:= AInfo.Candidates[0];
    Result.UnitName:= U;
    var Suffix: string:= '';
    var Offer: TUsesSection:= if NeedIntf then usInterface else usImplementation;
    var ImplTitle: string:= Format('Add %s to the implementation uses clause', [U]);
    var IntfTitle: string:= Format('Add %s to the interface uses clause', [U]);
    var AnyPath: string:= CyclePath(AFileStore, AFileId, ThisUnit, U, False);
    var OfferIntfToo: Boolean:= False;
    if NeedIntf then
    begin
      var IntfPath: string:= CyclePath(AFileStore, AFileId, ThisUnit, U, True);
      if IntfPath <> '' then
      begin
        Offer       := usImplementation;
        OfferIntfToo:= True;
        Suffix      := Format('and move its interface use there (the interface uses clause would create a circular unit reference: %s)', [IntfPath]);
        IntfTitle   := IntfTitle + Format(' (warning: circular unit reference %s -- E2047)', [IntfPath]);
        ImplTitle   := ImplTitle + ' (avoids the interface cycle; move the interface use of ''' + AName + ''' too)';
        if AnyPath <> '' then ImplTitle:= ImplTitle + Format(' (warning: uses cycle %s)', [AnyPath]);
      end
      else if AnyPath <> '' then
      begin
        Suffix   := Format('(warning: this creates a uses cycle: %s)', [AnyPath]);
        IntfTitle:= IntfTitle + Format(' (warning: uses cycle %s)', [AnyPath]);
      end;
    end
    else if AnyPath <> '' then
    begin
      Suffix   := Format('(warning: this creates a uses cycle: %s)', [AnyPath]);
      ImplTitle:= ImplTitle + Format(' (warning: uses cycle %s)', [AnyPath]);
    end;
    F.Message     := TUsesText.FormatMessage(AName, U, Offer, Suffix);
    Result.Finding:= F;
    Result.Section:= Offer;
    var Fx: TMissingUsesFix;
    Fx:= Default(TMissingUsesFix);
    if TUsesText.BuildInsertion(Lines, [U], Offer, Fx.Insertion) then
    begin
      Fx.Section  := Offer;
      Fx.Title    := if Offer = usInterface then IntfTitle else ImplTitle;
      Fx.Preferred:= True;
      Result.Fixes:= Result.Fixes + [Fx];
    end;
    if OfferIntfToo and TUsesText.BuildInsertion(Lines, [U], usInterface, Fx.Insertion) then
    begin
      Fx.Section  := usInterface;
      Fx.Title    := IntfTitle;
      Fx.Preferred:= False;
      Result.Fixes:= Result.Fixes + [Fx];
    end;
  end;

begin
  Result:= nil;
  if (AFileStore = nil) or (AFileId <= 0) then Exit;
  Lines:= TLiveDocuments.ReadLines(AFile);
  if not TUsesText.IsUnitText(Lines) then Exit;
  ImplLine:= TUsesText.ImplementationLine(Lines);
  if ImplLine <= 0 then Exit;
  Used:= TUsesText.UsesEntries(Lines);
  Stores:= nil;
  for var St: ISymbolStore in ALookup do
    if St <> nil then
    begin
      var Dup: Boolean:= False;
      for var Have: ISymbolStore in Stores do
        if Have = St then Dup:= True;
      if not Dup then Stores:= Stores + [St];
    end;
  var HaveOwn: Boolean:= False;
  for var Have: ISymbolStore in Stores do
    if Have = AFileStore then HaveOwn:= True;
  if not HaveOwn then Stores:= [AFileStore] + Stores;

  OwnNames := TDictionary<string, Boolean>.Create;
  Infos    := TDictionary<string, TNameInfo>.Create;
  Parents  := TDictionary<string, TSymbol>.Create;
  Occs     := TDictionary<string, TArray<TOccurrence>>.Create;
  Order    := TList<string>.Create;
  WithCache:= TDictionary<Int64, Boolean>.Create;
  try
    ThisUnit  := '';
    GuardState:= 0;
    CollectOwnNames;
    AddTextDeclaredNames(Lines, OwnNames);
    if ThisUnit = '' then Exit;
    for var R: TReference in AFileStore.GetReferencesFromFile(AFileId) do
    begin
      if (R.SymbolId > 0) or (R.ReceiverText <> '') or not IsRefKindOfInterest(R.Kind) then Continue;
      var N: string:= R.NameText;
      if (N = '') or N.Contains('.') or IsIntrinsicName(N) then Continue;
      if OwnNames.ContainsKey(LowerCase(N)) or IsUsed(N) then Continue;
      if not NameAt(Lines, R.StartLine, R.StartCol, N) then Continue; { stale index: say nothing }
      var Info: TNameInfo:= InfoOf(N);
      if Info.InScope or (Length(Info.Candidates) = 0) then Continue;
      { An unindexed used unit -- or no System at all, i.e. no platform library --
        could declare any name: judging scope without it is guessing. Asked
        once, and only when a candidate appears (most files never get here). }
      if GuardState = 0 then
      begin
        GuardState:= 1;
        for var E: string in Used + ['System'] do
          if not KnownUnit(E) then GuardState:= 2;
      end;
      if GuardState = 2 then Exit;
      if Info.HasAnyMember or Info.HasClassMember then
      begin
        var IsMethod: Boolean;
        var Outer: TSymbol:= OuterRoutine(R.EnclosingSymbolId, IsMethod);
        if IsMethod and Info.HasClassMember then Continue;
        if Info.HasAnyMember and RoutineHasWith(Outer) then Continue;
      end;
      var O: TOccurrence;
      O.Ref       := R;
      O.Interface_:= R.StartLine < ImplLine;
      var Key: string:= LowerCase(N);
      var Arr: TArray<TOccurrence>;
      if not Occs.TryGetValue(Key, Arr) then
      begin
        Arr:= nil;
        Order.Add(Key);
      end;
      { one occurrence per position: a call ref and a read ref can share it }
      var Dup: Boolean:= False;
      for var Prev: TOccurrence in Arr do
        if (Prev.Ref.StartLine = R.StartLine) and (Prev.Ref.StartCol = R.StartCol) then Dup:= True;
      if not Dup then Occs.AddOrSetValue(Key, Arr + [O]);
    end;
    for var Key: string in Order do
    begin
      var Arr: TArray<TOccurrence>:= Occs[Key];
      var Info: TNameInfo:= Infos[Key];
      var Base: TMissingUsesFinding:= BuildFinding(Arr[0].Ref.NameText, Arr, Arr[0], Info);
      for var O: TOccurrence in Arr do
      begin
        var MF: TMissingUsesFinding:= Base;
        MF.Finding.StartLine:= O.Ref.StartLine;
        MF.Finding.StartCol := O.Ref.StartCol;
        MF.Finding.EndLine  := O.Ref.StartLine;
        MF.Finding.EndCol   := O.Ref.StartCol + Length(O.Ref.NameText);
        Result:= Result + [MF];
      end;
    end;
  finally
    WithCache.Free;
    Order.Free;
    Occs.Free;
    Parents.Free;
    Infos.Free;
    OwnNames.Free;
  end;
end;

class function TMissingUsesChecker.Check(const AFile: string; const AFileStore: ISymbolStore; AFileId: Int64;
  const ALookup: TArray<ISymbolStore>): TArray<TLintFinding>;
begin
  Result:= nil;
  for var MF: TMissingUsesFinding in Analyze(AFile, AFileStore, AFileId, ALookup) do
    Result:= Result + [MF.Finding];
end;

{ `lint --fix`: every finding of the rule in one file, its units grouped per
  section from the messages (the section the checker decided, cycle-checked),
  added with ONE insertion per clause. The message is the contract, read back
  by TUsesText.ParseMessage -- the same reader the IDE quick-fix uses. }
function FixMissingUses(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  Lines: TArray<string>;
  Units: array[TUsesSection] of TArray<string>;
  Cnt  : array[TUsesSection] of Integer;
begin
  Result:= nil;
  AFixed:= 0;
  Units[usInterface]     := nil;
  Units[usImplementation]:= nil;
  Cnt[usInterface]       := 0;
  Cnt[usImplementation]  := 0;
  for var F: TLintFinding in AFindings do
  begin
    if not SameText(F.RuleId, MISSING_USES_RULE) or not SameText(F.FilePath, APath) then Continue;
    var U: string;
    var Sec: TUsesSection;
    if not TUsesText.ParseMessage(F.Message, U, Sec) then Continue;
    if not MatchText(U, Units[Sec]) then Units[Sec]:= Units[Sec] + [U];
    Inc(Cnt[Sec]);
  end;
  { a unit the interface gains must not be listed twice (E2004) }
  var ImplOnly: TArray<string>:= nil;
  for var U: string in Units[usImplementation] do
    if not MatchText(U, Units[usInterface]) then ImplOnly:= ImplOnly + [U];
  Units[usImplementation]:= ImplOnly;
  if (Length(Units[usInterface]) = 0) and (Length(Units[usImplementation]) = 0) then Exit;
  Lines:= TLiveDocuments.ReadLines(APath);
  for var Sec: TUsesSection:= Low(TUsesSection) to High(TUsesSection) do
  begin
    var Ins: TUsesInsertion;
    if (Length(Units[Sec]) = 0) or not TUsesText.BuildInsertion(Lines, Units[Sec], Sec, Ins) then Continue;
    var E: TTextEdit:= Default(TTextEdit);
    E.FilePath  := APath;
    E.Kind      := tekReplaceLines;
    E.Line      := Ins.Line;
    E.EndLine   := Ins.Line;
    E.Text      := TUsesText.ApplyToLine(Lines, Ins);
    E.ExpectText:= Lines[Ins.Line - 1];
    Result:= Result + [E];
    Inc(AFixed, Cnt[Sec]);
  end;
end;

initialization
  RegisterFileFixer(MISSING_USES_RULE, FixMissingUses);

end.
