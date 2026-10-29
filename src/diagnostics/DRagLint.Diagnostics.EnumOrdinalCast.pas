unit DRagLint.Diagnostics.EnumOrdinalCast;

{ The `enum-ordinal-cast` rule (INBOX-lint-rules-from-new-facts-2026-09-23.md
  rule 3, lane B-ENUM).

  `TCmd(5)`, `Ord(X) = 3` and `case Ord(X) of 2:` hard-code an enum value's
  POSITION. Inserting, removing or reordering a value shifts every later
  ordinal and the code keeps compiling -- it just means something else.

  Three shapes fire:
    1. a cast TO an enum type whose single argument is an integer literal;
    2. an ordinal cast OF an enum expression (Ord, Integer, Byte, ...)
       compared (=, <>, <, >, <=, >=) with an integer literal, either side;
    3. `case <ordinal cast of an enum expression> of` with at least one
       integer-literal label.
  Silent: Ord() against another Ord() (arithmetic / serialisation), an ordinal
  cast of a non-enum (Ord(Ch) = 13), a cast to a non-enum type, a cast of a
  non-literal, a case on the enum itself.

  What is an enum is decided from this file's own declarations (enum types,
  enum values, the declared type of every var / param / field) and, when an
  index is supplied, from the refs at the exact identifier positions (an
  enum-typed symbol, an enum value, or a cast bound to an enum type).

  TYPE SCOPE (ENUMRULES, owner rule 2026-10-28): every finding carries the
  enum type's declaration as ScopeFile / ScopeLine, so ONE
  `// dl:ok enum-ordinal-cast -- <reason>` on the type line reviews every cast of
  that type in any unit (DRagLint.CLI.ApplyLineMarkers). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  ENUM_ORDINAL_CAST_RULE = 'enum-ordinal-cast';

type
  /// <summary>Checker for the enum-ordinal-cast rule: a hard-coded enum ordinal
  /// (a literal cast to an enum, or an enum's ordinal compared with or cased on
  /// a literal).</summary>
  /// <remarks>Stateless; thread-safe as far as TAstParseCache is. Called from
  /// DoLint and DoLintAll behind LintRuleWants(rule, ['enum-ordinal-cast']).</remarks>
  TEnumOrdinalCastChecker = class
  public
    /// <summary>Runs enum-ordinal-cast over one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="AStore">Optional project index; nil restricts the enum
    /// knowledge to the file's own declarations, so FEWER findings, never
    /// different ones.</param>
    /// <param name="AFileId">AFile's id in AStore; 0 (or a nil store) skips the
    /// ref lookups.</param>
    /// <returns>One 'enum-ordinal-cast' warning per offending cast, comparison
    /// or case statement, anchored at that node; empty when clean or
    /// unparsable.</returns>
    /// <remarks>Never raises on an unparsable file (empty result).</remarks>
    class function Check(const AFile: string; const AStore: ISymbolStore;
      AFileId: Int64): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.EnumOrdinalPersisted { CountImplicitOrdinals }
  ;

