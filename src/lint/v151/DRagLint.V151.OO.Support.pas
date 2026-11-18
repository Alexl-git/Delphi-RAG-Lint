unit DRagLint.V151.OO.Support;

{ Wave v151 lane OO -- checks of DRagLint.V151.OO (private to the lane).
  Every check reads the tree-sitter parse of ONE file (TAstParseCache) and
  decides on what that file says; nothing here needs the index. Evidence is
  positive only: a construct the file does not settle is left alone. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  ;

const
  /// <summary>Rule id: Equals override without GetHashCode override (or the reverse).</summary>
  EQUALS_HASH_RULE = 'equals-without-gethashcode';
  /// <summary>Rule id: an event field is called without a nil guard.</summary>
  EVENT_CALL_RULE = 'event-call-without-assigned';
  /// <summary>Rule id: two interfaces of one file carry the same GUID.</summary>
  DUP_GUID_RULE = 'duplicate-interface-guid';
  /// <summary>Rule id: an exported routine has no calling convention.</summary>
  DLL_EXPORT_RULE = 'dll-export-unsafe';
  /// <summary>Rule id: a money-named variable is a floating point type.</summary>
  MONEY_FLOAT_RULE = 'money-as-float';
  /// <summary>Rule id: a parameter carries a default value.</summary>
  DEFAULT_PARAM_RULE = 'default-parameter';
  /// <summary>Rule id: a property accessor only moves a field.</summary>
  TRIVIAL_ACCESSOR_RULE = 'trivial-accessor';
  /// <summary>Rule id: a forward declaration nothing before the full type needs.</summary>
  UNNEEDED_FORWARD_RULE = 'unneeded-forward-declaration';
  /// <summary>Rule id: non-generic TList / TObjectList items read through a cast.</summary>
  LEGACY_TLIST_RULE = 'legacy-tlist';
  /// <summary>Rule id: non-generic stack / queue items read through a cast.</summary>
  LEGACY_STACK_QUEUE_RULE = 'legacy-stack-queue';

/// <summary>Runs every lane-OO check that AWants asks for against one .pas file.</summary>
/// <param name="APath">The .pas file; unreadable or unparsable files give no finding.</param>
/// <param name="AWants">Tells whether a rule id is wanted by the run (honours --rule).</param>
/// <returns>All findings of the wanted rules; nil when none.</returns>
/// <remarks>Not thread-safe (shared parse cache). Findings are 1-based line / column.</remarks>
function OOCheckFile(const APath: string; const AWants: TFunc<string, Boolean>): TArray<TLintFinding>;

implementation

uses
  System.Classes
  , System.StrUtils
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

type
  TOOClassInfo = class
    Fields : TStringList;
    Getters: TDictionary<string, string>; { accessor lower -> property name }
    Setters: TDictionary<string, string>;
    Skip   : TStringList;                 { accessors with virtual / override / dynamic / message }
  end;

  TOOEvClass = class
    Aliases: TObjectDictionary<string, TStringList>; { event field lower -> names that reach it }
  end;

  TOOKind = (lkNone, lkList, lkStack);

  TOOScan = class  // dl:ok high-response@9b5f -- REVIEWED 2026-11-14 v151 INT: one scanner class holding the per-rule checks of one lane; a split is beyond 1.51
  strict private
    FPath : string;
    FSrc  : TBytes;
    FOut  : TList<TLintFinding>;
    function Txt(const ANode: TTSNode): string;
    function Low(const ANode: TTSNode): string;
    procedure Add(const ARule, ASeverity, AMsg: string; const ANode: TTSNode);
    procedure Gather(const ANode: TTSNode; const AKind: string; AList: TList<TTSNode>);
    function HasAttr(const AProc: TTSNode; const AWords: array of string): Boolean;
    function ArgCount(const AProc: TTSNode): Integer;
    function IsKeywordNode(const ANode: TTSNode): Boolean;
    function BodyStatements(const ABody: TTSNode): TArray<TTSNode>;
    function SimpleRef(const ANode: TTSNode): string;
    function ClassNameOfDecl(const AClass: TTSNode): string;
    procedure CheckEqualsHash(const AClasses: TList<TTSNode>);
    procedure CheckDupGuid(const ARoot: TTSNode);
    procedure CheckDllExport(const ARoot: TTSNode);
    procedure CheckMoney(const ARoot: TTSNode);
    procedure CheckDefaultParam(const ARoot: TTSNode);
    procedure CheckForward(const ARoot: TTSNode);
    procedure CheckTrivialAccessor(const ARoot: TTSNode; const AClasses: TList<TTSNode>);
    procedure CheckEventCall(const ARoot: TTSNode; const AClasses: TList<TTSNode>);
    procedure CheckLegacy(const ARoot: TTSNode; AList, AStack: Boolean);
  public
    constructor Create(const APath: string; const ASrc: TBytes);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode; const AWants: TFunc<string, Boolean>): TArray<TLintFinding>;
  end;

