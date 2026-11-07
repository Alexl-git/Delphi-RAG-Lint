unit DRagLint.Lint.ReadNeverAssigned;

{ The `read-never-assigned` project rule (owner request #5b, 1.40 lane flow).

  A field or a global variable that something READS but that nothing anywhere
  in the project ever assigns or creates: every read sees the default value
  (0 / nil / empty). The per-file `referenced-never-set` covers private fields
  inside one unit; this rule covers every field and every global, project-wide,
  so it runs only where the whole index is in scope (lint-all / lint-project).

  Evidence of a write, any one of which silences the symbol:
    * a 'write' ref bound to it (`X := v`, `Self.X := v`, `with O do X := v`,
      an initialization-section assignment);
    * a bound read / member-access ref whose source text is followed by `:=`
      (after any `[..]` / `.member` / `^` chain): `O.X := v` and the ref-gap G5
      hard cast `T(P).X := v`;
    * the symbol passed as an argument where the callee may take it by var /
      out: an RTL intrinsic (SetLength, Inc, Val, ...), a routine of the project
      or the platform library with a var / out parameter at that position, or a
      callee the indexes do not know at all. A call the resolver bound to a
      routine answers from THAT routine's overload set only (owner ruling D6);
      the bare-name merge across project + library is the fallback for an
      unbound call;
    * its address taken (`@X`);
    * an UNBOUND ref of the same name that writes by any of the shapes above
      (the resolver left it unbound -- a write through it may be this symbol);
    * a property naming it as its `write` accessor;
    * a global declared with an initialiser (`G: Integer = 7`), declared
      `absolute`, or the target of an `absolute` alias.
  Never candidates: typed constants (they are initialised), record fields (a
  record is filled whole -- `R := F()`, a stream read, FillChar), published
  fields and the fields of a class's default-visibility section (the form
  loader streams them from the DFM). }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>The rule id, as `rules --json`, `--rule` and dl:ok markers spell it.</summary>
  READ_NEVER_ASSIGNED_RULE = 'read-never-assigned';

/// <summary>Runs the rule over a project index.</summary>
/// <param name="AStore">The project index; nil yields no findings.</param>
/// <param name="ALibStore">The platform library index, or nil. It answers
/// whether a library callee takes an argument by var / out; with nil a callee
/// the project does not declare counts as a possible write (no finding).</param>
/// <returns>One 'read-never-assigned' warning per field or global variable
/// that a ref READS and that has no write evidence anywhere in the project (see
/// the unit comment for the evidence and the exempt shapes), anchored at the
/// symbol's declaration.</returns>
/// <remarks>
/// An UNBOUND write of a field's name (a receiver the resolver could not bind) silences the name
/// project-wide, except that when ref_receivers and ref_types give the receiver a known static type
/// that is neither the field's class nor a relative of it (type_ancestors, both directions), that
/// write no longer counts. An unknown receiver, an undecidable ancestry, a global, or an index
/// without those tables keeps the name-only rule.
/// Reads refs file by file (one query per file), and the source text
/// only of the files that hold a still-undecided ref or a would-be finding's
/// declaration. A source file that cannot be read, or whose text no longer
/// matches the index at a ref, counts as a write: the rule errs towards
/// silence.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: CompareText, ContainsText, Copy, Default, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByKind, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile, DRagLint.Lint.ReadNeverAssigned.CollectReadNeverAssigned.AddCandidate, DRagLint.Lint.ReadNeverAssigned.CollectReadNeverAssigned.GlobalExempt, DRagLint.Lint.ReadNeverAssigned.CollectReadNeverAssigned.NoteUnboundWrite (+17 more)</para>
/// <para>Returns: nil; Findings.ToArray</para>
/// <para>Complexity: 26 (cyclomatic, outer body), 281 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByKind"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetReferencesFromFile"/>
/// <seealso cref="DRagLint.Lint.ReadNeverAssigned.CollectReadNeverAssigned.AddCandidate"/>
/// <seealso cref="DRagLint.Lint.ReadNeverAssigned.CollectReadNeverAssigned.GlobalExempt"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectReadNeverAssigned(const AStore, ALibStore: ISymbolStore): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.Math
  , System.IOUtils
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param  // dl:ok unused-unit-in-uses@c61d -- REVIEWED 2026-11-06: needed to expand the inline TFDParam setters (removing it gives H2443); no identifier names it
  , DRagLint.Storage.SQLite
  , DRagLint.Lint.RefTypeRules
  ;