const
  { The ordinal casts whose argument, when an enum, yields the enum's position. }
  ORD_CASTS: array[0..10] of string = (
    'ord', 'integer', 'cardinal', 'byte', 'word', 'smallint', 'shortint', 'longint',
    'longword', 'nativeint', 'int64');
  COMPARE_OPS: array[0..5] of string = ('=', '<>', '<', '>', '<=', '>=');
  { declType's own name field, and the decl nodes whose names carry a type. }
  FIELD_NAME = 'name';
  FIELD_TYPE = 'type';
  { EnumState answers }
  ENUM_NONE   = -1;
  ENUM_FREE   = 0;
  ENUM_PINNED = 1;
  { how far past an indexed enum's start line its value list may run }
  DECL_WINDOW_LINES = 400;

class function TEnumOrdinalCastChecker.Check(const AFile: string; const AStore: ISymbolStore;
  AFileId: Int64): TArray<TLintFinding>;
var
  Src       : TBytes                                ;
  PF        : TParsedFile                           ;
  Findings  : TList<TLintFinding>                   ;
  EnumTypes : TDictionary<string, Boolean>          ; { lower enum type names declared here -> every value pinned (= N) }
  EnumValues: TDictionary<string, string>           ; { lower enum value name declared here -> lower type name }
  DeclTypes : TDictionary<string, string>           ; { lower var/param/field name -> lower bare type; '' = ambiguous }
  RefByPos  : TDictionary<string, TReference>       ; { 'line:col' (1-based) -> ref }
  StoreEnum : TDictionary<string, Integer>          ; { lower type name -> ENUM_NONE / ENUM_FREE / ENUM_PINNED }
  ScopeFile : TDictionary<string, string>           ; { lower enum type name -> file of its declaration (ENUMRULES) }
  ScopeLine : TDictionary<string, Integer>          ; { lower enum type name -> line of its declaration }

  function NodeStr(const N: TTSNode): string;
  var
    S, E: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte);
    E:= Integer(N.EndByte);
    if (E <= S) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, E - S);
  end;

  { `Unit.TKind` -> `tkind`; '' for anything that is not a plain (dotted) name. }
  function BareLower(const AText: string): string;
  begin
    Result:= Trim(AText);
    var I: Integer:= LastDelimiter('.', Result);
    if I > 0 then Result:= Copy(Result, I + 1, MaxInt);
    Result:= LowerCase(Result);
  end;

  function InList(const AText: string; const AList: array of string): Boolean;
  begin
    Result:= False;
    for var S: string in AList do
      if SameText(AText, S) then Exit(True);
  end;

  procedure NoteDeclType(const AName, AType: string);
  var
    Old: string;
  begin
    if DeclTypes.TryGetValue(AName, Old) then
    begin
      if Old <> AType then DeclTypes[AName]:= '';
    end
    else
      DeclTypes.Add(AName, AType);
  end;

  procedure CollectDecls(const N: TTSNode);
  begin
    if N.IsNull then Exit;
    var T: string:= N.NodeType;
    if T = 'declEnum' then
    begin
      var P: TTSNode:= N.Parent;
      while not P.IsNull and (P.NodeType <> 'declType') do P:= P.Parent;
      if not P.IsNull then
      begin
        var TypeNm: string:= BareLower(NodeStr(P.ChildByField(FIELD_NAME)));
        var Pinned: Boolean:= True;
        for var I: Integer:= 0 to N.NamedChildCount - 1 do
        begin
          var V: TTSNode:= N.NamedChild(I);
          if V.NodeType <> 'declEnumValue' then Continue;
          EnumValues.AddOrSetValue(LowerCase(Trim(NodeStr(V.ChildByField(FIELD_NAME)))), TypeNm);
          if V.ChildByField('value').IsNull then Pinned:= False;
        end;
        EnumTypes.AddOrSetValue(TypeNm, Pinned);
        ScopeFile.AddOrSetValue(TypeNm, AFile);
        ScopeLine.AddOrSetValue(TypeNm, Integer(P.ChildByField(FIELD_NAME).StartPoint.Row) + 1);
      end;
    end
    else if (T = 'declVar') or (T = 'declArg') or (T = 'declField') then
    begin
      var TypeN: TTSNode:= N.ChildByField(FIELD_TYPE);
      if not TypeN.IsNull then
      begin
        var TB: Integer:= Integer(TypeN.StartByte);
        var TName: string:= BareLower(NodeStr(TypeN));
        for var I: Integer:= 0 to N.NamedChildCount - 1 do
        begin
          var C: TTSNode:= N.NamedChild(I);
          { names precede the type node in `A, B: T` }
          if (C.NodeType = 'identifier') and (Integer(C.StartByte) < TB) then
            NoteDeclType(LowerCase(Trim(NodeStr(C))), TName);
        end;
      end;
    end;
    for var I: Integer:= 0 to N.NamedChildCount - 1 do CollectDecls(N.NamedChild(I));
  end;

  function RefAt(const N: TTSNode; out ARef: TReference): Boolean;
  begin
    var P: TTSPoint:= N.StartPoint;
    Result:= RefByPos.TryGetValue(IntToStr(Integer(P.Row) + 1) + ':' + IntToStr(Integer(P.Column) + 1), ARef)
      and (ARef.SymbolId > 0);
  end;

  { An indexed enum's declaration text (from its name on); '' when unreadable. }
  function DeclTextOf(const AEnum: TSymbol): string;
  var
    Lines: TArray<string>;
  begin
    Result:= '';
    try
      Lines:= TFile.ReadAllLines(AStore.GetFilePath(AEnum.FileId), TEncoding.ANSI);
    except  // dl:ok try-except-swallowed@57ce -- an unreadable declaring file only means the pin cannot be proven: the enum counts as unpinned
      on EInOutError do Exit;
      on EStreamError do Exit;
      on EEncodingError do Exit;
    end;
    for var L: Integer:= AEnum.StartLine to AEnum.StartLine + DECL_WINDOW_LINES do
    begin
      if (L < 1) or (L > Length(Lines)) then Break;
      var Txt: string:= Lines[L - 1];
      if (L = AEnum.StartLine) and (AEnum.StartCol > 1) then Txt:= Copy(Txt, AEnum.StartCol, MaxInt);
      Result:= Result + Txt + sLineBreak;
    end;
  end;

  { The enum state of a type the INDEX knows by name: read once, cached. A
    name two enums share is ENUM_NONE (no guessing). }
  function StoreEnumState(const ALowerType: string): Integer;
  var
    Found: TArray<TSymbol>;
  begin
    if (AStore = nil) or (ALowerType = '') then Exit(ENUM_NONE);
    if StoreEnum.TryGetValue(ALowerType, Result) then Exit;
    Result:= ENUM_NONE;
    Found:= nil;
    for var S: TSymbol in AStore.FindSymbolsByExactName(ALowerType) do
      if (S.Kind = skEnum) and SameText(S.Name, ALowerType) then Found:= Found + [S];
    if Length(Found) = 1 then
    begin
      Result:= ENUM_FREE;
      if not ScopeFile.ContainsKey(ALowerType) then
      begin
        ScopeFile.Add(ALowerType, AStore.GetFilePath(Found[0].FileId));
        ScopeLine.AddOrSetValue(ALowerType, Found[0].StartLine);
      end;
      var Total: Integer;
      var Decl: string:= DeclTextOf(Found[0]);
      if (Decl <> '') and (CountImplicitOrdinals(Decl, Total) = 0) and (Total > 0) then Result:= ENUM_PINNED;
    end;
    StoreEnum.Add(ALowerType, Result);
  end;

  { ENUM_NONE when ALowerType is no enum, else whether its values are pinned. }
  function EnumState(const ALowerType: string): Integer;
  var
    Pinned: Boolean;
  begin
    if ALowerType = '' then Exit(ENUM_NONE);
    if EnumTypes.TryGetValue(ALowerType, Pinned) then Exit(if Pinned then ENUM_PINNED else ENUM_FREE);
    Result:= StoreEnumState(ALowerType);
  end;

  { The identifier a (dotted) name ends in; null for any other expression. }
  function LastIdent(const N: TTSNode): TTSNode;
  begin
    Result:= N;
    while not Result.IsNull and (Result.NodeType = 'exprParens') and (Result.NamedChildCount = 1) do
      Result:= Result.NamedChild(0);
    if Result.IsNull then Exit;
    if Result.NodeType = 'exprDot' then Result:= Result.ChildByField('rhs');
    if Result.IsNull or (Result.NodeType <> 'identifier') then Result:= Default(TTSNode);
  end;

  { The declared type in a symbol's signature (`pK: TKind` -> `tkind`). }
  function SigType(const ASym: TSymbol): string;
  begin
    Result:= ASym.Signature;
    var I: Integer:= Pos(':', Result);
    if I > 0 then Result:= Copy(Result, I + 1, MaxInt);
    I:= Pos('=', Result);
    if I > 0 then Result:= Copy(Result, 1, I - 1);
    I:= Pos(';', Result);
    if I > 0 then Result:= Copy(Result, 1, I - 1);
    Result:= BareLower(Result);
  end;

  { The lower enum TYPE name of an enum value expression -- an enum value, or a
    var / param / field declared of an enum type; '' when N is none of those. }
  function EnumTypeOfExpr(const N: TTSNode): string;
  var
    Ref: TReference;
  begin
    Result:= '';
    var Id: TTSNode:= LastIdent(N);
    if Id.IsNull then Exit;
    var Nm: string:= LowerCase(Trim(NodeStr(Id)));
    if (AStore <> nil) and RefAt(Id, Ref) then
    begin
      var Sym: TSymbol:= AStore.GetSymbolById(Ref.SymbolId);
      if Sym.Kind = skEnumValue then Exit(LowerCase(AStore.GetSymbolById(Sym.ParentId).Name));
      if Sym.Kind in [skEnum, skClass, skRecord, skInterface, skProcedure, skFunction, skMethod] then Exit;
      var St: string:= SigType(Sym);
      if EnumState(St) <> ENUM_NONE then Exit(St);
    end;
    if EnumValues.TryGetValue(Nm, Result) then Exit;
    var Ty: string;
    if DeclTypes.TryGetValue(Nm, Ty) and (EnumState(Ty) <> ENUM_NONE) then Result:= Ty;
  end;

  { The lower enum TYPE name a call's callee names (a cast to it); '' otherwise. }
  function EnumCastTarget(const AEntity: TTSNode): string;
  var
    Ref: TReference;
  begin
    Result:= '';
    var Id: TTSNode:= LastIdent(AEntity);
    if Id.IsNull then Exit;
    var Nm: string:= LowerCase(Trim(NodeStr(Id)));
    if (AStore <> nil) and RefAt(Id, Ref) then
    begin
      if AStore.GetSymbolById(Ref.SymbolId).Kind = skEnum then Result:= Nm;
      Exit;
    end;
    if EnumTypes.ContainsKey(Nm) then Result:= Nm;
  end;

  { A non-negative integer literal. A negative one (TKind(-1)) is an out-of-range
    sentinel, not any value's position, so reordering cannot change it. }
  function IsIntLiteral(const N: TTSNode): Boolean;
  begin
    if N.IsNull then Exit(False);
    if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then Exit(IsIntLiteral(N.NamedChild(0)));
    var Txt: string:= Trim(NodeStr(N));
    Result:= (N.NodeType = 'literalNumber') and not Txt.Contains('.') and not StartsStr('-', Txt);
  end;

  function SingleArg(const ACall: TTSNode): TTSNode;
  begin
    Result:= Default(TTSNode);
    var Args: TTSNode:= ACall.ChildByField('args');
    if not Args.IsNull and (Args.NamedChildCount = 1) then Result:= Args.NamedChild(0);
  end;

  { True for `Ord(E)` / `Integer(E)` / ... with E a value of an enum whose
    ordinals are NOT all pinned (`= N` makes a literal ordinal stable).
    AType: the lower enum type name (the finding's type scope); '' when False. }
  function IsOrdOfFreeEnum(const N: TTSNode; out AType: string): Boolean;
  begin
    Result:= False;
    AType := '';
    var X: TTSNode:= N;
    while not X.IsNull and (X.NodeType = 'exprParens') and (X.NamedChildCount = 1) do X:= X.NamedChild(0);
    if X.IsNull or (X.NodeType <> 'exprCall') then Exit;
    var Ent: TTSNode:= X.ChildByField('entity');
    if Ent.IsNull or (Ent.NodeType <> 'identifier') or not InList(Trim(NodeStr(Ent)), ORD_CASTS) then Exit;
    var Arg: TTSNode:= SingleArg(X);
    if Arg.IsNull then Exit;
    AType := EnumTypeOfExpr(Arg);
    Result:= EnumState(AType) = ENUM_FREE;
    if not Result then AType:= '';
  end;

  { ATypeLower: the enum type the finding is about -- its declaration becomes
    the finding's TYPE scope, where one dl:ok reviews every cast of it. }
  procedure EmitAt(const ANode: TTSNode; const ATypeLower, AMsg: string);
  var
    P: TTSPoint    ;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ENUM_ORDINAL_CAST_RULE;
    F.Severity := 'warning';
    F.Message  := AMsg;
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row   ) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
    F.EndCol   := Integer(ANode.EndPoint.Column) + 1;
    var Sf: string;
    var Sl: Integer;
    if ScopeFile.TryGetValue(ATypeLower, Sf) and ScopeLine.TryGetValue(ATypeLower, Sl) then
    begin
      F.ScopeFile:= Sf;
      F.ScopeLine:= Sl;
    end;
    Findings.Add(F);
  end;

  function CaseHasLiteralLabel(const ACase: TTSNode): Boolean;
  begin
    Result:= False;
    for var I: Integer:= 0 to ACase.NamedChildCount - 1 do
    begin
      var CC: TTSNode:= ACase.NamedChild(I);
      if CC.NodeType <> 'caseCase' then Continue;
      var Lbl: TTSNode:= CC.ChildByField('label');
      if Lbl.IsNull then Continue;
      for var J: Integer:= 0 to Lbl.NamedChildCount - 1 do
      begin
        var L: TTSNode:= Lbl.NamedChild(J);
        if IsIntLiteral(L) then Exit(True);
        if (L.NodeType = 'range') and (L.NamedChildCount > 0) and IsIntLiteral(L.NamedChild(0)) then Exit(True);
      end;
    end;
  end;

  { The case selector: the first named child that is neither a keyword nor a branch. }
  function CaseSelector(const ACase: TTSNode): TTSNode;
  begin
    Result:= Default(TTSNode);
    for var I: Integer:= 0 to ACase.NamedChildCount - 1 do
    begin
      var C: TTSNode:= ACase.NamedChild(I);
      if StartsStr('k', C.NodeType) or (C.NodeType = 'caseCase') then Continue;
      Exit(C);
    end;
  end;

  procedure Visit(const N: TTSNode);
  begin
    if N.IsNull then Exit;
    var T: string:= N.NodeType;
    if T = 'exprCall' then
    begin
      var Arg: TTSNode:= SingleArg(N);
      var Target: string:= EnumCastTarget(N.ChildByField('entity'));
      if IsIntLiteral(Arg) and (EnumState(Target) = ENUM_FREE) then
        EmitAt(N, Target, Format('%s hard-codes an enum ordinal -- inserting or reordering a value of %s ' +
          'silently changes which value this is. Name the value instead.',
          [Trim(NodeStr(N)), Trim(NodeStr(N.ChildByField('entity')))]));
    end
    else if T = 'exprBinary' then
    begin
      var Op: string:= Trim(NodeStr(N.ChildByField('operator')));
      if InList(Op, COMPARE_OPS) then
      begin
        var L: TTSNode:= N.ChildByField('lhs');
        var R: TTSNode:= N.ChildByField('rhs');
        var Side: TTSNode:= Default(TTSNode);
        var Ty: string:= '';
        if IsIntLiteral(R) and IsOrdOfFreeEnum(L, Ty) then Side:= L
        else if IsIntLiteral(L) and IsOrdOfFreeEnum(R, Ty) then Side:= R;
        if not Side.IsNull then
          EmitAt(N, Ty, Format('%s compares an enum ordinal with a literal -- inserting or reordering a ' +
            'value silently changes the meaning. Compare with the enum value itself.',
            [Trim(NodeStr(N))]));
      end;
    end
    else if T = 'case' then
    begin
      var Sel: TTSNode:= CaseSelector(N);
      var Ty: string:= '';
      if not Sel.IsNull and IsOrdOfFreeEnum(Sel, Ty) and CaseHasLiteralLabel(N) then
        EmitAt(N, Ty, Format('case %s of ... with literal labels hard-codes enum ordinals -- inserting or ' +
          'reordering a value silently changes which branch runs. Case on the enum value itself.',
          [Trim(NodeStr(Sel))]));
    end;
    for var I: Integer:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings  := TList<TLintFinding>.Create;
  EnumTypes := TDictionary<string, Boolean>.Create;
  EnumValues:= TDictionary<string, string>.Create;
  DeclTypes := TDictionary<string, string>.Create;
  RefByPos  := TDictionary<string, TReference>.Create;
  StoreEnum := TDictionary<string, Integer>.Create;
  ScopeFile := TDictionary<string, string>.Create;
  ScopeLine := TDictionary<string, Integer>.Create;
  try
    CollectDecls(PF.Tree.RootNode);
    if (AStore <> nil) and (AFileId > 0) then
      for var R: TReference in AStore.GetReferencesFromFile(AFileId) do
        RefByPos.AddOrSetValue(IntToStr(R.StartLine) + ':' + IntToStr(R.StartCol), R);
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    ScopeLine.Free;
    ScopeFile.Free;
    StoreEnum.Free;
    RefByPos.Free;
    DeclTypes.Free;
    EnumValues.Free;
    EnumTypes.Free;
    Findings.Free;
  end;
end;

end.