const
  MONEY_TOKENS: array[0..29] of string = ('price', 'preis', 'amount', 'betrag', 'cost', 'kosten', 'salary',
    'gehalt', 'balance', 'saldo', 'money', 'geld', 'wage', 'lohn', 'fee', 'gebuehr', 'invoice', 'rechnung',
    'vat', 'mwst', 'tax', 'steuer', 'revenue', 'umsatz', 'discount', 'rabatt', 'skonto', 'payment', 'zahlung',
    'currency');
  NOT_MONEY_TOKENS: array[0..13] of string = ('percent', 'pct', 'prozent', 'rate', 'factor', 'faktor',
    'ratio', 'count', 'anzahl', 'index', 'id', 'nr', 'number', 'type');
  FLOAT_TYPES: array[0..5] of string = ('double', 'single', 'extended', 'real', 'real48', 'comp');
  SAFE_CONVENTIONS: array[0..4] of string = ('stdcall', 'cdecl', 'safecall', 'winapi', 'pascal');
  EVENT_SUFFIXES: array[0..4] of string = ('event', 'notify', 'callback', 'handler', 'proc');
  LIST_ITEM_MEMBERS: array[0..3] of string = ('items', 'first', 'last', 'extract');
  STACK_ITEM_MEMBERS: array[0..3] of string = ('pop', 'peek', 'extract', 'first');

function OOCheckFile(const APath: string; const AWants: TFunc<string, Boolean>): TArray<TLintFinding>;
begin
  Result:= nil;
  var PF: TParsedFile:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit;
  var Scan:= TOOScan.Create(APath, PF.Src);
  try
    Result:= Scan.Run(PF.Tree.RootNode, AWants);
  finally
    Scan.Free;
  end;
end;

{ TOOScan }

constructor TOOScan.Create(const APath: string; const ASrc: TBytes);
begin
  inherited Create;
  FPath:= APath;
  FSrc := ASrc;
  FOut := TList<TLintFinding>.Create;
end;

destructor TOOScan.Destroy;
begin
  FOut.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-11-14 v151 INT: bare inherited calls the same-named ancestor method, intended
end;

function TOOScan.Txt(const ANode: TTSNode): string;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  var S: Integer:= Integer(ANode.StartByte);
  var L: Integer:= Integer(ANode.EndByte) - S;
  if (L > 0) and (S >= 0) and (S + L <= Length(FSrc)) then Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

function TOOScan.Low(const ANode: TTSNode): string;
begin
  Result:= LowerCase(Txt(ANode));
end;

procedure TOOScan.Add(const ARule, ASeverity, AMsg: string; const ANode: TTSNode);
begin
  var F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASeverity;
  F.FilePath := FPath;
  F.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, ANode.StartPoint); { 1.52 BK-COLS2: character column }
  F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  F.EndCol   := TAstParseCache.CharCol(F.FilePath, ANode.EndPoint); { 1.52 BK-COLS2: character column }
  F.Message  := AMsg;
  FOut.Add(F);
end;

procedure TOOScan.Gather(const ANode: TTSNode; const AKind: string; AList: TList<TTSNode>);
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = AKind then AList.Add(ANode);
  for var I: Integer:= 0 to ANode.NamedChildCount - 1 do
    Gather(ANode.NamedChild(I), AKind, AList);
end;

function TOOScan.HasAttr(const AProc: TTSNode; const AWords: array of string): Boolean;
begin
  Result:= False;
  for var I: Integer:= 0 to AProc.NamedChildCount - 1 do
  begin
    var C: TTSNode:= AProc.NamedChild(I);
    if C.NodeType <> 'procAttribute' then Continue;
    var T: string:= Low(C);
    for var W: string in AWords do
      if T = W then Exit(True);
  end;
end;

function CountChars(const AText: string; AChar: Char): Integer;
begin
  Result:= 0;
  for var C: Char in AText do
    if C = AChar then Inc(Result);
end;