const
  REF_WRITE        = 'write';
  REF_READ          = 'read';
  REF_MEMBER_ACCESS = 'member-access';
  REF_CALL          = 'call';
  KIND_FIELD        = 'field';
  KIND_VAR          = 'var';
  KIND_PROPERTY     = 'property';
  VIS_PUBLISHED     = 'published';
  ANY_ARG           = -1;
  NO_POS            = -1;    { BeforeReceiver: the brackets do not balance }
  CALLEE_UNKNOWN    = 0;     { nothing declares the name }
  CALLEE_ROUTINE    = 1;
  CALLEE_OTHER      = 2;     { a type (a cast) or another non-routine }
  DECL_LOOKAHEAD    = 3;     { lines a declaration may span to its ';' }
  WS                = [' ', #9, #10, #13];
  IDENT_START       = ['A'..'Z', 'a'..'z', '_'];
  IDENT_PART        = ['A'..'Z', 'a'..'z', '_', '0'..'9'];

  { The compiler intrinsics / RTL routines that take an argument by var / out,
    as 'name:index' (index ANY_ARG: every argument). They have no declaration
    an index could answer from. }
  VAR_INTRINSICS: array[0..29] of string = (
    'setlength:0', 'inc:0', 'dec:0', 'include:0', 'exclude:0', 'initialize:0', 'finalize:0',
    'fillchar:0', 'move:1', 'str:1', 'val:1', 'val:2', 'insert:1', 'delete:0', 'new:0', 'getmem:0',
    'reallocmem:0', 'setstring:0', 'read:-1', 'readln:-1', 'blockread:-1', 'assignfile:0', 'reset:0',
    'rewrite:0', 'atomicincrement:0', 'atomicdecrement:0', 'atomicexchange:0', 'atomiccmpexchange:0', 'settextbuf:0', 'settextbuf:1');

  { A word before `(` that makes it a grouping, not a call. }
  NOT_CALLEES: array[0..18] of string = (
    'if', 'while', 'until', 'and', 'or', 'not', 'xor', 'div', 'mod', 'in', 'case', 'of', 'then',
    'do', 'to', 'downto', 'else', 'is', 'as');

type
  { One source file as a single string, with the offset of each line start. }
  TSrcText = class
  private
    FText  : string;
    FStarts: TArray<Integer>;
  public
    property Text: string read FText;
    property Starts: TArray<Integer> read FStarts;
    constructor Create(const ALines: TArray<string>);
    /// <summary>1-based offset of (ALine, ACol), or 0 when out of range.</summary>
    function OffsetOf(ALine, ACol: Integer): Integer;
  end;

  TWriteVerdict = (wvRead, wvWrite);

  TCollector = class  // dl:ok high-response@dfb5 -- REVIEWED 2026-11-03 one private text-classifier for one rule; RFC 51 counts RTL dictionary/string calls, the 1-over is BoundCallee (RNA-BARENAME)
  private
    FStore, FLib : ISymbolStore;
    FTexts       : TObjectDictionary<Int64, TSrcText>;
    FCalleeModes : TDictionary<string, TArray<Boolean>>;  { lower callee -> union of var/out per index }
    FCalleeKnown : TDictionary<string, Integer>;          { lower callee -> 0 unknown, 1 routine, 2 non-routine }
    FIntrinsics  : TDictionary<string, Boolean>;          { 'name:index' }
    FNotCallees  : TDictionary<string, Boolean>;
    FBoundCalls  : TObjectDictionary<Int64, TDictionary<Integer, Int64>>;  { file -> callee-name offset -> bound symbol id }
    FBoundModes  : TDictionary<Int64, TArray<Boolean>>;   { bound routine id -> var/out per index of its overload set }
    FBoundIsCall : TDictionary<Int64, Boolean>;           { bound symbol id -> is a routine }
    function TextOf(AFileId: Int64): TSrcText;
    function ArgIsVar(const ACallee: string; AIndex: Integer): Boolean;
    procedure LearnCallee(const ACallee, ALower: string);
    function BoundCallee(AFileId: Int64; ASrc: TSrcText; AOffset: Integer; out AModes: TArray<Boolean>): Boolean;
    function ArgVerdict(AFileId: Int64; ASrc: TSrcText; B: Integer): TWriteVerdict;
  public
    constructor Create(const AStore, ALibStore: ISymbolStore);
    destructor Destroy; override;
    /// <summary>Whether the ref at its source position writes (or may write) the
    /// name it spells. An unreadable or drifted file answers wvWrite.</summary>
    function Classify(const ARef: TReference): TWriteVerdict;
    /// <summary>The declaration text after the symbol's name up to its ';'
    /// (at most DECL_LOOKAHEAD lines), lower-cased; '' when unreadable.</summary>
    function DeclTail(const ASym: TSymbol): string;
    /// <summary>The symbol's whole declaration line, lower-cased; '' when unreadable.</summary>
    function DeclLine(const ASym: TSymbol): string;
    /// <summary>The lower-cased `write` accessor a property declaration names, or ''.</summary>
    function WriteAccessor(const AProp: TSymbol): string;
  end;

{ ---- TSrcText ----------------------------------------------------------- }

constructor TSrcText.Create(const ALines: TArray<string>);
var
  SB: TStringBuilder;
  I : Integer;
begin
  inherited Create;
  SetLength(FStarts, Length(ALines));
  SB:= TStringBuilder.Create;
  try
    for I:= 0 to High(ALines) do
    begin
      FStarts[I]:= SB.Length + 1;
      SB.Append(ALines[I]).Append(#10);
    end;
    FText:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSrcText.OffsetOf(ALine, ACol: Integer): Integer;
begin
  Result:= 0;
  if (ALine < 1) or (ALine > Length(Starts)) or (ACol < 1) then Exit;
  Result:= Starts[ALine - 1] + ACol - 1;
  if Result > Length(Text) then Result:= 0;
end;

{ ---- scanning helpers --------------------------------------------------- }

function SkipWsFwd(const S: string; P: Integer): Integer;
begin
  Result:= P;
  while (Result <= Length(S)) and CharInSet(S[Result], WS) do Inc(Result);
end;

function SkipWsBack(const S: string; P: Integer): Integer;
begin
  Result:= P;
  while (Result >= 1) and CharInSet(S[Result], WS) do Dec(Result);
end;

{ Position just past the bracket that closes the one opening at P ('[' or '('). }
function SkipBalancedFwd(const S: string; P: Integer): Integer;
var
  Depth: Integer;
begin
  Depth:= 0;
  Result:= P;
  while Result <= Length(S) do
  begin
    case S[Result] of
      '[', '(': Inc(Depth);
      ']', ')':
        begin
          Dec(Depth);
          if Depth = 0 then Exit(Result + 1);
        end;
      '''':
        begin
          Inc(Result);
          while (Result <= Length(S)) and (S[Result] <> '''') do Inc(Result);
        end;
    end;
    Inc(Result);
  end;
end;

{ Position of the bracket that opens the one closing at P (']' or ')'), or 0. }
function SkipBalancedBack(const S: string; P: Integer): Integer;
var
  Depth: Integer;
begin
  Depth:= 0;
  Result:= P;
  while Result >= 1 do
  begin
    case S[Result] of
      ']', ')': Inc(Depth);
      '[', '(':
        begin
          Dec(Depth);
          if Depth = 0 then Exit;
        end;
      '''':
        begin
          Dec(Result);
          while (Result >= 1) and (S[Result] <> '''') do Dec(Result);
        end;
    end;
    Dec(Result);
  end;
end;

function SkipIdentBack(const S: string; P: Integer): Integer;
begin
  Result:= P;
  while (Result >= 1) and CharInSet(S[Result], IDENT_PART) do Dec(Result);
end;

{ The per-index var/out flags of a routine signature `(var A, B: T; const C: U)`. }
function ParamModes(const ASig: string): TArray<Boolean>;
var
  S, Grp, Head: string;
  Open, Close, I, Depth, GStart: Integer;
  Groups: TList<string>;
begin
  Result:= nil;
  S:= TrimLeft(ASig);
  if (S = '') or (S[1] <> '(') then Exit;
  Open:= 1;
  Close:= SkipBalancedFwd(S, Open) - 1;
  if Close <= Open then Exit;
  Groups:= TList<string>.Create;
  try
    Depth:= 0;
    GStart:= Open + 1;
    for I:= Open + 1 to Close - 1 do
      case S[I] of
        '(', '[': Inc(Depth);
        ')', ']': Dec(Depth);
        ';':
          if Depth = 0 then
          begin
            Groups.Add(Copy(S, GStart, I - GStart));
            GStart:= I + 1;
          end;
      end;
    Groups.Add(Copy(S, GStart, Close - GStart));
    for Grp in Groups do
    begin
      Head:= Trim(Grp);
      if Head = '' then Continue;
      { attributes in front: [ref], [Weak] }
      while (Head <> '') and (Head[1] = '[') do Head:= Trim(Copy(Head, SkipBalancedFwd(Head, 1), MaxInt));
      var IsVar: Boolean:= StartsText('var ', Head) or StartsText('out ', Head);
      var Colon: Integer:= Pos(':', Head);
      var Names: string:= if Colon > 0 then Copy(Head, 1, Colon - 1) else Head;
      var Count: Integer:= 1;
      for var C in Names do
        if C = ',' then Inc(Count);
      for I:= 1 to Count do Result:= Result + [IsVar];
    end;
  finally
    Groups.Free;
  end;
end;

function IsRoutineKind(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
end;

{ ---- TCollector ---------------------------------------------------------- }

constructor TCollector.Create(const AStore, ALibStore: ISymbolStore);
begin
  inherited Create;
  FStore:= AStore;
  FLib  := ALibStore;
  FTexts      := TObjectDictionary<Int64, TSrcText>.Create([doOwnsValues]);
  FCalleeModes:= TDictionary<string, TArray<Boolean>>.Create;
  FCalleeKnown:= TDictionary<string, Integer>.Create;
  FIntrinsics := TDictionary<string, Boolean>.Create;
  FNotCallees := TDictionary<string, Boolean>.Create;
  FBoundCalls := TObjectDictionary<Int64, TDictionary<Integer, Int64>>.Create([doOwnsValues]);
  FBoundModes := TDictionary<Int64, TArray<Boolean>>.Create;
  FBoundIsCall:= TDictionary<Int64, Boolean>.Create;
  for var N in VAR_INTRINSICS do FIntrinsics.AddOrSetValue(N, True);
  for var N in NOT_CALLEES do FNotCallees.AddOrSetValue(N, True);
end;

destructor TCollector.Destroy;
begin
  FBoundIsCall.Free;
  FBoundModes.Free;
  FBoundCalls.Free;
  FNotCallees.Free;
  FIntrinsics.Free;
  FCalleeKnown.Free;
  FCalleeModes.Free;
  FTexts.Free;
  inherited Destroy;
end;

function TCollector.TextOf(AFileId: Int64): TSrcText;
begin
  if FTexts.TryGetValue(AFileId, Result) then Exit;
  Result:= nil;
  var Path: string:= FStore.GetFilePath(AFileId);
  if (Path <> '') and TFile.Exists(Path) then
    try
      Result:= TSrcText.Create(TFile.ReadAllLines(Path));
    except
      on E: EInOutError do Result:= nil;
      on E: EFileNotFoundException do Result:= nil;
      on E: EEncodingError do Result:= nil;
    end;
  FTexts.Add(AFileId, Result);
end;

procedure TCollector.LearnCallee(const ACallee, ALower: string);
var
  Modes: TArray<Boolean>;
  Known: Integer;

  procedure Take(const ASyms: TArray<TSymbol>);
  begin
    for var Sy in ASyms do
      if IsRoutineKind(Sy.Kind) then
      begin
        Known:= CALLEE_ROUTINE;
        var M: TArray<Boolean>:= ParamModes(Sy.Signature);
        if Length(M) > Length(Modes) then SetLength(Modes, Length(M));
        for var I:= 0 to High(M) do
          if M[I] then Modes[I]:= True;
      end
      else if Known = CALLEE_UNKNOWN then Known:= CALLEE_OTHER;
  end;

begin
  Modes:= nil;
  Known:= CALLEE_UNKNOWN;
  Take(FStore.FindSymbolsByExactName(ACallee));
  if FLib <> nil then Take(FLib.FindSymbolsByExactName(ACallee));
  FCalleeModes.AddOrSetValue(ALower, Modes);
  FCalleeKnown.AddOrSetValue(ALower, Known);
end;

function TCollector.ArgIsVar(const ACallee: string; AIndex: Integer): Boolean;
var
  Lc   : string;
  Modes: TArray<Boolean>;
begin
  Lc:= LowerCase(ACallee);
  if FIntrinsics.ContainsKey(Lc + ':' + IntToStr(AIndex)) or FIntrinsics.ContainsKey(Lc + ':' + IntToStr(ANY_ARG)) then
    Exit(True);
  if not FCalleeKnown.ContainsKey(Lc) then LearnCallee(ACallee, Lc);
  var Known: Integer:= FCalleeKnown[Lc];
  if Known = CALLEE_UNKNOWN then Exit(True);   { nothing declares it: may take it by var }
  if Known = CALLEE_OTHER then Exit(False);
  Modes:= FCalleeModes[Lc];
  Result:= (AIndex < Length(Modes)) and Modes[AIndex];
end;

{ Position just past the lvalue chain that starts with the name at P:
  Name[..], Name^, Name.Member, in any order. }
function LvalueEnd(const S: string; P, ALen: Integer): Integer;
var
  Q: Integer;
begin
  Result:= P + ALen;
  while True do
  begin
    Q:= SkipWsFwd(S, Result);
    if Q > Length(S) then Exit;
    if S[Q] = '[' then Result:= SkipBalancedFwd(S, Q)
    else if S[Q] = '^' then Result:= Q + 1
    else if (S[Q] = '.') and (SkipWsFwd(S, Q + 1) <= Length(S)) and CharInSet(S[SkipWsFwd(S, Q + 1)], IDENT_START) then
    begin
      Result:= SkipWsFwd(S, Q + 1);
      while (Result <= Length(S)) and CharInSet(S[Result], IDENT_PART) do Inc(Result);
    end
    else Exit;
  end;
end;

{ The last non-blank position before the receiver chain of the name at P
  (Recv. / Cast(X). / A[I]. / P^.); 0 at the start of the text, NO_POS when the
  brackets do not balance. }
function BeforeReceiver(const S: string; P: Integer): Integer;
begin
  Result:= SkipWsBack(S, P - 1);
  while (Result >= 1) and (S[Result] = '.') do
  begin
    Result:= SkipWsBack(S, Result - 1);
    while Result >= 1 do
      if CharInSet(S[Result], [')', ']']) then
      begin
        Result:= SkipBalancedBack(S, Result);
        if Result = 0 then Exit(NO_POS);
        Result:= SkipIdentBack(S, SkipWsBack(S, Result - 1));
        Break;
      end
      else if S[Result] = '^' then Dec(Result)
      else
      begin
        Result:= SkipIdentBack(S, Result);
        Break;
      end;
    Result:= SkipWsBack(S, Result);
  end;
end;

{ The unmatched open bracket an argument whose preceding delimiter sits at B
  belongs to, and the argument's 0-based index; 0 when a ';' ends the search. }
function EnclosingOpen(const S: string; B: Integer; out AIndex: Integer): Integer;
var
  K, Depth: Integer;
begin
  AIndex:= 0;
  if S[B] = '(' then Exit(B);
  Result:= 0;
  AIndex:= 1;
  K:= B - 1;
  Depth:= 0;
  while K >= 1 do
  begin
    case S[K] of
      ')', ']': Inc(Depth);
      '(', '[':
        begin
          if Depth = 0 then Exit(K);
          Dec(Depth);
        end;
      ',': if Depth = 0 then Inc(AIndex);
      ';': if Depth = 0 then Exit;
      '''':
        begin
          Dec(K);
          while (K >= 1) and (S[K] <> '''') do Dec(K);
        end;
    end;
    Dec(K);
  end;
end;

{ The callee name in front of the open parenthesis at AOpen ('' for a grouping),
  and the offset where that name starts. }
function CalleeBefore(const S: string; AOpen: Integer; out AStart: Integer): string;
var
  NEnd: Integer;
begin
  NEnd:= SkipWsBack(S, AOpen - 1);
  if (NEnd >= 1) and (S[NEnd] = '>') then                { a generic call Foo<T>(X) }
  begin
    while (NEnd >= 1) and (S[NEnd] <> '<') do Dec(NEnd);
    NEnd:= SkipWsBack(S, NEnd - 1);
  end;
  AStart:= SkipIdentBack(S, NEnd) + 1;
  Result:= if AStart > NEnd then '' else Copy(S, AStart, NEnd - AStart + 1);
end;

{ RNA-BARENAME (owner ruling D6, narrow): the routine the resolver bound the
  call at AOffset (the callee name's start) to. True with AModes = the var/out
  flags of THAT routine's overload set only (same name, same parent -- the
  resolver may have picked the wrong overload, so the set errs to silence);
  False when the call is unbound or bound to a non-routine (a cast), and the
  caller falls back to the bare-name merge across project + library. }
function TCollector.BoundCallee(AFileId: Int64; ASrc: TSrcText; AOffset: Integer; out AModes: TArray<Boolean>): Boolean;
var
  Map  : TDictionary<Integer, Int64>;
  SymId: Int64;
  IsRtn: Boolean;
begin
  AModes:= nil;
  if not FBoundCalls.TryGetValue(AFileId, Map) then
  begin
    Map:= TDictionary<Integer, Int64>.Create;
    FBoundCalls.Add(AFileId, Map);
    for var R in FStore.GetReferencesFromFile(AFileId) do
      if (R.SymbolId > 0) and SameText(R.Kind, REF_CALL) then
      begin
        var Off: Integer:= ASrc.OffsetOf(R.StartLine, R.StartCol);
        if Off > 0 then Map.AddOrSetValue(Off, R.SymbolId);
      end;
  end;
  if not Map.TryGetValue(AOffset, SymId) then Exit(False);
  if not FBoundIsCall.TryGetValue(SymId, IsRtn) then
  begin
    var Sym: TSymbol:= FStore.GetSymbolById(SymId);
    IsRtn:= (Sym.Id = SymId) and IsRoutineKind(Sym.Kind);
    if IsRtn then
    begin
      var Modes: TArray<Boolean>:= nil;
      for var Ov in FStore.FindSymbolsByExactName(Sym.Name) do
        if (Ov.Id = Sym.Id) or (IsRoutineKind(Ov.Kind) and (Ov.ParentId = Sym.ParentId)) then
        begin
          var M: TArray<Boolean>:= ParamModes(Ov.Signature);
          if Length(M) > Length(Modes) then SetLength(Modes, Length(M));
          for var I:= 0 to High(M) do
            if M[I] then Modes[I]:= True;
        end;
      FBoundModes.AddOrSetValue(SymId, Modes);
    end;
    FBoundIsCall.AddOrSetValue(SymId, IsRtn);
  end;
  if not IsRtn then Exit(False);
  AModes:= FBoundModes[SymId];
  Result:= True;
end;

function TCollector.ArgVerdict(AFileId: Int64; ASrc: TSrcText; B: Integer): TWriteVerdict;
var
  Index, NStart: Integer;
  Modes: TArray<Boolean>;
begin
  var S: string:= ASrc.Text;
  var Open: Integer:= EnclosingOpen(S, B, Index);
  if (Open = 0) or (S[Open] = '[') then Exit(wvRead);   { an index or an open-array constructor }
  var Callee: string:= CalleeBefore(S, Open, NStart);
  if (Callee = '') or FNotCallees.ContainsKey(LowerCase(Callee)) then Exit(wvRead);
  if BoundCallee(AFileId, ASrc, NStart, Modes) then
    Exit(if (Index < Length(Modes)) and Modes[Index] then wvWrite else wvRead);
  Result:= if ArgIsVar(Callee, Index) then wvWrite else wvRead;
end;

function TCollector.Classify(const ARef: TReference): TWriteVerdict;  // dl:ok too-many-exit-points@61a1 -- REVIEWED 2026-11-01 one guard clause per write shape; each Exit is a verdict
var
  Src : TSrcText;
  S   : string;
  P, Q: Integer;
begin
  Result:= wvWrite;
  Src:= TextOf(ARef.FileId);
  if Src = nil then Exit;
  S:= Src.Text;
  P:= Src.OffsetOf(ARef.StartLine, ARef.StartCol);
  if (P = 0) or not SameText(Copy(S, P, Length(ARef.NameText)), ARef.NameText) then Exit;
  Q:= SkipWsFwd(S, LvalueEnd(S, P, Length(ARef.NameText)));
  if (Q < Length(S)) and (S[Q] = ':') and (S[Q + 1] = '=') then Exit(wvWrite);
  var ArgEnd: Boolean:= (Q <= Length(S)) and CharInSet(S[Q], [',', ')']);
  var B: Integer:= BeforeReceiver(S, P);
  if B = NO_POS then Exit(wvWrite);
  if B < 1 then Exit(wvRead);
  if S[B] = '@' then Exit(wvWrite);                       { address taken }
  if not (ArgEnd and CharInSet(S[B], ['(', ','])) then Exit(wvRead);
  Result:= ArgVerdict(ARef.FileId, Src, B);
end;

function TCollector.DeclTail(const ASym: TSymbol): string;
var
  Src: TSrcText;
  P, Q: Integer;
begin
  Result:= '';
  Src:= TextOf(ASym.FileId);
  if Src = nil then Exit;
  P:= Src.OffsetOf(ASym.StartLine, ASym.StartCol);
  if P = 0 then Exit;
  P:= P + Length(ASym.Name);
  Q:= P;
  var Limit: Integer:= Src.OffsetOf(Min(ASym.StartLine + DECL_LOOKAHEAD, Length(Src.Starts)), 1);
  if Limit = 0 then Limit:= Length(Src.Text);
  while (Q <= Limit) and (Src.Text[Q] <> ';') do Inc(Q);
  Result:= LowerCase(Copy(Src.Text, P, Q - P));
end;

function TCollector.DeclLine(const ASym: TSymbol): string;
var
  Src: TSrcText;
begin
  Result:= '';
  Src:= TextOf(ASym.FileId);
  if (Src = nil) or (ASym.StartLine < 1) or (ASym.StartLine > Length(Src.Starts)) then Exit;
  var P: Integer:= Src.Starts[ASym.StartLine - 1];
  var Q: Integer:= P;
  while (Q <= Length(Src.Text)) and (Src.Text[Q] <> #10) do Inc(Q);
  Result:= LowerCase(Copy(Src.Text, P, Q - P));
end;

function TCollector.WriteAccessor(const AProp: TSymbol): string;
var
  T: string;
  I: Integer;
begin
  Result:= '';
  T:= ' ' + DeclTail(AProp).Replace(#10, ' ').Replace(#9, ' ') + ' ';
  I:= Pos(' write ', T);
  if I = 0 then Exit;
  I:= SkipWsFwd(T, I + Length(' write '));
  var J: Integer:= I;
  while (J <= Length(T)) and CharInSet(T[J], IDENT_PART) do Inc(J);
  Result:= Copy(T, I, J - I);
end;

{ ---- the rule ----------------------------------------------------------- }

function HasWord(const AText, AWord: string): Boolean;
var
  I: Integer;
begin
  I:= Pos(AWord, AText);
  while I > 0 do
  begin
    var Before: Boolean:= (I = 1) or not CharInSet(AText[I - 1], IDENT_PART);
    var After: Boolean:= (I + Length(AWord) > Length(AText)) or not CharInSet(AText[I + Length(AWord)], IDENT_PART);
    if Before and After then Exit(True);
    I:= PosEx(AWord, AText, I + 1);
  end;
  Result:= False;
end;

{ The prepared receiver-type query over ref_receivers + ref_types, or nil when the store is not
  SQLite or the index predates either table (the rule then keeps its name-only evidence). }
function OpenReceiverQuery(const AStore: ISymbolStore): TFDQuery;
begin
  Result:= nil;
  if AStore is not TSQLiteSymbolStore then Exit;
  var Q: TFDQuery:= TFDQuery.Create(nil);
  try
    Q.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text  := 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name IN (''ref_receivers'', ''ref_types'')';
    Q.Open;
    var Both: Boolean:= Q.Fields[0].AsInteger = 2;
    Q.Close;
    if Both then
    begin
      Q.SQL.Text:= 'SELECT t.type_qname FROM ref_receivers rr JOIN ref_types t ON t.ref_id = rr.receiver_ref_id ' +
                   'WHERE rr.ref_id = :id LIMIT 1';
      Result:= Q;
      Q:= nil;
    end;
  finally
    Q.Free;
  end;
end;

function CollectReadNeverAssigned(const AStore, ALibStore: ISymbolStore): TArray<TLintFinding>;
var
  Cand       : TDictionary<Int64, TSymbol>;
  CandNames  : TDictionary<string, Boolean>;
  VarsByName : TObjectDictionary<string, TList<TSymbol>>;
  Written    : TDictionary<Int64, Boolean>;
  ReadSeen   : TDictionary<Int64, Boolean>;
  NameWritten: TDictionary<string, Boolean>;
  Pending    : TObjectDictionary<Int64, TList<TReference>>;
  Parents    : TDictionary<Int64, TSymbol>;
  Coll       : TCollector;
  Findings   : TList<TLintFinding>;
  TypedWrites: TObjectDictionary<string, TList<string>>;  { name -> receiver type leaves of the unbound writes }
  RcvQuery   : TFDQuery;                                  { nil: no ref_receivers / ref_types facts }

  function ParentOf(const ASym: TSymbol; out AParent: TSymbol): Boolean; forward;

  { The static type leaf of the receiver of ref AId (F1 + ref_receivers), '' when unknown. }
  function ReceiverLeaf(AId: Int64): string;
  begin
    Result:= '';
    if RcvQuery = nil then Exit;
    RcvQuery.ParamByName('id').AsLargeInt:= AId;
    RcvQuery.Open;
    try
      if not RcvQuery.Eof then Result:= RcvQuery.Fields[0].AsString;
    finally
      RcvQuery.Close;
    end;
    var Dot: Integer:= LastDelimiter('.', Result);
    if Dot > 0 then Result:= Copy(Result, Dot + 1, MaxInt);
  end;

  { An unbound write of a candidate's name: a known receiver type is kept apart, anything else is
    the project-wide name evidence of old. }
  procedure NoteUnboundWrite(const ARef: TReference);
  begin
    var Lc: string:= LowerCase(ARef.NameText);
    if NameWritten.ContainsKey(Lc) then Exit;
    var Leaf: string:= ReceiverLeaf(ARef.Id);
    if Leaf = '' then
    begin
      NameWritten.AddOrSetValue(Lc, True);
      Exit;
    end;
    var L: TList<string>;
    if not TypedWrites.TryGetValue(Lc, L) then
    begin
      L:= TList<string>.Create;
      TypedWrites.Add(Lc, L);
    end;
    L.Add(Leaf);
  end;

  { Whether the unbound writes of the symbol's name may reach it: a global, a name written through an
    unknown receiver, or a receiver type that is the field's class, a relative of it, or undecidable. }
  function WriteMayReach(const ASym: TSymbol): Boolean;
  var
    L    : TList<string>;
    Owner: TSymbol;
  begin
    Result:= True;
    if NameWritten.ContainsKey(LowerCase(ASym.Name)) then Exit;
    if not TypedWrites.TryGetValue(LowerCase(ASym.Name), L) then Exit(False);
    if (ASym.Kind <> skField) or not ParentOf(ASym, Owner) then Exit;
    for var Leaf in L do
      if (TypeDescendsFrom(AStore, ALibStore, Leaf, Owner.Name) <> tdNo)
        or (TypeDescendsFrom(AStore, ALibStore, Owner.Name, Leaf) <> tdNo) then Exit;
    Result:= False;
  end;

  function ParentOf(const ASym: TSymbol; out AParent: TSymbol): Boolean;
  begin
    Result:= Parents.TryGetValue(ASym.ParentId, AParent);
    if Result or (ASym.ParentId <= 0) then Exit;
    AParent:= AStore.GetSymbolById(ASym.ParentId);
    Result:= AParent.Id = ASym.ParentId;
    if Result then Parents.Add(ASym.ParentId, AParent);
  end;

  procedure AddCandidate(const ASym: TSymbol);
  begin
    Cand.AddOrSetValue(ASym.Id, ASym);
    CandNames.AddOrSetValue(LowerCase(ASym.Name), True);
  end;

  procedure Queue(const ARef: TReference);
  var
    L: TList<TReference>;
  begin
    if not Pending.TryGetValue(ARef.FileId, L) then
    begin
      L:= TList<TReference>.Create;
      Pending.Add(ARef.FileId, L);
    end;
    L.Add(ARef);
  end;

  { Pass 1 for one ref: a bound write decides at once; a read is queued for the text check. }
  procedure Take(const R: TReference);
  var
    S: TSymbol;
  begin
    var IsRw: Boolean:= SameText(R.Kind, REF_READ) or SameText(R.Kind, REF_MEMBER_ACCESS);
    if (R.SymbolId > 0) and Cand.TryGetValue(R.SymbolId, S) then
    begin
      if (R.FileId = S.FileId) and (R.StartLine = S.StartLine) and (R.StartCol = S.StartCol) then Exit;
      if SameText(R.Kind, REF_WRITE) then Written.AddOrSetValue(R.SymbolId, True)
      else if IsRw then
      begin
        ReadSeen.AddOrSetValue(R.SymbolId, True);
        Queue(R);
      end;
    end
    else if (R.SymbolId <= 0) and CandNames.ContainsKey(LowerCase(R.NameText)) then
      if SameText(R.Kind, REF_WRITE) then NoteUnboundWrite(R)
      else if IsRw then Queue(R);
  end;
  function Undecided(AId: Int64): Boolean;
  begin
    Result:= ReadSeen.ContainsKey(AId) and not Written.ContainsKey(AId);
  end;

  { An initialised, absolute or absolute-aliased global; also one whose declaration
    cannot be read. Since extractor 1.33 (146 b1) the name after `absolute` is a READ
    ref, no longer a second var on the alias's line, so the alias's target is found by
    reading the other globals' declarations for `absolute <Name>`. }
  function NamesAsAbsoluteTarget(const ADecl, AName: string): Boolean;
  var
    P: Integer;
    W: string;
  begin
    P:= Pos('absolute', LowerCase(ADecl));
    if P = 0 then Exit(False);
    W:= Trim(Copy(ADecl, P + Length('absolute'), MaxInt));
    P:= 1;
    while (P <= Length(W)) and CharInSet(W[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(P);
    W:= Copy(W, 1, P - 1);
    if W.Contains('.') then W:= Copy(W, W.LastIndexOf('.') + 2, MaxInt);
    Result:= SameText(W, AName);
  end;

  function GlobalExempt(const ASym: TSymbol): Boolean;
  var
    L: TList<TSymbol>;
  begin
    Result:= False;
    if not VarsByName.TryGetValue(LowerCase(ASym.Name), L) then Exit;
    for var V in L do
    begin
      var Tail: string:= Coll.DeclTail(V);
      if (V.Id = ASym.Id) and ((Tail = '') or Tail.Contains('=')) then Exit(True);
      if HasWord(Coll.DeclLine(V), 'absolute') then Exit(True);
    end;
    for var Others in VarsByName.Values do
      for var V in Others do
        if (V.Id <> ASym.Id) and NamesAsAbsoluteTarget(Coll.DeclLine(V), ASym.Name) then Exit(True);
  end;
  procedure Report(const ASym: TSymbol; AIsField: Boolean);
  var
    Owner: TSymbol;
  begin
    var Fd: TLintFinding:= Default(TLintFinding);
    Fd.RuleId    := READ_NEVER_ASSIGNED_RULE;
    Fd.FileId    := ASym.FileId;
    Fd.FilePath  := AStore.GetFilePath(ASym.FileId);
    Fd.StartLine := ASym.StartLine;
    Fd.EndLine   := ASym.StartLine;
    Fd.StartCol  := if ASym.StartCol > 0 then ASym.StartCol else 1;
    Fd.EndCol    := Fd.StartCol + Length(ASym.Name);
    Fd.Severity  := 'warning';
    Fd.SymbolName:= ASym.Name;
    var What: string:= ASym.Name;
    if AIsField and ParentOf(ASym, Owner) then What:= Owner.Name + '.' + ASym.Name;
    Fd.Message   := Format(
      '%s %s is read but nothing in the project assigns or creates it -- every read sees its default ' +
      '(0 / nil / empty); assign it where it is meant, or remove it.',
      [if AIsField then 'Field' else 'Global variable', What]);
    Findings.Add(Fd);
  end;

begin
  Result:= nil;
  if AStore = nil then Exit;
  Cand       := TDictionary<Int64, TSymbol>.Create;
  CandNames  := TDictionary<string, Boolean>.Create;
  VarsByName := TObjectDictionary<string, TList<TSymbol>>.Create([doOwnsValues]);
  Written    := TDictionary<Int64, Boolean>.Create;
  ReadSeen   := TDictionary<Int64, Boolean>.Create;
  NameWritten:= TDictionary<string, Boolean>.Create;
  TypedWrites:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  RcvQuery   := nil;
  Pending    := TObjectDictionary<Int64, TList<TReference>>.Create([doOwnsValues]);
  Parents    := TDictionary<Int64, TSymbol>.Create;
  Coll       := TCollector.Create(AStore, ALibStore);
  Findings   := TList<TLintFinding>.Create;
  try
    { candidates: class / object fields outside the streamed sections, and globals }
    for var F in AStore.FindSymbolsByKind(KIND_FIELD, False, MaxInt) do
    begin
      var Owner: TSymbol;
      if not ParentOf(F, Owner) or (Owner.Kind <> skClass) then Continue;   { record fields: filled whole }
      if not F.VisExplicit or ContainsText(F.Modifiers, VIS_PUBLISHED) then Continue;  { DFM-streamed }
      AddCandidate(F);
    end;
    for var V in AStore.FindSymbolsByKind(KIND_VAR, False, MaxInt) do
    begin
      var Owner: TSymbol;
      if not ParentOf(V, Owner) or (Owner.Kind not in [skUnit, skProgram, skPackage]) then Continue;
      AddCandidate(V);
      var L: TList<TSymbol>;
      if not VarsByName.TryGetValue(LowerCase(V.Name), L) then
      begin
        L:= TList<TSymbol>.Create;
        VarsByName.Add(LowerCase(V.Name), L);
      end;
      L.Add(V);
    end;
    if Cand.Count = 0 then Exit;
    RcvQuery:= OpenReceiverQuery(AStore);

    { pass 1: bound writes decide at once; reads are queued for the text check }
    for var Fi in AStore.GetAllFileIds do
      for var R in AStore.GetReferencesFromFile(Fi) do Take(R);

    { the names still undecided -- only their unbound refs need the text check }
    var OpenNames: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      for var Pair in Cand do
        if Undecided(Pair.Key) then OpenNames.AddOrSetValue(LowerCase(Pair.Value.Name), True);
      { pass 2: classify the queued refs by their source text }
      for var PF in Pending do
        for var R in PF.Value do
        begin
          var Lc: string:= LowerCase(R.NameText);
          if R.SymbolId > 0 then
          begin
            if not Undecided(R.SymbolId) then Continue;
            if Coll.Classify(R) = wvWrite then Written.AddOrSetValue(R.SymbolId, True);
          end
          else if OpenNames.ContainsKey(Lc) and not NameWritten.ContainsKey(Lc) and (Coll.Classify(R) = wvWrite) then
            NoteUnboundWrite(R);
        end;
    finally
      OpenNames.Free;
    end;

    { the would-be findings, then the declaration-text exemptions }
    var Open: TList<TSymbol>:= TList<TSymbol>.Create;
    try
      for var Pair in Cand do
        if Undecided(Pair.Key) and not WriteMayReach(Pair.Value) then Open.Add(Pair.Value);
      if Open.Count > 0 then
      begin
        var PropWrites: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
        try
          for var Pr in AStore.FindSymbolsByKind(KIND_PROPERTY, False, MaxInt) do
          begin
            var W: string:= Coll.WriteAccessor(Pr);
            if W <> '' then PropWrites.AddOrSetValue(W, True);
          end;
          for var S in Open do
          begin
            var Lc: string:= LowerCase(S.Name);
            if PropWrites.ContainsKey(Lc) then Continue;
            var IsField: Boolean:= S.Kind = skField;
            if not IsField and GlobalExempt(S) then Continue;

            Report(S, IsField);
          end;
        finally
          PropWrites.Free;
        end;
      end;
    finally
      Open.Free;
    end;

    Findings.Sort(TComparer<TLintFinding>.Construct(
      function(const A, B: TLintFinding): Integer
      begin
        Result:= CompareText(A.FilePath, B.FilePath);
        if Result = 0 then Result:= A.StartLine - B.StartLine;
        if Result = 0 then Result:= A.StartCol - B.StartCol;
      end));
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Coll.Free;
    Parents.Free;
    Pending.Free;
    RcvQuery.Free;
    TypedWrites.Free;
    NameWritten.Free;
    ReadSeen.Free;
    Written.Free;
    VarsByName.Free;
    CandNames.Free;
    Cand.Free;
  end;
end;

end.
