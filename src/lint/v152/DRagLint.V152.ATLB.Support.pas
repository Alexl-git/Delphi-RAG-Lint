unit DRagLint.V152.ATLB.Support;

{ Wave v152 lane ATLB -- helpers of DRagLint.V152.ATLB (private to the lane).

  member-could-be-private (survey row 19): a PUBLIC member of a class whose every
  reference in the index sits in the file that declares it. Delphi's `private` is
  visible to the whole unit, so such a member can leave the public section without
  breaking a caller the index can see. The rule is deliberately conservative: it
  stays silent whenever it cannot prove the narrowing safe.

  Exemptions (silent): published members and the unlabelled section of a class
  (VisExplicit = False); virtual / dynamic / override / abstract / message /
  reintroduce / external routines; constructors and destructors; members of
  helpers; members whose name an interface of the class declares, or any class
  whose interface list holds an ancestor that does not resolve (unsure); members
  carrying an attribute (RTTI may read them; read from the attributes index fact,
  the source line above the member only on an index without it); members with no reference at all
  (dead-code rules own that); a name referenced from a second file (another unit,
  or a form file); members of a unit that lists more than one project in its
  `dl:shared` header (a sibling project's index is not open here); a name another
  indexed file spells on a line the preprocessor blanks -- an inactive conditional
  branch the index never parsed (1.52 TAILS-ENG2). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Evaluates the member-could-be-private rule over one project index.</summary>
  /// <remarks>Stateless; class methods only. Reads the store, never writes it.</remarks>
  TMemberPrivacy = class
  public
    /// <summary>Finds public members that no file but their own declaring file references.</summary>
    /// <param name="AStore">Project index (not nil).</param>
    /// <param name="ALibStore">Library index used to resolve interface ancestors; may be nil.</param>
    /// <param name="ARuleId">Rule id to stamp on each finding.</param>
    /// <returns>One hint per candidate member; nil when none.</returns>
    /// <remarks>Cost: one GetReferencesFromFile per indexed file, plus a raw read of each indexed file
    /// when there is a candidate (preprocessed only when it spells a candidate's name): a candidate
    /// another file names inside an inactive conditional branch is dropped. Meant for lint-all only.</remarks>
    class function Find(const AStore, ALibStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>; static;
  end;

  /// <summary>1.52 BK-ATTRRULES (B48): evaluates debug-display-placeholder on one indexed file --
  /// a `[DebuggerDisplay('...{Name}...')]` attribute on a class or record whose template names
  /// a member the type (with its ancestors) does not have.</summary>
  /// <remarks>Stateless; class methods only. Reads the attributes index fact (BK-EXTRA, B09) and
  /// the symbol tables, never the source text. Silent whenever it cannot prove the member absent:
  /// no attributes table, a first argument that is not one string literal, a placeholder that
  /// does not start with an identifier, an ancestor no index places. Self is always accepted;
  /// a placeholder is judged by its leading identifier only ({Owner.Name}, {Count,nq}).</remarks>
  TDebugDisplayCheck = class
  public
    /// <summary>Finds the debugger-display placeholders of one file that name no member.</summary>
    /// <param name="AStore">Project index; nil returns nil.</param>
    /// <param name="ALibStore">Library index used to place RTL / VCL ancestors; may be nil (TObject
    /// is then judged by a built-in member list, any other outside ancestor is unknown).</param>
    /// <param name="AFileId">files.id of the file in AStore; 0 returns nil.</param>
    /// <param name="APath">The file path stamped on each finding.</param>
    /// <param name="ARuleId">Rule id to stamp on each finding.</param>
    /// <returns>One warning per unknown placeholder, at the attribute name; nil when none.</returns>
    class function Check(const AStore, ALibStore: ISymbolStore; AFileId: Int64;
      const APath, ARuleId: string): TArray<TLintFinding>; static;
  end;
implementation

uses
  System.Classes
  , System.IOUtils
  , System.RegularExpressions
  , System.StrUtils                  { MatchText }
  , DRagLint.Core.Encoding          { EnsureUtf8Bytes }
  , DRagLint.Diagnostics.ParseCache  { TAstParseCache.ApplyPreprocess -- the transform the rules read }
  , DRagLint.Lint.SharedUnit
  ;

const
  EXEMPT_DIRECTIVES: array[0..8] of string =
    ('virtual', 'dynamic', 'override', 'abstract', 'message', 'reintroduce', 'external', 'export', 'static');
  MAX_IFACE_DEPTH = 4;

function HeritageNames(const AHeritage: string): TArray<string>;
begin
  Result:= nil;
  var Depth: Integer:= 0;
  var Cur  : string:= '';
  for var Ch: Char in AHeritage do
    if Ch = '<' then Inc(Depth)
    else if Ch = '>' then Dec(Depth)
    else if (Ch = ',') and (Depth = 0) then
    begin
      Result:= Result + [Cur];
      Cur:= '';
    end
    else if Depth = 0 then Cur:= Cur + Ch;  // dl:ok concat-in-loop@1b88 -- REVIEWED 2026-11-17 v152 ATLB: one identifier-list string of a few dozen chars per class heritage
  Result:= Result + [Cur];
  for var I: Integer:= 0 to High(Result) do
  begin
    var N: string:= Trim(Result[I]);
    var P: Integer:= N.LastDelimiter('.');
    if P >= 0 then N:= N.Substring(P + 1);
    Result[I]:= N;
  end;
end;

function LooksLikeInterface(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
end;

function FindType(const AStore, ALibStore: ISymbolStore; const AName: string; out ASym: TSymbol;
  out AOwner: ISymbolStore): Boolean;
begin
  Result:= False;
  ASym  := Default(TSymbol);
  AOwner:= nil;
  for var Pass: Integer:= 0 to 1 do
  begin
    var St: ISymbolStore:= (if Pass = 0 then AStore else ALibStore);
    if St = nil then Continue;
    for var S: TSymbol in St.FindSymbolsByExactName(AName) do
      if S.Kind in [skClass, skInterface, skRecord] then
      begin
        ASym  := S;
        AOwner:= St;
        Exit(True);
      end;
  end;
end;

{ Adds the member names of interface AName (and its ancestors) to ANames. False = unsure. }
function CollectInterface(const AStore, ALibStore: ISymbolStore; const AName: string;
  const ANames: TDictionary<string, Boolean>; ADepth: Integer): Boolean;
var
  T    : TSymbol;
  Owner: ISymbolStore;
begin
  Result:= False;
  if ADepth > MAX_IFACE_DEPTH then Exit;
  if not FindType(AStore, ALibStore, AName, T, Owner) or (T.Kind <> skInterface) then Exit;
  for var C: TSymbol in Owner.FindAllChildSymbols(T.Id) do
    ANames.AddOrSetValue(LowerCase(C.Name), True);
  Result:= True;
  if Trim(T.Heritage) = '' then Exit;
  for var A: string in HeritageNames(T.Heritage) do
    if (A <> '') and not SameText(A, 'IInterface') and not SameText(A, 'IUnknown')
      and not CollectInterface(AStore, ALibStore, A, ANames, ADepth + 1) then Result:= False;
end;

{ Fills ANames with the member names the class's interfaces declare. False = a
  heritage entry that looks like an interface did not resolve: the caller skips the class. }
function InterfaceNamesOf(const AStore, ALibStore: ISymbolStore; const AClass: TSymbol;
  const ANames: TDictionary<string, Boolean>): Boolean;
var
  T    : TSymbol;
  Owner: ISymbolStore;
begin
  Result:= True;
  if Trim(AClass.Heritage) = '' then Exit;
  for var H: string in HeritageNames(AClass.Heritage) do
  begin
    if H = '' then Continue;
    if FindType(AStore, ALibStore, H, T, Owner) then
    begin
      if (T.Kind = skInterface) and not CollectInterface(AStore, ALibStore, H, ANames, 0) then Result:= False;
    end
    else if LooksLikeInterface(H) then Result:= False;
  end;
end;

function HasAttributeAbove(const ALines: TArray<string>; ALine: Integer): Boolean;
begin
  Result:= False;
  if (ALine < 1) or (ALine > Length(ALines)) then Exit;
  { The symbol may start AT its attribute line ([Attr] procedure X;) or one line below it. }
  if Trim(ALines[ALine - 1]).StartsWith('[') then Exit(True);
  var I: Integer:= ALine - 2;
  while (I >= 0) and (Trim(ALines[I]) = '') do Dec(I);
  if I < 0 then Exit;
  var L: string:= Trim(ALines[I]);
  Result:= (L <> '') and (L[1] = '[') ;
end;

function HasExemptDirective(const ASym: TSymbol): Boolean;
begin
  Result:= ASym.IsVirtual;
  if Result then Exit;
  var Words: TArray<string>:= (LowerCase(ASym.Directives) + ' ' + LowerCase(ASym.Modifiers)).Split([' ']);
  for var W: string in Words do
    for var D: string in EXEMPT_DIRECTIVES do
      if W = D then Exit(True);
end;

{ 1.52 TAILS-ENG2 (FPM2 MsgToString / TRACE_CODESITE): the lowercased names of ANames that another
  indexed file of AStore spells on a line the preprocessor BLANKS (an inactive conditional branch the
  index never parsed). Such a reference is a caller in another build configuration: the member is
  treated as used elsewhere. ANames maps a name to the file id that declares it (its own file is
  skipped). A file is read and preprocessed only when its raw text holds one of the names. }
function NamesInInactiveBranches(const AStore: ISymbolStore; const ANames: TDictionary<string, Int64>): TDictionary<string, Boolean>;
begin
  Result:= TDictionary<string, Boolean>.Create;
  if ANames.Count = 0 then Exit;
  for var FileId: Int64 in AStore.GetAllFileIds do
  begin
    var Path: string:= AStore.GetFilePath(FileId);
    if not MatchText(ExtractFileExt(Path), ['.pas', '.dpr', '.dpk', '.inc']) then Continue;
    var Raw: TBytes;
    try
      Raw:= EnsureUtf8Bytes(TFile.ReadAllBytes(Path));
    except  // dl:ok try-except-swallowed@59fd -- an unreadable file names nothing; the finding stands as before
      on Exception do Continue;
    end;
    var RawText: string:= TEncoding.UTF8.GetString(Raw);
    var Lower: string:= LowerCase(RawText);
    var Want: TArray<string>:= nil;
    for var N: string in ANames.Keys do
      if (ANames[N] <> FileId) and not Result.ContainsKey(N) and Lower.Contains(N) then Want:= Want + [N];
    if Want = nil then Continue;
    var PpLines : TArray<string>:= TEncoding.UTF8.GetString(TAstParseCache.ApplyPreprocess(Raw, Path)).Split([#10]);
    var RawLines: TArray<string>:= RawText.Split([#10]);
    if Length(PpLines) <> Length(RawLines) then Continue;
    for var I: Integer:= 0 to High(RawLines) do
      if (Trim(PpLines[I]) = '') and (Trim(RawLines[I]) <> '') then
        for var N: string in Want do
          if TRegEx.IsMatch(RawLines[I], '\b' + N + '\b', [roIgnoreCase]) then Result.AddOrSetValue(N, True);
  end;
end;

class function TMemberPrivacy.Find(const AStore, ALibStore: ISymbolStore; const ARuleId: string): TArray<TLintFinding>;
var
  RefFile  : TDictionary<string, Int64>;
  FileLines: TDictionary<Int64, TArray<string>>;
  Shared   : TDictionary<Int64, Boolean>;
  Parents  : TDictionary<Int64, TSymbol>;
  IfaceOf  : TDictionary<Int64, TDictionary<string, Boolean>>;
  AttrFiles: TDictionary<Int64, Boolean>;
  AttrSyms : TDictionary<Int64, Boolean>;
  Prev     : Int64;
begin
  Result:= nil;
  { an index built before the attributes table falls back to the one-line source peek }
  var UseFact: Boolean:= AStore.HasAttributes;
  AttrFiles:= TDictionary<Int64, Boolean>.Create;
  AttrSyms := TDictionary<Int64, Boolean>.Create;
  RefFile  := TDictionary<string, Int64>.Create;
  FileLines:= TDictionary<Int64, TArray<string>>.Create;
  Shared   := TDictionary<Int64, Boolean>.Create;
  Parents  := TDictionary<Int64, TSymbol>.Create;
  IfaceOf  := TDictionary<Int64, TDictionary<string, Boolean>>.Create;
  try
    for var FileId: Int64 in AStore.GetAllFileIds do
      for var R: TReference in AStore.GetReferencesFromFile(FileId) do
      begin
        var Key: string:= LowerCase(R.NameText);
        if not RefFile.TryGetValue(Key, Prev) then RefFile.Add(Key, FileId)
        else if Prev <> FileId then RefFile.AddOrSetValue(Key, -1);
      end;
    for var FileId: Int64 in AStore.GetAllFileIds do
    begin
      var Path: string:= AStore.GetFilePath(FileId);
      if not SameText(ExtractFileExt(Path), '.pas') then Continue;
      for var Sym: TSymbol in AStore.FindSymbolsByFile(Path) do
      begin
        if Sym.Kind not in [skMethod, skFunction, skProcedure, skField] then Continue;
        if (Sym.ParentId <= 0) or (Trim(LowerCase(Sym.Modifiers)) <> 'public') or not Sym.VisExplicit then Continue;
        if HasExemptDirective(Sym) then Continue;
        if not RefFile.TryGetValue(LowerCase(Sym.Name), Prev) or (Prev <> Sym.FileId) then Continue;
        var Cls: TSymbol;
        if not Parents.TryGetValue(Sym.ParentId, Cls) then
        begin
          Cls:= AStore.GetSymbolById(Sym.ParentId);
          Parents.Add(Sym.ParentId, Cls);
        end;
        if (Cls.Id <> Sym.ParentId) or (Cls.Kind not in [skClass, skRecord]) or Cls.IsHelper then Continue;
        var Names: TDictionary<string, Boolean>;
        if not IfaceOf.TryGetValue(Cls.Id, Names) then
        begin
          Names:= TDictionary<string, Boolean>.Create;
          IfaceOf.Add(Cls.Id, Names);
          if not InterfaceNamesOf(AStore, ALibStore, Cls, Names) then Names.AddOrSetValue('*', True);
        end;
        if Names.ContainsKey('*') or Names.ContainsKey(LowerCase(Sym.Name)) then Continue;
        var IsShared: Boolean;
        if not Shared.TryGetValue(FileId, IsShared) then
        begin
          IsShared:= Length(TSharedUnit.ProjectsOf(Path)) > 1;
          Shared.Add(FileId, IsShared);
        end;
        if IsShared then Continue;
        if UseFact then
        begin
          { 1.52 BK-ATTRRULES (B48): the attributes index fact names the decorated symbol --
            no source read, and an attribute list split from its member by a comment or
            spread over several lines is still seen. }
          if not AttrFiles.ContainsKey(FileId) then
          begin
            AttrFiles.Add(FileId, True);
            for var A: TAttributeRow in AStore.GetAttributes(FileId) do
              if A.SymbolId > 0 then AttrSyms.AddOrSetValue(A.SymbolId, True);
          end;
          if AttrSyms.ContainsKey(Sym.Id) then Continue;
        end
        else
        begin
          var Lines: TArray<string>;
          if not FileLines.TryGetValue(FileId, Lines) then
          begin
            try
              Lines:= TFile.ReadAllLines(Path);
            except
              on Exception do
              Lines:= nil;
            end;
            FileLines.Add(FileId, Lines);
          end;
          if (Lines = nil) or HasAttributeAbove(Lines, Sym.StartLine) then Continue;
        end;
        var F: TLintFinding:= Default(TLintFinding);
        F.RuleId    := ARuleId;
        F.Severity  := 'hint';
        F.FileId    := FileId;
        F.FilePath  := Path;
        F.StartLine := Sym.StartLine;
        F.StartCol  := Sym.StartCol;
        F.EndLine   := Sym.EndLine;
        F.EndCol    := Sym.EndCol;
        F.SymbolName:= Sym.Name;
        F.Message   := Format('Public member %s.%s is only referenced inside its own unit -- it could be private', [Cls.Name, Sym.Name]);
        Result:= Result + [F];
      end;
    end;
    // 1.52 TAILS-ENG2: a name another file spells inside an inactive $IFDEF branch is used there.
    var Cands: TDictionary<string, Int64>:= TDictionary<string, Int64>.Create;
    try
      for var F: TLintFinding in Result do Cands.AddOrSetValue(LowerCase(F.SymbolName), F.FileId);
      var Inactive: TDictionary<string, Boolean>:= NamesInInactiveBranches(AStore, Cands);
      try
        if Inactive.Count > 0 then
        begin
          var Kept: TArray<TLintFinding>:= nil;
          for var F: TLintFinding in Result do
            if not Inactive.ContainsKey(LowerCase(F.SymbolName)) then Kept:= Kept + [F];
          Result:= Kept;
        end;
      finally
        Inactive.Free;
      end;
    finally
      Cands.Free;
    end;
  finally
    for var D: TDictionary<string, Boolean> in IfaceOf.Values do D.Free;
    IfaceOf.Free;
    AttrSyms.Free;
    AttrFiles.Free;
    Parents.Free;
    Shared.Free;
    FileLines.Free;
    RefFile.Free;
  end;
end;

{ ---- debug-display-placeholder (1.52 BK-ATTRRULES, B48) ---- }

const
  DEBUG_DISPLAY_NAMES: array[0..1] of string = ('debuggerdisplay', 'debuggerdisplayattribute');
  MAX_ANCESTOR_DEPTH = 32;
  { System.TObject's public surface, used only when no library index places TObject. }
  TOBJECT_MEMBERS: array[0..32] of string = (
    'create', 'free', 'disposeof', 'initinstance', 'cleanupinstance', 'classtype', 'classname',
    'classnameis', 'classparent', 'classinfo', 'instancesize', 'inheritsfrom', 'methodaddress',
    'methodname', 'qualifiedclassname', 'fieldaddress', 'getinterface', 'getinterfaceentry',
    'getinterfacetable', 'unitname', 'unitscope', 'safecallexception', 'afterconstruction',
    'beforedestruction', 'dispatch', 'defaulthandler', 'newinstance', 'freeinstance', 'destroy',
    'tostring', 'equals', 'gethashcode', 'disposed');

function IsDebugDisplayName(const AName: string): Boolean;
begin
  var N: string:= LowerCase(Trim(AName));
  var P: Integer:= N.LastDelimiter('.');
  if P >= 0 then N:= N.Substring(P + 1);
  for var D: string in DEBUG_DISPLAY_NAMES do
    if N = D then Exit(True);
  Result:= False;
end;

{ True when AArgs starts with exactly one Pascal string literal that is the whole first
  argument; AText is its value with '' unescaped. }
function FirstStringLiteral(const AArgs: string; out AText: string): Boolean;
begin
  AText:= '';
  Result:= False;
  var S: string:= Trim(AArgs);
  if (S = '') or (S[1] <> '''') then Exit;
  { the closing quote is the first single quote that is not doubled }
  var I: Integer:= 2;
  while (I <= Length(S)) and not ((S[I] = '''') and ((I = Length(S)) or (S[I + 1] <> ''''))) do
    Inc(I, if S[I] = '''' then 2 else 1);
  if I > Length(S) then Exit;
  AText:= StringReplace(Copy(S, 2, I - 2), '''''', '''', [rfReplaceAll]);
  var Rest: string:= Trim(S.Substring(I));
  Result:= (Rest = '') or (Rest[1] = ',');
end;
// The leading identifier of every brace placeholder of ATemplate; a doubled opening brace is a
// literal brace. A placeholder that does not start with an identifier is not returned.
function PlaceholderNames(const ATemplate: string): TArray<string>;
begin
  Result:= nil;
  var I: Integer:= 1;
  while I <= Length(ATemplate) do
  begin
    if ATemplate[I] <> '{' then
    begin
      Inc(I);
      Continue;
    end;
    if (I < Length(ATemplate)) and (ATemplate[I + 1] = '{') then
    begin
      Inc(I, 2);
      Continue;
    end;
    var Close: Integer:= Pos('}', ATemplate, I + 1);
    if Close = 0 then Exit;
    var Body: string:= Trim(Copy(ATemplate, I + 1, Close - I - 1));
    var J: Integer:= 1;
    while (J <= Length(Body)) and CharInSet(Body[J], ['A'..'Z', 'a'..'z', '_', '0'..'9']) do Inc(J);
    var Ident: string:= Copy(Body, 1, J - 1);
    if (Ident <> '') and CharInSet(Ident[1], ['A'..'Z', 'a'..'z', '_']) then Result:= Result + [Ident];
    I:= Close + 1;
  end;
end;

function FindClassType(const AStore, ALibStore: ISymbolStore; const AName: string; out ASym: TSymbol;
  out AOwner: ISymbolStore): Boolean;
begin
  Result:= FindType(AStore, ALibStore, AName, ASym, AOwner) and (ASym.Kind = skClass);
end;

{ The class ancestor of AClass: the first heritage entry when it is a class, else TObject.
  '' = the first entry is a name no index places and not an I-prefixed interface name
  (an unknown class ancestor -- the caller is unsure). }
function AncestorName(const AStore, ALibStore: ISymbolStore; const AClass: TSymbol): string;
var
  Anc  : TSymbol;
  AncSt: ISymbolStore;
begin
  Result:= 'TObject';
  var Heads: TArray<string>:= HeritageNames(AClass.Heritage);
  if (Length(Heads) = 0) or (Heads[0] = '') or SameText(Heads[0], 'TObject') then Exit;
  if FindType(AStore, ALibStore, Heads[0], Anc, AncSt) then
  begin
    if Anc.Kind = skClass then Result:= Heads[0]
    else if Anc.Kind <> skInterface then Result:= '';
  end
  else if not LooksLikeInterface(Heads[0]) then Result:= '';
end;

{ Fills ANames with the lower-case member names of AType and its class ancestors.
  False = some ancestor could not be placed: the caller stays silent. }
function MemberNamesOf(const AStore, ALibStore: ISymbolStore; const AOwnerStore: ISymbolStore;
  const AType: TSymbol; const ANames: TDictionary<string, Boolean>): Boolean;
var
  Cur  : TSymbol;
  Owner: ISymbolStore;
  Anc  : TSymbol;
  AncSt: ISymbolStore;
begin
  Cur  := AType;
  Owner:= AOwnerStore;
  for var Depth: Integer:= 0 to MAX_ANCESTOR_DEPTH do
  begin
    for var C: TSymbol in Owner.FindAllChildSymbols(Cur.Id) do
      ANames.AddOrSetValue(LowerCase(C.Name), True);
    if Cur.Kind <> skClass then Exit(True);
    if SameText(Cur.Name, 'TObject') then Exit(True);
    var AncName: string:= AncestorName(AStore, ALibStore, Cur);
    if AncName = '' then Exit(False);
    if not FindClassType(AStore, ALibStore, AncName, Anc, AncSt) then
    begin
      if not SameText(AncName, 'TObject') then Exit(False);
      for var M: string in TOBJECT_MEMBERS do ANames.AddOrSetValue(M, True);
      Exit(True);
    end;
    Cur  := Anc;
    Owner:= AncSt;
  end;
  Result:= False;
end;

class function TDebugDisplayCheck.Check(const AStore, ALibStore: ISymbolStore; AFileId: Int64;
  const APath, ARuleId: string): TArray<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (AFileId <= 0) or not AStore.HasAttributes then Exit;
  for var A: TAttributeRow in AStore.GetAttributes(AFileId) do
  begin
    if (A.SymbolId <= 0) or not IsDebugDisplayName(A.Name) then Continue;
    var Template: string;
    if not FirstStringLiteral(A.ArgText, Template) then Continue;
    var Wanted: TArray<string>:= PlaceholderNames(Template);
    if Wanted = nil then Continue;
    var T: TSymbol:= AStore.GetSymbolById(A.SymbolId);
    if (T.Id <> A.SymbolId) or (T.Kind not in [skClass, skRecord]) then Continue;
    var Names: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      if not MemberNamesOf(AStore, ALibStore, AStore, T, Names) then Continue;
      for var W: string in Wanted do
      begin
        if SameText(W, 'Self') or Names.ContainsKey(LowerCase(W)) then Continue;
        var F: TLintFinding:= Default(TLintFinding);
        F.RuleId    := ARuleId;
        F.Severity  := 'warning';
        F.FileId    := AFileId;
        F.FilePath  := APath;
        F.StartLine := A.Line;
        F.StartCol  := A.Col;
        F.EndLine   := A.Line;
        F.EndCol    := A.Col + Length(A.Name);
        F.SymbolName:= T.Name;
        F.Message   := Format('Debugger display placeholder {%s} names no member of %s or its ancestors -- ' +
          'the debugger shows the placeholder, not a value', [W, T.Name]);
        Result:= Result + [F];
      end;
    finally
      Names.Free;
    end;
  end;
end;

end.