function TOOScan.ArgCount(const AProc: TTSNode): Integer;
begin
  Result:= 0;
  var Args: TTSNode:= AProc.ChildByField('args');
  if Args.IsNull then Exit;
  for var I: Integer:= 0 to Args.NamedChildCount - 1 do
    if Args.NamedChild(I).NodeType = 'declArg' then
    begin
      var T: string:= Txt(Args.NamedChild(I));
      var Colon: Integer:= Pos(':', T);
      if Colon = 0 then Colon:= Length(T) + 1;
      Inc(Result, 1 + CountChars(Copy(T, 1, Colon - 1), ','));
    end;
end;

function TOOScan.IsKeywordNode(const ANode: TTSNode): Boolean;
begin
  var T: string:= ANode.NodeType;
  Result:= (Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']);
end;

function TOOScan.BodyStatements(const ABody: TTSNode): TArray<TTSNode>;
begin
  Result:= nil;
  if ABody.IsNull then Exit;
  for var I: Integer:= 0 to ABody.NamedChildCount - 1 do
    if not IsKeywordNode(ABody.NamedChild(I)) then Result:= Result + [ABody.NamedChild(I)];
end;

{ The name behind `F` or `Self.F` (lowercase), '' for anything else. }
function TOOScan.SimpleRef(const ANode: TTSNode): string;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  if ANode.NodeType = 'identifier' then Exit(Low(ANode));
  if ANode.NodeType = 'exprDot' then  // dl:ok collapsible-if@0a90 -- REVIEWED 2026-11-14 v151 INT: outer test guards a distinct shape; kept separate for the comment and later branches
  begin
    if Low(ANode.ChildByField('lhs')) = 'self' then Result:= Low(ANode.ChildByField('rhs'));
  end;
end;

function TOOScan.ClassNameOfDecl(const AClass: TTSNode): string;
begin
  Result:= '';
  var P: TTSNode:= AClass.Parent;
  while (not P.IsNull) and (P.NodeType <> 'declType') do P:= P.Parent;
  if not P.IsNull then Result:= Low(P.ChildByField('name'));
end;

procedure TOOScan.CheckEqualsHash(const AClasses: TList<TTSNode>);
begin
  for var Cls: TTSNode in AClasses do
  begin
    var Procs:= TList<TTSNode>.Create;
    try
      Gather(Cls, 'declProc', Procs);
      var EqNode : TTSNode:= Default(TTSNode);
      var HashNode: TTSNode:= Default(TTSNode);
      for var P: TTSNode in Procs do
      begin
        if not HasAttr(P, ['override']) then Continue;
        var N: string:= Low(P.ChildByField('name'));
        if (N = 'equals') and (ArgCount(P) = 1) then EqNode:= P.ChildByField('name')
        else if (N = 'gethashcode') and (ArgCount(P) = 0) then HashNode:= P.ChildByField('name');
      end;
      if (not EqNode.IsNull) and HashNode.IsNull then
        Add(EQUALS_HASH_RULE, 'warning', 'Equals is overridden but GetHashCode is not: two equal objects can '
          + 'then hash differently, so a TDictionary or THashSet with the default comparer misses them.', EqNode)
      else if EqNode.IsNull and not HashNode.IsNull then
        Add(EQUALS_HASH_RULE, 'warning', 'GetHashCode is overridden but Equals is not: the hash then says '
          + 'nothing about equality and the two disagree.', HashNode);
    finally
      Procs.Free;
    end;
  end;
end;

procedure TOOScan.CheckDupGuid(const ARoot: TTSNode);
begin
  var Intfs:= TList<TTSNode>.Create;
  var Seen := TDictionary<string, TTSNode>.Create;
  try
    Gather(ARoot, 'declIntf', Intfs);
    for var I: TTSNode in Intfs do
    begin
      var G: TTSNode:= I.ChildByField('guid');
      { a dispinterface shares the GUID of its dual interface by design (type-library units) }
      if G.IsNull or StartsStr('dispinterface', Low(I)) then Continue;
      var Key: string:= UpperCase(StringReplace(StringReplace(StringReplace(Txt(G), '''', '', [rfReplaceAll]),
        '[', '', [rfReplaceAll]), ']', '', [rfReplaceAll])).Trim;
      if Key = '' then Continue;
      var First: TTSNode;
      if Seen.TryGetValue(Key, First) then
        Add(DUP_GUID_RULE, 'warning', Format('This interface has the same GUID as the one declared at line %d; '
          + 'Supports and as cannot tell the two apart. Give one of them a new GUID.',
          [Integer(First.StartPoint.Row) + 1]), G)
      else
        Seen.Add(Key, G);
    end;
  finally
    Seen.Free;
    Intfs.Free;
  end;
end;

procedure TOOScan.CheckDllExport(const ARoot: TTSNode);
begin
  var Exps:= TList<TTSNode>.Create;
  var Procs  := TList<TTSNode>.Create;
  try
    Gather(ARoot, 'declExport', Exps);
    if Exps.Count = 0 then Exit;
    Gather(ARoot, 'declProc', Procs);
    for var E: TTSNode in Exps do
    begin
      if E.NamedChildCount = 0 then Continue;
      var Name: string:= Low(E.NamedChild(0));
      var Found: Boolean:= False;
      var Safe : Boolean:= False;
      for var P: TTSNode in Procs do
      begin
        var PN: TTSNode:= P.ChildByField('name');
        if (PN.NodeType <> 'identifier') or (Low(PN) <> Name) then Continue;
        Found:= True;
        if HasAttr(P, SAFE_CONVENTIONS) then Safe:= True;
      end;
      if Found and not Safe then
        Add(DLL_EXPORT_RULE, 'warning', Format('Exported routine %s has no calling convention. The default '
          + '(register) is not part of any DLL contract; add stdcall, cdecl or safecall, and pass strings '
          + 'as PChar or WideString.', [Txt(E.NamedChild(0))]), E);
    end;
  finally
    Procs.Free;
    Exps.Free;
  end;
end;

{ camelCase / underscore split of a name into lowercase tokens }
function NameTokens(const AName: string): TArray<string>;
begin
  Result:= nil;
  var Cur: string:= '';
  for var I: Integer:= 1 to Length(AName) do
  begin
    var C: Char:= AName[I];
    if (C = '_') or (CharInSet(C, ['A'..'Z']) and (Cur <> '') and not CharInSet(AName[I - 1], ['A'..'Z'])) then
    begin
      if Cur <> '' then Result:= Result + [LowerCase(Cur)];
      Cur:= '';
      if C = '_' then Continue;
    end;
    Cur:= Cur + C;  // dl:ok concat-in-loop@1bce -- REVIEWED 2026-11-14 v151 INT: a few short pieces per call, not an accumulating large string
  end;
  if Cur <> '' then Result:= Result + [LowerCase(Cur)];
end;

procedure TOOScan.CheckMoney(const ARoot: TTSNode);
const
  DECL_KINDS: array[0..3] of string = ('declField', 'declVar', 'declArg', 'declProp');
begin
  var List:= TList<TTSNode>.Create;
  try
    for var K: string in DECL_KINDS do Gather(ARoot, K, List);
    for var D: TTSNode in List do
    begin
      var NameN: TTSNode:= D.ChildByField('name');
      var TypeN: TTSNode:= D.ChildByField('type');
      if NameN.IsNull or TypeN.IsNull then Continue;
      var Ty: string:= Low(TypeN);
      if not MatchStr(Ty, FLOAT_TYPES) then Continue;
      var Money: Boolean:= False;
      var Other: Boolean:= False;
      for var Tok: string in NameTokens(Txt(NameN)) do
      begin
        if MatchStr(Tok, NOT_MONEY_TOKENS) then Other:= True;
        for var M: string in MONEY_TOKENS do
          if Tok = M then Money:= True;
      end;
      if Money and not Other then
        Add(MONEY_FLOAT_RULE, 'warning', Format('%s holds a money amount as %s. Binary floating point cannot '
          + 'represent most cent values; use Currency (or a scaled Int64 / decimal type).',
          [Txt(NameN), Txt(TypeN)]), NameN);
    end;
  finally
    List.Free;
  end;
end;

procedure TOOScan.CheckDefaultParam(const ARoot: TTSNode);
begin
  var List:= TList<TTSNode>.Create;
  try
    Gather(ARoot, 'declArg', List);
    for var A: TTSNode in List do
    begin
      var D: TTSNode:= A.ChildByField('defaultValue');
      if D.IsNull then Continue;
      Add(DEFAULT_PARAM_RULE, 'hint', Format('Parameter %s has a default value. The value is compiled into every '
        + 'caller; an overload keeps it in one place and can be changed without recompiling callers.',
        [Txt(A.ChildByField('name'))]), D);
    end;
  finally
    List.Free;
  end;
end;

procedure TOOScan.CheckForward(const ARoot: TTSNode);  // dl:ok deep-nesting@484e -- REVIEWED 2026-11-14 v151 INT: tree walk with per-shape branches; flattening would scatter one rule
begin
  var Blocks:= TList<TTSNode>.Create;
  try
    Gather(ARoot, 'declTypes', Blocks);
    for var B: TTSNode in Blocks do
    begin
      var Decls: TArray<TTSNode>:= nil;
      for var I: Integer:= 0 to B.NamedChildCount - 1 do
        if B.NamedChild(I).NodeType = 'declType' then Decls:= Decls + [B.NamedChild(I)];
      for var I: Integer:= 0 to High(Decls) do
      begin
        var TypeN: TTSNode:= Decls[I].ChildByField('type');
        if TypeN.IsNull then Continue;
        var Body: TTSNode:= TypeN;
        if (Body.NodeType = 'type') and (Body.NamedChildCount = 1) then Body:= Body.NamedChild(0);
        var IsFwd: Boolean:= ((Body.NodeType = 'declClass') or (Body.NodeType = 'declIntf'))
          and (Body.NamedChildCount = 1) and IsKeywordNode(Body.NamedChild(0));
        if not IsFwd then Continue;
        var Name: string:= Low(Decls[I].ChildByField('name'));
        var Full: Integer:= -1;
        for var J: Integer:= I + 1 to High(Decls) do
          if Low(Decls[J].ChildByField('name')) = Name then
          begin
            var T2: TTSNode:= Decls[J].ChildByField('type');
            var B2: TTSNode:= T2;
            if (B2.NodeType = 'type') and (B2.NamedChildCount = 1) then B2:= B2.NamedChild(0);
            if (B2.NodeType = 'declClass') or (B2.NodeType = 'declIntf') then  // dl:ok collapsible-if@8d7f -- REVIEWED 2026-11-14 v151 INT: outer test guards a distinct shape; kept separate for the comment and later branches
              if not ((B2.NamedChildCount = 1) and IsKeywordNode(B2.NamedChild(0))) then Full:= J;
            Break;
          end;
        if Full < 0 then Continue;
        { any mention of the name between the forward and the full declaration keeps the forward needed }
        var Used: Boolean:= False;
        for var J: Integer:= I + 1 to Full - 1 do
        begin
          var Ids:= TList<TTSNode>.Create;
          try
            Gather(Decls[J], 'identifier', Ids);
            for var Id: TTSNode in Ids do
              if Low(Id) = Name then Used:= True;
          finally
            Ids.Free;
          end;
          if Used then Break;
        end;
        if not Used then
          Add(UNNEEDED_FORWARD_RULE, 'hint', Format('Forward declaration of %s is not needed: nothing between it and '
            + 'the full declaration (line %d) mentions the type. Remove it.',
            [Txt(Decls[I].ChildByField('name')), Integer(Decls[Full].StartPoint.Row) + 1]), Decls[I]);
      end;
    end;
  finally
    Blocks.Free;
  end;
end;

procedure TOOScan.CheckTrivialAccessor(const ARoot: TTSNode; const AClasses: TList<TTSNode>);
var
  Infos: TObjectDictionary<string, TOOClassInfo>;
begin
  Infos:= TObjectDictionary<string, TOOClassInfo>.Create([doOwnsValues]);
  var Defs:= TList<TTSNode>.Create;
  try
    for var Cls: TTSNode in AClasses do
    begin
      var CN: string:= ClassNameOfDecl(Cls);
      if CN = '' then Continue;
      var Info:= TOOClassInfo.Create;
      Info.Fields := TStringList.Create;
      Info.Getters:= TDictionary<string, string>.Create;
      Info.Setters:= TDictionary<string, string>.Create;
      Info.Skip   := TStringList.Create;
      Infos.AddOrSetValue(CN, Info);
      var Fs:= TList<TTSNode>.Create;
      var Ps:= TList<TTSNode>.Create;
      var Ms:= TList<TTSNode>.Create;
      try
        Gather(Cls, 'declField', Fs);
        Gather(Cls, 'declProp', Ps);
        Gather(Cls, 'declProc', Ms);
        for var F: TTSNode in Fs do Info.Fields.Add(Low(F.ChildByField('name')));
        for var P: TTSNode in Ps do
        begin
          var G: TTSNode:= P.ChildByField('getter');
          var S: TTSNode:= P.ChildByField('setter');
          if not G.IsNull then Info.Getters.AddOrSetValue(Low(G), Txt(P.ChildByField('name')));
          if not S.IsNull then Info.Setters.AddOrSetValue(Low(S), Txt(P.ChildByField('name')));
        end;
        for var M: TTSNode in Ms do
          if HasAttr(M, ['virtual', 'override', 'dynamic', 'message', 'abstract']) then
            Info.Skip.Add(Low(M.ChildByField('name')));
      finally
        Ms.Free;
        Ps.Free;
        Fs.Free;
      end;
    end;
    Gather(ARoot, 'defProc', Defs);
    for var D: TTSNode in Defs do
    begin
      var H: TTSNode:= D.ChildByField('header');
      if H.IsNull then Continue;
      var NameN: TTSNode:= H.ChildByField('name');
      if NameN.NodeType <> 'genericDot' then Continue;
      var Info: TOOClassInfo;
      if not Infos.TryGetValue(Low(NameN.ChildByField('lhs')), Info) then Continue;
      var Meth: string:= Low(NameN.ChildByField('rhs'));
      if Info.Skip.IndexOf(Meth) >= 0 then Continue;
      var Stm: TArray<TTSNode>:= BodyStatements(D.ChildByField('body'));
      if Length(Stm) <> 1 then Continue;
      var S: TTSNode:= Stm[0];
      if S.NodeType <> 'assignment' then Continue;
      var PropName: string;
      if Info.Getters.TryGetValue(Meth, PropName) and (ArgCount(H) = 0) then
      begin
        if (Low(S.ChildByField('lhs')) = 'result') and (Info.Fields.IndexOf(SimpleRef(S.ChildByField('rhs'))) >= 0) then
          Add(TRIVIAL_ACCESSOR_RULE, 'hint', Format('Getter %s only returns field %s. Let property %s read the '
            + 'field directly (read %s) and drop the method.',
            [Txt(NameN.ChildByField('rhs')), Txt(S.ChildByField('rhs')), PropName, Txt(S.ChildByField('rhs'))]),
            NameN.ChildByField('rhs'));
      end
      else if Info.Setters.TryGetValue(Meth, PropName) and (ArgCount(H) = 1) then
      begin
        var Args: TTSNode:= H.ChildByField('args');
        var PName: string:= '';
        if (not Args.IsNull) and (Args.NamedChildCount > 0) then PName:= Low(Args.NamedChild(0).ChildByField('name'));
        if (PName <> '') and (Low(S.ChildByField('rhs')) = PName)
          and (Info.Fields.IndexOf(SimpleRef(S.ChildByField('lhs'))) >= 0) then
          Add(TRIVIAL_ACCESSOR_RULE, 'hint', Format('Setter %s only assigns field %s. Let property %s write the '
            + 'field directly (write %s) and drop the method.',
            [Txt(NameN.ChildByField('rhs')), Txt(S.ChildByField('lhs')), PropName, Txt(S.ChildByField('lhs'))]),
            NameN.ChildByField('rhs'));
      end;
    end;
  finally
    Defs.Free;
    Infos.Free;
  end;
end;

procedure TOOScan.CheckEventCall(const ARoot: TTSNode; const AClasses: TList<TTSNode>);
var
  Procedural: TStringList;
  Infos     : TObjectDictionary<string, TOOEvClass>;

  function IsEventType(const ATypeLow: string): Boolean;
  begin
    if Procedural.IndexOf(ATypeLow) >= 0 then Exit(True);
    Result:= False;
    var T: string:= ATypeLow;
    if (Length(T) > 2) and (T[1] = 't') then
      for var S: string in EVENT_SUFFIXES do
        if EndsStr(S, T) then Exit(True);
  end;

begin
  Procedural:= TStringList.Create;
  Infos     := TObjectDictionary<string, TOOEvClass>.Create([doOwnsValues]);
  var Defs  := TList<TTSNode>.Create;
  var TypeDs:= TList<TTSNode>.Create;
  try
    Gather(ARoot, 'declType', TypeDs);
    for var TD: TTSNode in TypeDs do
    begin
      var T: string:= Low(TD.ChildByField('type'));
      if (StartsStr('procedure', T) or StartsStr('function', T) or StartsStr('reference', T))
        and (ContainsStr(T, 'of object') or StartsStr('reference', T)) then
        Procedural.Add(Low(TD.ChildByField('name')));
    end;
    for var Cls: TTSNode in AClasses do
    begin
      var CN: string:= ClassNameOfDecl(Cls);
      if CN = '' then Continue;
      var Info:= TOOEvClass.Create;
      Info.Aliases:= TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
      Infos.AddOrSetValue(CN, Info);
      var Fs:= TList<TTSNode>.Create;
      var Ps:= TList<TTSNode>.Create;
      try
        Gather(Cls, 'declField', Fs);
        Gather(Cls, 'declProp', Ps);
        for var F: TTSNode in Fs do
          if IsEventType(Low(F.ChildByField('type'))) then
          begin
            var L:= TStringList.Create;
            L.Add(Low(F.ChildByField('name')));
            Info.Aliases.AddOrSetValue(Low(F.ChildByField('name')), L);
          end;
        for var P: TTSNode in Ps do
        begin
          var G: TTSNode:= P.ChildByField('getter');
          var L: TStringList;
          if (not G.IsNull) and Info.Aliases.TryGetValue(Low(G), L) then L.Add(Low(P.ChildByField('name')));
        end;
      finally
        Ps.Free;  // dl:ok duplicate-code@a44b -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
        Fs.Free;
      end;
    end;
    Gather(ARoot, 'defProc', Defs);
    for var D: TTSNode in Defs do
    begin
      var H: TTSNode:= D.ChildByField('header');
      if H.IsNull then Continue;
      var NameN: TTSNode:= H.ChildByField('name');
      if NameN.NodeType <> 'genericDot' then Continue;
      var Info: TOOEvClass;
      if not Infos.TryGetValue(Low(NameN.ChildByField('lhs')), Info) then Continue;
      var Body: TTSNode:= D.ChildByField('body');
      if Body.IsNull then Continue;
      var Flat: string:= StringReplace(StringReplace(StringReplace(Low(Body), ' ', '', [rfReplaceAll]), #13, '', [rfReplaceAll]),
        #10, '', [rfReplaceAll]);
      var Stmts:= TList<TTSNode>.Create;
      try
        Gather(Body, 'statement', Stmts);
        for var S: TTSNode in Stmts do
        begin
          if S.NamedChildCount <> 1 then Continue;
          var C: TTSNode:= S.NamedChild(0);
          var Ref: string:= '';
          if C.NodeType = 'exprCall' then Ref:= SimpleRef(C.ChildByField('entity'))
          else if C.NodeType = 'identifier' then Ref:= Low(C);
          if Ref = '' then Continue;
          for var Pair in Info.Aliases do
            if Pair.Value.IndexOf(Ref) >= 0 then
            begin
              var Guarded: Boolean:= False;
              for var A: string in Pair.Value do
                if ContainsStr(Flat, 'assigned(' + A + ')') or ContainsStr(Flat, 'assigned(self.' + A + ')')  // dl:ok boolean-expression-complexity@1e5d -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
                  or ContainsStr(Flat, A + '<>nil') or ContainsStr(Flat, A + '=nil')
                  or ContainsStr(Flat, 'nil<>' + A) or ContainsStr(Flat, 'nil=' + A)
                  or ContainsStr(Flat, 'self.' + A + '<>nil') or ContainsStr(Flat, 'self.' + A + '=nil') then
                  Guarded:= True;
              var EvName: string:= Txt(if C.NodeType = 'identifier' then C else C.ChildByField('entity'));
              if not Guarded then
                Add(EVENT_CALL_RULE, 'warning', Format('Event %s is called without checking that a handler is '
                  + 'assigned; with no handler this raises an access violation. Wrap the call in '
                  + 'if Assigned(%s) then.', [EvName, EvName]), C);
            end;
        end;
      finally
        Stmts.Free;
      end;
    end;
  finally
    TypeDs.Free;
    Defs.Free;
    Infos.Free;
    Procedural.Free;
  end;
end;

procedure TOOScan.CheckLegacy(const ARoot: TTSNode; AList, AStack: Boolean);
var
  Kinds: TDictionary<string, TOOKind>;

  function KindOfType(const ATypeLow: string): TOOKind;
  begin
    var T: string:= ATypeLow;
    if StartsStr('system.classes.', T) then T:= Copy(T, 16, MaxInt);  // dl:ok magic-literal@9a1a -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    if StartsStr('system.contnrs.', T) then T:= Copy(T, 16, MaxInt);  // dl:ok magic-literal@d20b -- REVIEWED 2026-11-14 v151 INT: a spec value / fixed offset or length read at its single use site; a named constant adds nothing
    if (T = 'tlist') or (T = 'tobjectlist') then Exit(lkList);
    if (T = 'tstack') or (T = 'tqueue') or (T = 'tobjectstack') or (T = 'tobjectqueue') then Exit(lkStack);
    Result:= lkNone;
  end;

  { the container name a cast argument reads from, with the accessed member }
  function Source(const AArg: TTSNode; out AMember: string): string;
  begin
    Result:= '';
    AMember:= '';
    if AArg.IsNull then Exit;
    if AArg.NodeType = 'exprSubscript' then
    begin
      var E: TTSNode:= AArg.ChildByField('entity');
      if E.NodeType = 'exprDot' then
      begin
        if Low(E.ChildByField('rhs')) <> 'items' then Exit;
        Result:= SimpleRef(E.ChildByField('lhs'));
        AMember:= 'items';
      end
      else
      begin
        Result:= SimpleRef(E);
        AMember:= 'items';
      end;
    end
    else if AArg.NodeType = 'exprDot' then
    begin
      Result:= SimpleRef(AArg.ChildByField('lhs'));
      AMember:= Low(AArg.ChildByField('rhs'));
    end;
  end;

  procedure Judge(const AArg, AReport: TTSNode);
  begin
    var Member: string;
    var Src: string:= Source(AArg, Member);
    if Src = '' then Exit;
    var K: TOOKind;
    if not Kinds.TryGetValue(Src, K) then Exit;
    if (K = lkList) and AList and MatchStr(Member, LIST_ITEM_MEMBERS) then
      Add(LEGACY_TLIST_RULE, 'hint', Format('Items of the non-generic list %s are read through a cast. Use '
        + 'TList<T> or TObjectList<T> so the element type is checked by the compiler.', [Txt(AArg)]), AReport)
    else if (K = lkStack) and AStack and MatchStr(Member, STACK_ITEM_MEMBERS) then
      Add(LEGACY_STACK_QUEUE_RULE, 'hint', Format('Items of the non-generic stack or queue are read through a '
        + 'cast (%s). Use TStack<T>, TQueue<T> or their object variants.', [Txt(AArg)]), AReport);
  end;

begin
  Kinds:= TDictionary<string, TOOKind>.Create;
  var Decls:= TList<TTSNode>.Create;
  var Calls:= TList<TTSNode>.Create;
  var Bins := TList<TTSNode>.Create;
  try
    for var K: string in ['declField', 'declVar', 'declArg'] do Gather(ARoot, K, Decls);
    for var D: TTSNode in Decls do
    begin
      var N: string:= Low(D.ChildByField('name'));
      if N = '' then Continue;
      var TN: TTSNode:= D.ChildByField('type');
      var Kd: TOOKind:= if TN.IsNull then lkNone else KindOfType(Low(TN));
      var Old: TOOKind;
      if Kinds.TryGetValue(N, Old) and (Old <> Kd) then Kd:= lkNone;
      Kinds.AddOrSetValue(N, Kd);
    end;
    Gather(ARoot, 'exprCall', Calls);
    for var C: TTSNode in Calls do
    begin
      var E: TTSNode:= C.ChildByField('entity');
      if E.NodeType <> 'identifier' then Continue;
      var En: string:= Txt(E);
      if not ((Length(En) > 1) and (En[1] = 'T') and CharInSet(En[2], ['A'..'Z'])) then Continue;
      var Args: TTSNode:= C.ChildByField('args');
      if Args.IsNull or (Args.NamedChildCount <> 1) then Continue;
      Judge(Args.NamedChild(0), C);
    end;
    Gather(ARoot, 'exprBinary', Bins);
    for var B: TTSNode in Bins do
      if B.ChildByField('operator').NodeType = 'kAs' then Judge(B.ChildByField('lhs'), B);
  finally
    Bins.Free;
    Calls.Free;
    Decls.Free;
    Kinds.Free;
  end;
end;

function TOOScan.Run(const ARoot: TTSNode; const AWants: TFunc<string, Boolean>): TArray<TLintFinding>;
begin
  var Classes:= TList<TTSNode>.Create;
  try
    Gather(ARoot, 'declClass', Classes);
    if AWants(EQUALS_HASH_RULE) then CheckEqualsHash(Classes);
    if AWants(DUP_GUID_RULE) then CheckDupGuid(ARoot);
    if AWants(DLL_EXPORT_RULE) then CheckDllExport(ARoot);
    if AWants(MONEY_FLOAT_RULE) then CheckMoney(ARoot);
    if AWants(DEFAULT_PARAM_RULE) then CheckDefaultParam(ARoot);
    if AWants(UNNEEDED_FORWARD_RULE) then CheckForward(ARoot);
    if AWants(TRIVIAL_ACCESSOR_RULE) then CheckTrivialAccessor(ARoot, Classes);
    if AWants(EVENT_CALL_RULE) then CheckEventCall(ARoot, Classes);
    if AWants(LEGACY_TLIST_RULE) or AWants(LEGACY_STACK_QUEUE_RULE) then
      CheckLegacy(ARoot, AWants(LEGACY_TLIST_RULE), AWants(LEGACY_STACK_QUEUE_RULE));
  finally
    Classes.Free;
  end;
  Result:= FOut.ToArray;
end;

end.
