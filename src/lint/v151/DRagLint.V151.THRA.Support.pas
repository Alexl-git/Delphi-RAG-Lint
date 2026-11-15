unit DRagLint.V151.THRA.Support;

{ Wave v151 lane THRA -- helpers of DRagLint.V151.THRA (private to the lane).

  A small, self-contained lexical scanner for one Delphi source file: tokens
  (comments and string bodies are gone), class declarations (ancestors, member
  routines with their visibility), routine implementations (owner, name, body
  token range) and a type table. The thread rules of the lane read these facts;
  none of them needs the parse tree. The scanner never raises on odd input: an
  unclosed construct simply ends at the end of the token list. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Lexical class of one token.</summary>
  TThrTokKind = (ttkIdent, ttkSym, ttkStr, ttkNum);

  /// <summary>One token with a 1-based position; Col/EndCol are 1-based, EndCol exclusive.</summary>
  TThrTok = record
    Kind   : TThrTokKind;
    Text   : string;
    Low    : string;
    Line   : Integer;
    Col    : Integer;
    EndLine: Integer;
    EndCol : Integer;
  end;

  /// <summary>One routine implementation found after `implementation`.</summary>
  /// <remarks>Nested routines are separate entries; their token range lies inside the parent's.</remarks>
  TThrRoutine = record
    Kind    : string;    // procedure | function | constructor | destructor
    OwnerLow: string;    // class name, lowercase; '' for a free or nested routine
    NameLow : string;
    KwTok   : Integer;   // token index of the routine keyword
    HdrEnd  : Integer;   // token index of the `;` that ends the header
    BodyBeg : Integer;   // token index of `begin` / `asm`; -1 without a body
    BodyEnd : Integer;   // token index of the matching `end`; -1 without a body
  end;

  /// <summary>One member routine declared in a class body.</summary>
  TThrMethod = record
    NameLow: string;
    Vis    : string;     // private | protected | public | published
  end;

  /// <summary>One class, record or interface declaration.</summary>
  TThrClass = record
    Name     : string;
    Ancestors: TArray<string>;   // lowercase, last dotted part, generic arguments dropped
    Methods  : TArray<TThrMethod>;
  end;

  /// <summary>Scans one source text and answers structural questions about it.</summary>
  /// <remarks>Not thread-safe; one instance per file. Owns nothing but its own lists.</remarks>
  TThrScan = class
  private
    FToks     : TArray<TThrTok>;
    FRoutines : TList<TThrRoutine>;
    FClasses  : TDictionary<string, TThrClass>;
    FTypeDefs : TDictionary<string, Integer>;
    FThreadMemo: TDictionary<string, Boolean>;
    FImplIdx  : Integer;
    FStore    : ISymbolStore;
    FFileId   : Int64;
    function IsTypeOpener(AIdx: Integer): Boolean;
    function IsRoutineStart(AIdx: Integer): Boolean;
    function ParseClassDecl(AOpener: Integer): Integer;
    function ParseRoutine(AKw: Integer): Integer;
    procedure Parse;
    function EvalTypeDef(AIdx, ADepth: Integer): Boolean;
    function EvalRecord(AFirst, ADepth: Integer): Boolean;
  public
    /// <summary>Tokenizes and parses ASource.</summary>
    /// <param name="ASource">The unit text.</param>
    /// <param name="AStore">Project index for class ancestry beyond this file; may be nil.</param>
    /// <param name="AFileId">The file's id in AStore, or 0.</param>
    constructor Create(const ASource: string; const AStore: ISymbolStore; AFileId: Int64);
    destructor Destroy; override;
    /// <summary>Number of tokens.</summary>
    /// <returns>Token count.</returns>
    function Count: Integer;
    /// <summary>The token at AIdx.</summary>
    /// <param name="AIdx">0-based token index; must be in range.</param>
    /// <returns>The token record.</returns>
    function Tok(AIdx: Integer): TThrTok;
    /// <summary>Lowercase text of the token at AIdx.</summary>
    /// <param name="AIdx">Any integer.</param>
    /// <returns>The lowercase text, or '' when AIdx is out of range.</returns>
    function L(AIdx: Integer): string;
    /// <summary>All routine implementations, nested ones included.</summary>
    /// <returns>The scanner's own list; do not free.</returns>
    function Routines: TList<TThrRoutine>;
    /// <summary>The class declaration named ANameLow, if this file declares it.</summary>
    /// <param name="ANameLow">Lowercase type name.</param>
    /// <param name="AClass">Receives the declaration.</param>
    /// <returns>True when found.</returns>
    function TryGetClass(const ANameLow: string; out AClass: TThrClass): Boolean;
    /// <summary>Index of the token that closes the parenthesis opened at AOpen.</summary>
    /// <param name="AOpen">Token index of `(`.</param>
    /// <returns>Index of the matching `)`, or -1.</returns>
    function MatchParen(AOpen: Integer): Integer;
    /// <summary>Innermost routine whose body contains token AIdx.</summary>
    /// <param name="AIdx">Token index.</param>
    /// <returns>Index into Routines, or -1.</returns>
    function EnclosingRoutine(AIdx: Integer): Integer;
    /// <summary>Does ANameLow descend from TThread?</summary>
    /// <param name="ANameLow">Lowercase class name.</param>
    /// <returns>True when the in-file chain reaches TThread, the index says so, or an unresolved ancestor is named *Thread.</returns>
    function IsThreadClass(const ANameLow: string): Boolean;
    /// <summary>Is the type spelled by tokens [AFrom, ATo) managed (never finalized in a threadvar)?</summary>
    /// <param name="AFrom">First token of the type.</param>
    /// <param name="ATo">One past the last token.</param>
    /// <param name="ADepth">Recursion depth, 0 at the caller.</param>
    /// <returns>True for strings, variants, dynamic arrays, interfaces, anonymous methods and records holding one.</returns>
    function TypeManaged(AFrom, ATo, ADepth: Integer): Boolean;
    /// <summary>End (exclusive) of a type or statement run: the next `;` at nesting depth 0.</summary>
    /// <param name="AFrom">First token.</param>
    /// <returns>Index of the `;` or Count.</returns>
    function RunEnd(AFrom: Integer): Integer;
    /// <summary>Index of the `end` that closes the begin/try/case/asm at ABeg.</summary>
    /// <param name="ABeg">Token index of the opener.</param>
    /// <returns>Index of the closing `end`, or Count - 1.</returns>
    function MatchEnd(ABeg: Integer): Integer;
    /// <summary>Does tokens [AFrom, ATo] contain the lowercase identifier AWord?</summary>
    /// <param name="AFrom">First token.</param>
    /// <param name="ATo">Last token, inclusive.</param>
    /// <param name="AWord">Lowercase identifier.</param>
    /// <returns>True when present.</returns>
    function HasWord(AFrom, ATo: Integer; const AWord: string): Boolean;
    /// <summary>Does tokens [AFrom, ATo] contain any identifier of AWords?</summary>
    /// <param name="AFrom">First token.</param>
    /// <param name="ATo">Last token, inclusive.</param>
    /// <param name="AWords">Lowercase identifiers.</param>
    /// <returns>True when one is present.</returns>
    function HasAnyWord(AFrom, ATo: Integer; const AWords: array of string): Boolean;
    /// <summary>The unit's index in the declaration order of `uses` names, as one lowercase list.</summary>
    /// <returns>Every identifier between a `uses` keyword and its `;`, lowercase, dotted names joined.</returns>
    function UsesNames: TArray<string>;
  end;


/// <summary>`TThread.CreateAnonymousThread(...)` whose thread is never started.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckAnonymousNotStarted(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>Synchronize reached from the destructor of a TThread descendant.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckSynchronizeInDestructor(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>Execute loops that never consult Terminated.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckLoopWithoutTerminated(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>A thread member used after Start although FreeOnTerminate is True.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckUseAfterFreeOnTerminate(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>threadvar declarations of a managed type.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckThreadvarManaged(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>TThread.Queue(nil, ...) / ForceQueue(nil, ...) in a unit that belongs to a package.</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckQueueNilInPackage(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

/// <summary>FreeAndNil / DisposeOf on a thread that frees itself (the forms the host rule does not see).</summary>
/// <param name="AScan">Scan of the file.</param>
/// <param name="APath">File path.</param>
/// <param name="AHostRuleId">The host rule id the findings are emitted under.</param>
/// <param name="AOut">Findings are appended.</param>
procedure ThrCheckFreeAndNilOnFreeOnTerminate(const AScan: TThrScan; const APath, AHostRuleId: string; const AOut: TList<TLintFinding>);

implementation

uses
  System.Character
  , System.IOUtils
  ;

const
  ROUTINE_KWS: array[0..3] of string = ('procedure', 'function', 'constructor', 'destructor');
  DIRECTIVES: array[0..29] of string = (
    'forward', 'external', 'overload', 'inline', 'stdcall', 'cdecl', 'register', 'safecall', 'pascal',
    'far', 'near', 'assembler', 'deprecated', 'platform', 'experimental', 'reintroduce', 'virtual',
    'override', 'abstract', 'dynamic', 'final', 'static', 'varargs', 'message', 'dispid', 'export',
    'local', 'unsafe', 'winapi', 'library');
  SECTION_KWS: array[0..19] of string = (
    'var', 'const', 'type', 'threadvar', 'procedure', 'function', 'constructor', 'destructor', 'begin',
    'implementation', 'initialization', 'finalization', 'class', 'uses', 'resourcestring', 'label', 'end',
    'interface', 'exports', 'property');
  DESIGN_UNITS: array[0..3] of string = ('toolsapi', 'designintf', 'designeditors', 'componentdesigner');
  MAX_DEPTH = 6;

function InArr(const AVal: string; const AArr: array of string): Boolean;
begin
  Result:= False;
  for var S: string in AArr do
    if AVal = S then Exit(True);
end;

function IsRoutineKw(const ALow: string): Boolean;
begin
  Result:= InArr(ALow, ROUTINE_KWS);
end;

{ Tokenizer ------------------------------------------------------------- }

function Tokenize(const S: string): TArray<TThrTok>;  // dl:ok deep-nesting@9caa, cyclomatic-complexity@a967, cognitive-complexity@0e50 -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  Lst: TList<TThrTok>;
  I, N, Line, Col, StartI, StartLine, StartCol: Integer;
  C: Char;

  procedure Adv;
  begin
    if S[I] = #10 then
    begin
      Inc(Line);
      Col:= 1;
    end
    else if S[I] <> #13 then Inc(Col);
    Inc(I);
  end;

  procedure Emit(AKind: TThrTokKind);
  var
    T: TThrTok;
  begin
    T.Kind   := AKind;
    T.Text   := Copy(S, StartI, I - StartI);
    T.Low    := LowerCase(T.Text);
    if T.Low.StartsWith('&') and (Length(T.Low) > 1) and (AKind = ttkIdent) then T.Low:= Copy(T.Low, 2, MaxInt);
    T.Line   := StartLine;
    T.Col    := StartCol;
    T.EndLine:= Line;
    T.EndCol := Col;
    Lst.Add(T);
  end;

  procedure Mark;
  begin
    StartI:= I;
    StartLine:= Line;
    StartCol:= Col;
  end;

begin
  Lst:= TList<TThrTok>.Create;
  try
    N:= Length(S);
    I:= 1;
    Line:= 1;
    Col:= 1;
    while I <= N do
    begin
      C:= S[I];
      if C <= ' ' then Adv
      else if (C = '/') and (I < N) and (S[I + 1] = '/') then
      begin
        while (I <= N) and (S[I] <> #10) do Adv;
      end
      else if C = '{' then
      begin
        while (I <= N) and (S[I] <> '}') do Adv;
        if I <= N then Adv;
      end
      else if (C = '(') and (I < N) and (S[I + 1] = '*') then
      begin
        Adv;
        Adv;
        while (I <= N) and not ((S[I] = '*') and (I < N) and (S[I + 1] = ')')) do Adv;
        if I <= N then Adv;
        if I <= N then Adv;
      end
      else if C = '''' then
      begin
        Mark;
        Adv;
        while (I <= N) and (S[I] <> #10) do
        begin
          if S[I] = '''' then
          begin
            if (I < N) and (S[I + 1] = '''') then
            begin
              Adv;
              Adv;
            end
            else
            begin
              Adv;
              Break;
            end;
          end
          else Adv;
        end;
        Emit(ttkStr);
      end
      else if C = '#' then
      begin
        Mark;
        Adv;
        if (I <= N) and (S[I] = '$') then Adv;
        while (I <= N) and S[I].IsLetterOrDigit do Adv;
        Emit(ttkStr);
      end
      else if C.IsLetter or (C = '_') or ((C = '&') and (I < N) and S[I + 1].IsLetter) then
      begin
        Mark;
        Adv;
        while (I <= N) and (S[I].IsLetterOrDigit or (S[I] = '_')) do Adv;
        Emit(ttkIdent);
      end
      else if C.IsDigit or ((C = '$') and (I < N) and S[I + 1].IsLetterOrDigit) then
      begin
        Mark;
        if C = '$' then
        begin
          Adv;
          while (I <= N) and S[I].IsLetterOrDigit do Adv;
        end
        else
        begin
          while (I <= N) and S[I].IsDigit do Adv;
          if (I < N) and (S[I] = '.') and S[I + 1].IsDigit then
          begin
            Adv;
            while (I <= N) and S[I].IsDigit do Adv;
          end;
        end;
        Emit(ttkNum);
      end
      else
      begin
        Mark;
        Adv;
        if (I <= N) then
        begin
          var Two: string:= C + S[I];
          if (Two = ':=') or (Two = '<>') or (Two = '<=') or (Two = '>=') or (Two = '..') then Adv;
        end;
        Emit(ttkSym);
      end;
    end;
    Result:= Lst.ToArray;
  finally
    Lst.Free;
  end;
end;

{ TThrScan -------------------------------------------------------------- }

constructor TThrScan.Create(const ASource: string; const AStore: ISymbolStore; AFileId: Int64);
begin
  inherited Create;
  FRoutines  := TList<TThrRoutine>.Create;
  FClasses   := TDictionary<string, TThrClass>.Create;
  FTypeDefs  := TDictionary<string, Integer>.Create;
  FThreadMemo:= TDictionary<string, Boolean>.Create;
  FStore     := AStore;
  FFileId    := AFileId;
  FToks      := Tokenize(ASource);
  Parse;
end;

destructor TThrScan.Destroy;
begin
  FThreadMemo.Free;
  FTypeDefs.Free;
  FClasses.Free;
  FRoutines.Free;
  inherited;  // dl:ok inherited-bare@246d -- REVIEWED 2026-11-13 v151 THR-A: TObject destructor chain only
end;

function TThrScan.Count: Integer;
begin
  Result:= Length(FToks);
end;

function TThrScan.Tok(AIdx: Integer): TThrTok;
begin
  Result:= FToks[AIdx];
end;

function TThrScan.L(AIdx: Integer): string;
begin
  if (AIdx >= 0) and (AIdx < Length(FToks)) then Result:= FToks[AIdx].Low else Result:= '';  // dl:ok ifthen-to-if-expression@8c95 -- REVIEWED 2026-11-13 v151 THR-A: kept as a statement to match the surrounding style
end;

function TThrScan.Routines: TList<TThrRoutine>;
begin
  Result:= FRoutines;
end;

function TThrScan.TryGetClass(const ANameLow: string; out AClass: TThrClass): Boolean;
begin
  Result:= FClasses.TryGetValue(ANameLow, AClass);
end;

function TThrScan.MatchParen(AOpen: Integer): Integer;
var
  D, K: Integer;
begin
  Result:= -1;
  D:= 0;
  for K:= AOpen to Length(FToks) - 1 do
  begin
    if FToks[K].Kind <> ttkSym then Continue;
    if FToks[K].Low = '(' then Inc(D)
    else if FToks[K].Low = ')' then
    begin
      Dec(D);
      if D = 0 then Exit(K);
    end;
  end;
end;

function TThrScan.RunEnd(AFrom: Integer): Integer;
var
  K, D: Integer;
begin
  D:= 0;
  K:= AFrom;
  while K < Length(FToks) do
  begin
    if FToks[K].Kind = ttkSym then
    begin
      if (FToks[K].Low = '(') or (FToks[K].Low = '[') or (FToks[K].Low = '<') then Inc(D)
      else if (FToks[K].Low = ')') or (FToks[K].Low = ']') or (FToks[K].Low = '>') then Dec(D)
      else if (FToks[K].Low = ';') and (D <= 0) then Exit(K);
    end;
    Inc(K);
  end;
  Result:= K;
end;

function TThrScan.MatchEnd(ABeg: Integer): Integer;
var
  K, D: Integer;
  W: string;
begin
  D:= 0;
  K:= ABeg;
  while K < Length(FToks) do
  begin
    W:= FToks[K].Low;
    if FToks[K].Kind = ttkIdent then
    begin
      if (W = 'begin') or (W = 'try') or (W = 'case') or (W = 'asm') then Inc(D)
      else if W = 'end' then
      begin
        Dec(D);
        if D <= 0 then Exit(K);
      end;
    end;
    Inc(K);
  end;
  Result:= Length(FToks) - 1;
end;

function TThrScan.HasWord(AFrom, ATo: Integer; const AWord: string): Boolean;
begin
  Result:= False;
  for var K: Integer:= AFrom to ATo do
    if (K >= 0) and (K < Length(FToks)) and (FToks[K].Kind = ttkIdent) and (FToks[K].Low = AWord) then Exit(True);
end;

function TThrScan.HasAnyWord(AFrom, ATo: Integer; const AWords: array of string): Boolean;
begin
  Result:= False;
  for var K: Integer:= AFrom to ATo do
    if (K >= 0) and (K < Length(FToks)) and (FToks[K].Kind = ttkIdent) and InArr(FToks[K].Low, AWords) then Exit(True);
end;

function TThrScan.UsesNames: TArray<string>;  // dl:ok deep-nesting@ddf6 -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  Res: TList<string>;
  K: Integer;
  Cur: string;
begin
  Res:= TList<string>.Create;
  try
    K:= 0;
    while K < Length(FToks) do
    begin
      if (FToks[K].Low = 'uses') and (FToks[K].Kind = ttkIdent) then
      begin
        Inc(K);
        Cur:= '';
        while (K < Length(FToks)) and (FToks[K].Low <> ';') do
        begin
          if FToks[K].Low = ',' then
          begin
            if Cur <> '' then Res.Add(Cur);
            Cur:= '';
          end
          else if FToks[K].Kind = ttkIdent then
          begin
            if FToks[K].Low = 'in' then
            begin
              while (K < Length(FToks)) and (FToks[K].Low <> ',') and (FToks[K].Low <> ';') do Inc(K);
              Continue;
            end;
            Cur:= Cur + FToks[K].Low;  // dl:ok concat-in-loop@ec6e -- REVIEWED 2026-11-13 v151 THR-A: short lists (a handful of items); a builder would add noise
          end
          else if FToks[K].Low = '.' then Cur:= Cur + '.';  // dl:ok concat-in-loop@3638 -- REVIEWED 2026-11-13 v151 THR-A: short lists (a handful of items); a builder would add noise
          Inc(K);
        end;
        if Cur <> '' then Res.Add(Cur);
      end
      else Inc(K);
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
  end;
end;

function TThrScan.IsTypeOpener(AIdx: Integer): Boolean;
var
  W: string;
begin
  Result:= False;
  if FToks[AIdx].Kind <> ttkIdent then Exit;
  W:= FToks[AIdx].Low;
  if not ((W = 'class') or (W = 'record') or (W = 'object') or (W = 'interface') or (W = 'dispinterface')) then Exit;
  if (L(AIdx - 1) <> '=') and not ((L(AIdx - 1) = 'packed') and (L(AIdx - 2) = '=')) then Exit;
  if (W = 'class') and (L(AIdx + 1) = 'of') then Exit;
  Result:= True;
end;

function TThrScan.IsRoutineStart(AIdx: Integer): Boolean;
var
  P: Integer;
begin
  Result:= False;
  if (FToks[AIdx].Kind <> ttkIdent) or not IsRoutineKw(FToks[AIdx].Low) then Exit;
  P:= AIdx - 1;
  if L(P) = 'class' then Dec(P);
  Result:= (P < 0) or (L(P) = ';') or (L(P) = 'implementation') or (L(P) = ']');
end;

function TThrScan.ParseClassDecl(AOpener: Integer): Integer;  // dl:ok deep-nesting@c943, cyclomatic-complexity@3862, cognitive-complexity@a35b -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  N, J, K, Depth, E, GenD: Integer;
  C: TThrClass;
  NameLow, Vis, Last: string;
  Anc: TList<string>;
  Meths: TList<TThrMethod>;
  M: TThrMethod;
  P: string;
begin
  N:= Length(FToks);
  Result:= AOpener + 1;
  E:= AOpener - 1;
  if L(E) = 'packed' then Dec(E);
  // E is the '=' token; the type name sits left of it (generic parameter list skipped).
  K:= E - 1;
  if L(K) = '>' then
  begin
    GenD:= 0;
    while K >= 0 do
    begin
      if L(K) = '>' then Inc(GenD)
      else if L(K) = '<' then
      begin
        Dec(GenD);
        if GenD = 0 then
        begin
          Dec(K);
          Break;
        end;
      end;
      Dec(K);
    end;
  end;
  if (K >= 0) and (FToks[K].Kind = ttkIdent) then NameLow:= FToks[K].Low else NameLow:= '';  // dl:ok ifthen-to-if-expression@2dd1 -- REVIEWED 2026-11-13 v151 THR-A: kept as a statement to match the surrounding style
  J:= AOpener + 1;
  if (L(J) = 'abstract') or (L(J) = 'sealed') then Inc(J);
  Anc:= TList<string>.Create;
  Meths:= TList<TThrMethod>.Create;
  try
    if L(J) = '(' then
    begin
      Depth:= 1;
      GenD:= 0;
      Last:= '';
      Inc(J);
      while (J < N) and (Depth > 0) do
      begin
        P:= FToks[J].Low;
        if FToks[J].Kind = ttkSym then
        begin
          if P = '(' then Inc(Depth)
          else if P = ')' then
          begin
            Dec(Depth);
            if (Depth = 0) and (Last <> '') then Anc.Add(Last);
          end
          else if (P = ',') and (Depth = 1) and (GenD = 0) then
          begin
            if Last <> '' then Anc.Add(Last);
            Last:= '';
          end
          else if P = '<' then Inc(GenD)
          else if P = '>' then Dec(GenD);
        end
        else if (FToks[J].Kind = ttkIdent) and (GenD = 0) and (Depth = 1) then Last:= P;
        Inc(J);
      end;
    end;
    if (NameLow <> '') and (L(J) = ';') then
    begin
      C.Name:= FToks[K].Text;
      C.Ancestors:= Anc.ToArray;
      C.Methods:= nil;
      FClasses.AddOrSetValue(NameLow, C);
      Exit(J + 1);
    end;
    Vis:= 'public';
    Depth:= 1;
    while (J < N) and (Depth > 0) do
    begin
      P:= FToks[J].Low;
      if FToks[J].Kind = ttkIdent then
      begin
        if IsTypeOpener(J) and not ((P = 'class') and ((L(J + 1) = ';') or (L(J + 1) = 'of'))) then Inc(Depth)
        else if P = 'end' then Dec(Depth)
        else if Depth = 1 then
        begin
          if (P = 'private') or (P = 'protected') or (P = 'public') or (P = 'published') then Vis:= P
          else if IsRoutineKw(P) and (L(J - 1) <> ':') and (L(J - 1) <> 'to') and (L(J - 1) <> '=') and (L(J - 1) <> 'of')  // dl:ok boolean-expression-complexity@41a2 -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
            and (J + 1 < N) and (FToks[J + 1].Kind = ttkIdent) then
          begin
            M.NameLow:= L(J + 1);
            M.Vis:= Vis;
            Meths.Add(M);
          end;
        end;
      end;
      Inc(J);
    end;
    if NameLow <> '' then
    begin
      C.Name:= FToks[K].Text;
      C.Ancestors:= Anc.ToArray;
      C.Methods:= Meths.ToArray;
      FClasses.AddOrSetValue(NameLow, C);
    end;
    Result:= J;
  finally
    Meths.Free;
    Anc.Free;
  end;
end;

function TThrScan.ParseRoutine(AKw: Integer): Integer;  // dl:ok deep-nesting@c417, cyclomatic-complexity@b56d -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  N, J, D: Integer;
  R: TThrRoutine;
  Parts: TList<string>;
  Dir: string;
  HasBody: Boolean;
begin
  N:= Length(FToks);
  R:= Default(TThrRoutine);
  R.Kind:= FToks[AKw].Low;
  R.KwTok:= AKw;
  R.BodyBeg:= -1;
  R.BodyEnd:= -1;
  Parts:= TList<string>.Create;
  try
    J:= AKw + 1;
    while (J < N) and (FToks[J].Kind = ttkIdent) do
    begin
      Parts.Add(FToks[J].Low);
      Inc(J);
      if L(J) = '<' then
      begin
        D:= 0;
        while J < N do
        begin
          if L(J) = '<' then Inc(D)
          else if L(J) = '>' then
          begin
            Dec(D);
            if D = 0 then
            begin
              Inc(J);
              Break;
            end;
          end;
          Inc(J);
        end;
      end;
      if L(J) = '.' then Inc(J) else Break;
    end;
    if Parts.Count > 0 then R.NameLow:= Parts[Parts.Count - 1];
    if Parts.Count > 1 then R.OwnerLow:= Parts[Parts.Count - 2];
    D:= 0;
    while J < N do
    begin
      if FToks[J].Kind = ttkSym then
      begin
        if FToks[J].Low = '(' then Inc(D)
        else if FToks[J].Low = ')' then Dec(D)
        else if (FToks[J].Low = ';') and (D <= 0) then Break;
      end
      else if (D <= 0) and ((FToks[J].Low = 'begin') or (FToks[J].Low = 'asm')) then Break;
      Inc(J);
    end;
    R.HdrEnd:= J;
    Inc(J);
    HasBody:= True;
    while (J < N) and (FToks[J].Kind = ttkIdent) and InArr(FToks[J].Low, DIRECTIVES) do
    begin
      Dir:= FToks[J].Low;
      if (Dir = 'forward') or (Dir = 'external') then HasBody:= False;
      while (J < N) and (FToks[J].Low <> ';') do Inc(J);
      Inc(J);
    end;
    if not HasBody then
    begin
      FRoutines.Add(R);
      Exit(J);
    end;
    while J < N do
    begin
      if (FToks[J].Low = 'begin') or (FToks[J].Low = 'asm') then Break;
      if IsTypeOpener(J) then J:= ParseClassDecl(J)
      else if IsRoutineStart(J) then J:= ParseRoutine(J)
      else Inc(J);
    end;
    if J >= N then
    begin
      FRoutines.Add(R);
      Exit(N);
    end;
    R.BodyBeg:= J;
    R.BodyEnd:= MatchEnd(J);
    FRoutines.Add(R);
    Result:= R.BodyEnd + 1;
    if L(Result) = ';' then Inc(Result);
  finally
    Parts.Free;
  end;
end;

procedure TThrScan.Parse;
var
  I, N: Integer;
begin
  N:= Length(FToks);
  FImplIdx:= -1;
  for I:= 0 to N - 1 do
    if (FToks[I].Kind = ttkIdent) and (FToks[I].Low = 'implementation') then
    begin
      FImplIdx:= I;
      Break;
    end;
  // type table: Name = <definition>
  for I:= 1 to N - 2 do
    if (FToks[I].Kind = ttkSym) and (FToks[I].Low = '=') and (FToks[I - 1].Kind = ttkIdent) then
      FTypeDefs.TryAdd(FToks[I - 1].Low, I + 1);
  I:= 0;
  while I < N do
  begin
    if (FToks[I].Kind = ttkIdent) and IsTypeOpener(I) then I:= ParseClassDecl(I)
    else if ((FImplIdx < 0) or (I > FImplIdx)) and IsRoutineStart(I) then I:= ParseRoutine(I)
    else Inc(I);
  end;
end;

function TThrScan.EnclosingRoutine(AIdx: Integer): Integer;
var
  Best, BestBeg: Integer;
begin
  Best:= -1;
  BestBeg:= -1;
  for var K: Integer:= 0 to FRoutines.Count - 1 do
    if (FRoutines[K].BodyBeg >= 0) and (AIdx >= FRoutines[K].BodyBeg) and (AIdx <= FRoutines[K].BodyEnd)
      and (FRoutines[K].BodyBeg > BestBeg) then
    begin
      Best:= K;
      BestBeg:= FRoutines[K].BodyBeg;
    end;
  Result:= Best;
end;

function TThrScan.IsThreadClass(const ANameLow: string): Boolean;

  function Walk(const AName: string; ADepth: Integer; out AUnresolvedThread: Boolean): Boolean;
  var
    C: TThrClass;
    Sub: Boolean;
  begin
    Result:= False;
    AUnresolvedThread:= False;
    if AName = 'tthread' then Exit(True);
    if ADepth > MAX_DEPTH then Exit;
    if FClasses.TryGetValue(AName, C) then
    begin
      for var A: string in C.Ancestors do
      begin
        if Walk(A, ADepth + 1, Sub) then Exit(True);
        if Sub then AUnresolvedThread:= True;
      end;
    end
    else AUnresolvedThread:= AName.EndsWith('thread');
  end;

var
  Cached, Unresolved: Boolean;
  C: TThrClass;
begin
  if FThreadMemo.TryGetValue(ANameLow, Cached) then Exit(Cached);
  Result:= Walk(ANameLow, 0, Unresolved);
  if (not Result) and FClasses.TryGetValue(ANameLow, C) then
  begin
    if (FStore <> nil) and (FFileId > 0) then
    begin
      try
        Result:= FStore.IsDescendantOf(C.Name, 'TThread', FFileId);
      except  // dl:ok bare-except@79dc -- REVIEWED 2026-11-13 v151 THR-A: an unreadable or unlistable file means no package or source facts, so no finding is the right result
        Result:= False;
      end;
    end;
    if (not Result) and Unresolved then Result:= True;
  end;
  FThreadMemo.AddOrSetValue(ANameLow, Result);
end;

function TThrScan.EvalRecord(AFirst, ADepth: Integer): Boolean;
var
  K, N, Nest, PD, ChunkStart, ColonAt: Integer;
  W: string;

  function ChunkManaged(AFrom, ATo: Integer): Boolean;
  var
    Q, Dd: Integer;
  begin
    Result:= False;
    if AFrom >= ATo then Exit;
    W:= FToks[AFrom].Low;
    if (FToks[AFrom].Kind = ttkIdent) and (InArr(W, ROUTINE_KWS) or (W = 'class') or (W = 'property') or (W = 'case')  // dl:ok boolean-expression-complexity@e871 -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
      or (W = 'private') or (W = 'public') or (W = 'strict') or (W = 'protected') or (W = 'published')) then Exit;
    ColonAt:= -1;
    Dd:= 0;
    for Q:= AFrom to ATo - 1 do
    begin
      if FToks[Q].Kind <> ttkSym then Continue;
      if (FToks[Q].Low = '(') or (FToks[Q].Low = '[') then Inc(Dd)
      else if (FToks[Q].Low = ')') or (FToks[Q].Low = ']') then Dec(Dd)
      else if (FToks[Q].Low = ':') and (Dd = 0) then
      begin
        ColonAt:= Q;
        Break;
      end;
    end;
    if ColonAt >= 0 then Result:= TypeManaged(ColonAt + 1, ATo, ADepth + 1);
  end;

begin
  Result:= False;
  N:= Length(FToks);
  Nest:= 0;
  PD:= 0;
  ChunkStart:= AFirst;
  K:= AFirst;
  while K < N do
  begin
    W:= FToks[K].Low;
    if FToks[K].Kind = ttkIdent then
    begin
      if W = 'record' then Inc(Nest)
      else if W = 'end' then
      begin
        if Nest = 0 then
        begin
          Result:= ChunkManaged(ChunkStart, K);
          Exit;
        end;
        Dec(Nest);
      end;
    end
    else if FToks[K].Kind = ttkSym then
    begin
      if (W = '(') or (W = '[') then Inc(PD)
      else if (W = ')') or (W = ']') then Dec(PD)
      else if (W = ';') and (Nest = 0) and (PD <= 0) then
      begin
        if ChunkManaged(ChunkStart, K) then Exit(True);
        ChunkStart:= K + 1;
      end;
    end;
    Inc(K);
  end;
end;

function TThrScan.EvalTypeDef(AIdx, ADepth: Integer): Boolean;
var
  S: Integer;
begin
  Result:= False;
  if ADepth > MAX_DEPTH then Exit;
  S:= AIdx;
  while (L(S) = 'packed') or (L(S) = 'type') do Inc(S);
  if L(S) = 'record' then Exit(EvalRecord(S + 1, ADepth));
  if (L(S) = 'interface') or (L(S) = 'dispinterface') then Exit(True);
  if (L(S) = 'class') or (L(S) = 'object') then Exit(False);
  Result:= TypeManaged(S, RunEnd(S), ADepth + 1);
end;

function TThrScan.TypeManaged(AFrom, ATo, ADepth: Integer): Boolean;  // dl:ok too-many-exit-points@f576 -- REVIEWED 2026-11-13 v151 THR-A: type classification returns at the first decisive token
var
  W: string;
  Q, D: Integer;
  Def: Integer;
begin
  Result:= False;
  if (ADepth > MAX_DEPTH) or (AFrom >= ATo) or (AFrom >= Length(FToks)) then Exit;
  W:= FToks[AFrom].Low;  // dl:ok overwrite-before-read@27e1 -- REVIEWED 2026-11-13 v151 THR-A: W is re-read from the first token on purpose after the qualifier skip
  while (L(AFrom + 1) = '.') and (AFrom + 2 < ATo) do Inc(AFrom, 2);
  W:= FToks[AFrom].Low;
  if W = 'packed' then Exit(TypeManaged(AFrom + 1, ATo, ADepth));
  if W = 'string' then Exit(L(AFrom + 1) <> '[');
  if InArr(W, ['ansistring', 'unicodestring', 'widestring', 'rawbytestring', 'utf8string', 'variant', 'olevariant']) then Exit(True);
  if W = 'reference' then Exit(True);
  if W = 'record' then Exit(EvalRecord(AFrom + 1, ADepth));
  if W = 'array' then
  begin
    if L(AFrom + 1) = 'of' then Exit(True);
    D:= 0;
    for Q:= AFrom + 1 to ATo - 1 do
    begin
      if (FToks[Q].Low = '[') then Inc(D)
      else if (FToks[Q].Low = ']') then Dec(D)
      else if (FToks[Q].Low = 'of') and (D = 0) then Exit(TypeManaged(Q + 1, ATo, ADepth + 1));
    end;
    Exit(False);
  end;
  if FToks[AFrom].Kind <> ttkIdent then Exit;
  if FTypeDefs.TryGetValue(W, Def) then Exit(EvalTypeDef(Def, ADepth + 1));
  if InArr(W, ['tarray', 'tbytes', 'tstringdynarray', 'tproc', 'tfunc', 'tpredicate', 'tcomparison', 'tbytearray']) then Exit(True);
  if W.EndsWith('dynarray') then Exit(True);
  if (Length(W) > 2) and (FToks[AFrom].Text[1] = 'I') and FToks[AFrom].Text[2].IsUpper and not W.StartsWith('int') then Exit(True);
end;

{ Findings -------------------------------------------------------------- }

function ThrFinding(const AScan: TThrScan; const ARuleId, APath: string; AFirst, ALast: Integer;
  const ASeverity, AMessage: string): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARuleId;
  Result.FilePath := APath;
  Result.StartLine:= AScan.Tok(AFirst).Line;
  Result.StartCol := AScan.Tok(AFirst).Col;
  Result.EndLine  := AScan.Tok(ALast).EndLine;
  Result.EndCol   := AScan.Tok(ALast).EndCol;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
end;

{ Rule: anonymous-thread-not-started --------------------------------------- }

procedure ThrCheckAnonymousNotStarted(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);  // dl:ok cyclomatic-complexity@40a0, cognitive-complexity@eb47 -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  I, S, Close, R, T, K: Integer;
  Nxt, Prv, Name: string;
  Started, Escapes, IsLocal: Boolean;
begin
  for I:= 2 to AScan.Count - 2 do
  begin
    if (AScan.L(I) <> 'createanonymousthread') or (AScan.L(I - 1) <> '.') or (AScan.L(I - 2) <> 'tthread')
      or (AScan.L(I + 1) <> '(') then Continue;
    S:= I - 2;
    while (S >= 2) and (AScan.L(S - 1) = '.') and (AScan.Tok(S - 2).Kind = ttkIdent) do Dec(S, 2);
    Close:= AScan.MatchParen(I + 1);
    if Close < 0 then Continue;
    Nxt:= AScan.L(Close + 1);
    Prv:= AScan.L(S - 1);
    if Nxt = '.' then Continue;
    if InArr(Prv, [';', 'begin', 'do', 'then', 'else', 'try', 'finally', 'except']) then
    begin
      if (Nxt = ';') or (Nxt = 'end') or (Nxt = 'else') or (Nxt = '') then
        AOut.Add(ThrFinding(AScan, 'anonymous-thread-not-started', APath, S, Close, 'warning',
          'The anonymous thread is created suspended and its result is dropped: nothing ever calls Start, so the procedure never runs.'));
    end
    else if Prv = ':=' then
    begin
      T:= S - 2;
      if (T < 0) or (AScan.Tok(T).Kind <> ttkIdent) then Continue;
      Name:= AScan.L(T);
      if (Name = 'result') or (AScan.L(T - 1) = '.') then Continue;
      R:= AScan.EnclosingRoutine(S);
      if R < 0 then Continue;
      IsLocal:= AScan.L(T - 1) = 'var';
      if not IsLocal then
        for K:= AScan.Routines[R].HdrEnd + 1 to AScan.Routines[R].BodyBeg - 1 do
          if (AScan.L(K) = Name) and ((AScan.L(K + 1) = ':') or (AScan.L(K + 1) = ',')) then
          begin
            IsLocal:= True;
            Break;
          end;
      if not IsLocal then Continue;
      Started:= False;
      Escapes:= False;
      for K:= Close + 1 to AScan.Routines[R].BodyEnd do
      begin
        if (AScan.L(K) <> Name) or (AScan.L(K - 1) = '.') then Continue;
        if AScan.L(K + 1) = '.' then
        begin
          if (AScan.L(K + 2) = 'start') or (AScan.L(K + 2) = 'resume') then Started:= True;
        end
        else if AScan.L(K + 1) <> ':=' then Escapes:= True;
      end;
      if not (Started or Escapes) then
        AOut.Add(ThrFinding(AScan, 'anonymous-thread-not-started', APath, S, Close, 'warning',
          Format('The anonymous thread assigned to %s is created suspended and %s.Start is never called, so the procedure never runs.',
            [AScan.Tok(T).Text, AScan.Tok(T).Text])));
    end;
  end;
end;

{ Rule: synchronize-in-destructor ------------------------------------------ }

procedure ThrCheckSynchronizeInDestructor(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);

  function FindSync(ARoutine: Integer; const AVisited: TList<Integer>; ADepth: Integer; out ACallTok: Integer; out AVia: string): Integer;
  var
    Rt: TThrRoutine;
    K, Sub, DummyTok: Integer;
    Callee, DummyVia: string;
  begin
    Result:= -1;
    ACallTok:= -1;
    AVia:= '';
    Rt:= AScan.Routines[ARoutine];
    if (Rt.BodyBeg < 0) or (ADepth > 3) then Exit;  // dl:ok magic-literal@5736 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
    AVisited.Add(ARoutine);
    for K:= Rt.BodyBeg + 1 to Rt.BodyEnd - 1 do
    begin
      if AScan.Tok(K).Kind <> ttkIdent then Continue;
      if (AScan.L(K) = 'synchronize') and (AScan.L(K + 1) = '(')
        and ((AScan.L(K - 1) <> '.') or (AScan.L(K - 2) = 'tthread') or (AScan.L(K - 2) = 'self')) then
        Exit(K);
    end;
    for K:= Rt.BodyBeg + 1 to Rt.BodyEnd - 1 do
    begin
      if AScan.Tok(K).Kind <> ttkIdent then Continue;
      if (AScan.L(K - 1) = '.') and (AScan.L(K - 2) <> 'self') then Continue;
      Callee:= AScan.L(K);
      for Sub:= 0 to AScan.Routines.Count - 1 do
      begin
        if (AScan.Routines[Sub].OwnerLow <> Rt.OwnerLow) or (AScan.Routines[Sub].NameLow <> Callee) then Continue;
        if AVisited.Contains(Sub) then Continue;
        if FindSync(Sub, AVisited, ADepth + 1, DummyTok, DummyVia) >= 0 then
        begin
          ACallTok:= K;
          AVia:= AScan.Tok(K).Text;
          Exit(K);
        end;
      end;
    end;
  end;

var
  Idx, Hit, CallTok: Integer;
  Via: string;
  Visited: TList<Integer>;
begin
  for Idx:= 0 to AScan.Routines.Count - 1 do
  begin
    if (AScan.Routines[Idx].Kind <> 'destructor') or (AScan.Routines[Idx].BodyBeg < 0)
      or (AScan.Routines[Idx].OwnerLow = '') or not AScan.IsThreadClass(AScan.Routines[Idx].OwnerLow) then Continue;
    Visited:= TList<Integer>.Create;
    try
      Hit:= FindSync(Idx, Visited, 0, CallTok, Via);
    finally
      Visited.Free;
    end;
    if Hit < 0 then Continue;
    if CallTok < 0 then
      AOut.Add(ThrFinding(AScan, 'synchronize-in-destructor', APath, Hit, Hit, 'warning',
        'Synchronize in the destructor of a TThread descendant: the thread is usually freed from the main thread, which then waits for this very thread, so the call can deadlock.'))
    else
      AOut.Add(ThrFinding(AScan, 'synchronize-in-destructor', APath, Hit, Hit, 'warning',
        Format('%s is called from the destructor of a TThread descendant and reaches Synchronize: the main thread frees the thread and waits for it, so the call can deadlock.', [Via])));
  end;
end;

{ Rule: thread-loop-without-terminated ------------------------------------- }

procedure ThrCheckLoopWithoutTerminated(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);  // dl:ok deep-nesting@a746, cognitive-complexity@eb8b -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct

  function StmtEnd(AFrom, ALimit: Integer): Integer;
  var
    K, D: Integer;
    W: string;
  begin
    D:= 0;
    K:= AFrom;
    while K <= ALimit do
    begin
      W:= AScan.L(K);
      if AScan.Tok(K).Kind = ttkIdent then
      begin
        if (W = 'begin') or (W = 'try') or (W = 'case') or (W = 'asm') then Inc(D)
        else if W = 'end' then
        begin
          Dec(D);
          if D < 0 then Exit(K);
        end;
      end
      else if (W = ';') and (D = 0) then Exit(K);
      Inc(K);
    end;
    Result:= ALimit + 1;
  end;

  function ConstCond(AFrom, ATo: Integer; ATrue: Boolean): Boolean;
  var
    Txt: string;
  begin
    Txt:= '';
    for var K: Integer:= AFrom to ATo do Txt:= Txt + AScan.L(K);  // dl:ok concat-in-loop@bbb4 -- REVIEWED 2026-11-13 v151 THR-A: short lists (a handful of items); a builder would add noise
    if ATrue then Result:= (Txt = 'true') or (Txt = 'notfalse') or (Txt = '1=1') or (Txt = '(true)')  // dl:ok ifthen-to-if-expression@2e6f -- REVIEWED 2026-11-13 v151 THR-A: kept as a statement to match the surrounding style
    else Result:= (Txt = 'false') or (Txt = 'nottrue') or (Txt = '(false)');
  end;

  procedure CheckLoops(ABeg, AEnd: Integer);
  var
    K, M, D, BodyFrom, BodyTo, CondFrom, CondTo, Depth: Integer;
    Infinite, Blocking, Exits, SeesTerm: Boolean;
  begin
    K:= ABeg;
    while K <= AEnd do
    begin
      if (AScan.L(K) = 'while') and (AScan.Tok(K).Kind = ttkIdent) then
      begin
        M:= K + 1;
        D:= 0;
        while M <= AEnd do
        begin
          if (AScan.L(M) = '(') or (AScan.L(M) = '[') then Inc(D)
          else if (AScan.L(M) = ')') or (AScan.L(M) = ']') then Dec(D)
          else if (AScan.L(M) = 'do') and (D = 0) then Break;
          Inc(M);
        end;
        if M > AEnd then
        begin
          Inc(K);
          Continue;
        end;
        CondFrom:= K + 1;
        CondTo:= M - 1;
        BodyFrom:= M + 1;
        if AScan.L(BodyFrom) = 'begin' then BodyTo:= AScan.MatchEnd(BodyFrom) else BodyTo:= StmtEnd(BodyFrom, AEnd) - 1;  // dl:ok ifthen-to-if-expression@a7b0 -- REVIEWED 2026-11-13 v151 THR-A: kept as a statement to match the surrounding style
        Infinite:= ConstCond(CondFrom, CondTo, True);
      end
      else if (AScan.L(K) = 'repeat') and (AScan.Tok(K).Kind = ttkIdent) then
      begin
        M:= K + 1;
        Depth:= 0;
        while M <= AEnd do
        begin
          if AScan.L(M) = 'repeat' then Inc(Depth)
          else if AScan.L(M) = 'until' then
          begin
            if Depth = 0 then Break;
            Dec(Depth);
          end;
          Inc(M);
        end;
        if M > AEnd then
        begin
          Inc(K);
          Continue;
        end;
        BodyFrom:= K + 1;
        BodyTo:= M - 1;
        CondFrom:= M + 1;
        CondTo:= StmtEnd(CondFrom, AEnd) - 1;
        Infinite:= ConstCond(CondFrom, CondTo, False);
      end
      else
      begin
        Inc(K);
        Continue;
      end;
      SeesTerm:= AScan.HasAnyWord(CondFrom, CondTo, ['terminated', 'checkterminated', 'terminate'])
        or AScan.HasAnyWord(BodyFrom, BodyTo, ['terminated', 'checkterminated', 'terminate']);
      Exits:= AScan.HasAnyWord(BodyFrom, BodyTo, ['break', 'exit', 'raise', 'abort', 'halt']);
      Blocking:= AScan.HasAnyWord(CondFrom, BodyTo, ['sleep', 'sleepex', 'waitfor', 'waitforsingleobject', 'waitformultipleobjects']);
      if (not SeesTerm) and ((Infinite and not Exits) or ((not Infinite) and Blocking and not Exits)) then  // dl:ok boolean-expression-complexity@e45e -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
        AOut.Add(ThrFinding(AScan, 'thread-loop-without-terminated', APath, K, K, 'warning',
          'This loop in a thread''s Execute path never tests Terminated, so Terminate and WaitFor cannot stop the thread; add "not Terminated" to the loop condition or test it in the body.'));
      Inc(K);
    end;
  end;

var
  Idx, Sub, Cand, Caller, K, C: Integer;
  Cls: TThrClass;
  Included: TList<Integer>;
  Changed, External, HasCaller, OnlyIncluded, IsPrivate: Boolean;
  Name: string;
begin
  for Idx:= 0 to AScan.Routines.Count - 1 do
  begin
    if (AScan.Routines[Idx].NameLow <> 'execute') or (AScan.Routines[Idx].BodyBeg < 0)
      or (AScan.Routines[Idx].OwnerLow = '') or not AScan.IsThreadClass(AScan.Routines[Idx].OwnerLow) then Continue;
    Included:= TList<Integer>.Create;
    try
      Included.Add(Idx);
      Changed:= True;
      while Changed do
      begin
        Changed:= False;
        for Cand:= 0 to AScan.Routines.Count - 1 do
        begin
          if Included.Contains(Cand) or (AScan.Routines[Cand].BodyBeg < 0)
            or (AScan.Routines[Cand].OwnerLow <> AScan.Routines[Idx].OwnerLow) then Continue;
          Name:= AScan.Routines[Cand].NameLow;
          IsPrivate:= False;
          if AScan.TryGetClass(AScan.Routines[Idx].OwnerLow, Cls) then
            for var Mth: TThrMethod in Cls.Methods do
              if (Mth.NameLow = Name) and ((Mth.Vis = 'private') or (Mth.Vis = 'protected')) then IsPrivate:= True;
          if not IsPrivate then Continue;
          HasCaller:= False;
          OnlyIncluded:= True;
          External:= False;
          for K:= 0 to AScan.Count - 1 do
          begin
            if (AScan.L(K) <> Name) or (AScan.Tok(K).Kind <> ttkIdent) then Continue;
            if (K >= AScan.Routines[Cand].KwTok) and (K <= AScan.Routines[Cand].HdrEnd) then Continue;  // dl:ok manual-inrange@8a11 -- REVIEWED 2026-11-13 v151 THR-A: open interval on purpose
            if AScan.L(K - 1) = '.' then
            begin
              if AScan.L(K - 2) <> 'self' then
              begin
                External:= True;
                Break;
              end;
            end;
            Caller:= AScan.EnclosingRoutine(K);
            if Caller < 0 then Continue;   // mention outside any routine body (declaration)
            HasCaller:= True;
            if not Included.Contains(Caller) then OnlyIncluded:= False;
          end;
          if (not External) and HasCaller and OnlyIncluded then
          begin
            Included.Add(Cand);
            Changed:= True;
          end;
        end;
      end;
      for C:= 0 to Included.Count - 1 do
      begin
        Sub:= Included[C];
        CheckLoops(AScan.Routines[Sub].BodyBeg + 1, AScan.Routines[Sub].BodyEnd - 1);
      end;
    finally
      Included.Free;
    end;
  end;
end;

{ Rule: thread-use-after-free-on-terminate --------------------------------- }

procedure ThrCheckUseAfterFreeOnTerminate(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);  // dl:ok deep-nesting@94d9 -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  Idx, K, M, Q: Integer;
  R: TThrRoutine;
  Name: string;
  Fired: Boolean;
begin
  for Idx:= 0 to AScan.Routines.Count - 1 do
  begin
    R:= AScan.Routines[Idx];
    if R.BodyBeg < 0 then Continue;
    for K:= R.BodyBeg + 1 to R.BodyEnd - 1 do
    begin
      if not ((AScan.L(K) = 'freeonterminate') and (AScan.L(K - 1) = '.') and (AScan.L(K + 1) = ':=') and (AScan.L(K + 2) = 'true')  // dl:ok boolean-expression-complexity@b0d3 -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
        and (AScan.Tok(K - 2).Kind = ttkIdent) and (AScan.L(K - 3) <> '.')) then Continue;  // dl:ok magic-literal@37ff -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
      Name:= AScan.L(K - 2);
      for M:= K + 3 to R.BodyEnd - 1 do  // dl:ok magic-literal@fd01 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
      begin
        if not ((AScan.L(M) = Name) and (AScan.L(M - 1) <> '.') and (AScan.L(M + 1) = '.')
          and ((AScan.L(M + 2) = 'start') or (AScan.L(M + 2) = 'resume'))) then Continue;
        Fired:= False;
        Q:= M + 3;  // dl:ok magic-literal@419d -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
        while (Q < R.BodyEnd) and not Fired do
        begin
          if (AScan.L(Q) = Name) and (AScan.L(Q - 1) <> '.') then
          begin
            if AScan.L(Q + 1) = ':=' then Break;
            if AScan.L(Q + 1) = '.' then
            begin
              AOut.Add(ThrFinding(AScan, 'thread-use-after-free-on-terminate', APath, Q, Q + 2, 'warning',
                Format('%s has FreeOnTerminate = True and was already started: it can free itself at any moment, so this access to %s may touch a freed object.',
                  [AScan.Tok(Q).Text, AScan.Tok(Q + 2).Text])));
              Fired:= True;
            end;
          end;
          Inc(Q);
        end;
        Break;
      end;
    end;
  end;
end;

{ Rule: threadvar-managed ---------------------------------------------------- }

procedure ThrCheckThreadvarManaged(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);
var
  I, J, TypeFrom, TypeTo: Integer;
  Names: TList<Integer>;
  W: string;
begin
  Names:= TList<Integer>.Create;
  try
    I:= 0;
    while I < AScan.Count do
    begin
      if not ((AScan.L(I) = 'threadvar') and (AScan.Tok(I).Kind = ttkIdent) and (AScan.L(I - 1) <> '.')) then
      begin
        Inc(I);
        Continue;
      end;
      J:= I + 1;
      while J < AScan.Count do
      begin
        W:= AScan.L(J);
        if (AScan.Tok(J).Kind = ttkIdent) and InArr(W, SECTION_KWS) then Break;
        Names.Clear;
        while (J < AScan.Count) and (AScan.Tok(J).Kind = ttkIdent) do
        begin
          Names.Add(J);
          Inc(J);
          if AScan.L(J) = ',' then Inc(J) else Break;
        end;
        if (Names.Count = 0) or (AScan.L(J) <> ':') then
        begin
          Inc(J);
          Continue;
        end;
        TypeFrom:= J + 1;
        TypeTo:= AScan.RunEnd(TypeFrom);
        if AScan.TypeManaged(TypeFrom, TypeTo, 0) then
          for var N: Integer in Names do
            AOut.Add(ThrFinding(AScan, 'threadvar-managed', APath, N, N, 'warning',
              Format('Thread variable %s has a managed type, and Delphi does not finalize threadvar storage when a thread ends: the value leaks. Use a class instance owned by the thread, or a plain unmanaged type.',
                [AScan.Tok(N).Text])));
        J:= TypeTo + 1;
      end;
      I:= J;
    end;
  finally
    Names.Free;
  end;
end;

{ Rule: queue-nil-in-package ------------------------------------------------- }

function UnitIsInPackage(const AScan: TThrScan; const APath: string): Boolean;
var
  UnitName, Dir, Sub, Txt: string;
  Dpks: TArray<string>;
  Level, P: Integer;
begin
  Result:= False;
  for var U: string in AScan.UsesNames do
    if InArr(U, DESIGN_UNITS) then Exit(True);
  UnitName:= LowerCase(TPath.GetFileNameWithoutExtension(APath));
  Dir:= TPath.GetDirectoryName(APath);
  Level:= 0;
  while (Dir <> '') and (Level < 4) do  // dl:ok magic-literal@7bad -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
  begin
    try
      Dpks:= TDirectory.GetFiles(Dir, '*.dpk');
      for Sub in TDirectory.GetDirectories(Dir) do
      begin
        if Length(Dpks) > 40 then Break;  // dl:ok large-magic-number@ce2f, magic-literal@ce2f -- REVIEWED 2026-11-13 v151 THR-A: bounded directory scan, documented in the routine
        Dpks:= Dpks + TDirectory.GetFiles(Sub, '*.dpk');
      end;
    except  // dl:ok bare-except@53e7 -- REVIEWED 2026-11-13 v151 THR-A: an unreadable or unlistable file means no package or source facts, so no finding is the right result
      Dpks:= nil;
    end;
    for var Dpk: string in Dpks do
    begin
      try
        Txt:= LowerCase(TFile.ReadAllText(Dpk));
      except  // dl:ok bare-except@69ff, try-except-swallowed@69ff -- REVIEWED 2026-11-13 v151 THR-A: an unreadable or unlistable file means no package or source facts, so no finding is the right result
        Continue;
      end;
      P:= Txt.IndexOf('contains');
      if P < 0 then Continue;
      Txt:= Copy(Txt, P + 1, MaxInt);
      var Pos1: Integer:= Txt.IndexOf(UnitName);
      while Pos1 >= 0 do
      begin
        var Before: Char:= if Pos1 = 0 then ' ' else Txt[Pos1];
        var After : Char:= if Pos1 + Length(UnitName) >= Length(Txt) then ' ' else Txt[Pos1 + Length(UnitName) + 1];
        if not (Before.IsLetterOrDigit or (Before = '_') or (Before = '.')) and not (After.IsLetterOrDigit or (After = '_')) then
          Exit(True);
        Pos1:= Txt.IndexOf(UnitName, Pos1 + 1);
      end;
    end;
    Dir:= TPath.GetDirectoryName(Dir);
    Inc(Level);
  end;
end;

procedure ThrCheckQueueNilInPackage(const AScan: TThrScan; const APath: string; const AOut: TList<TLintFinding>);
var
  I, S: Integer;
  Known, InPkg: Boolean;
begin
  Known:= False;
  InPkg:= False;
  for I:= 2 to AScan.Count - 4 do  // dl:ok magic-literal@b55f -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
  begin
    if not (((AScan.L(I) = 'queue') or (AScan.L(I) = 'forcequeue')) and (AScan.L(I - 1) = '.') and (AScan.L(I - 2) = 'tthread')  // dl:ok boolean-expression-complexity@2d70 -- REVIEWED 2026-11-13 v151 THR-A: flat lookahead over adjacent tokens; splitting it would hide the pattern
      and (AScan.L(I + 1) = '(') and (AScan.L(I + 2) = 'nil') and (AScan.L(I + 3) = ',')) then Continue;  // dl:ok magic-literal@cde4 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
    if not Known then
    begin
      InPkg:= UnitIsInPackage(AScan, APath);
      Known:= True;
    end;
    if not InPkg then Exit;
    S:= I - 2;
    while (S >= 2) and (AScan.L(S - 1) = '.') and (AScan.Tok(S - 2).Kind = ttkIdent) do Dec(S, 2);
    AOut.Add(ThrFinding(AScan, 'queue-nil-in-package', APath, S, I + 3, 'warning',  // dl:ok magic-literal@635a -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
      Format('TThread.%s(nil, ...) in a package unit: the queued entry belongs to no thread, so it is not removed when the package is unloaded and can run into freed code. Pass the owning thread or component-bound context instead.',
        [AScan.Tok(I).Text])));
  end;
end;

{ Expansion of freeonterminate-then-wait: FreeAndNil / DisposeOf ----------- }

procedure ThrCheckFreeAndNilOnFreeOnTerminate(const AScan: TThrScan; const APath, AHostRuleId: string; const AOut: TList<TLintFinding>);  // dl:ok deep-nesting@5c94, cyclomatic-complexity@ec8f, cognitive-complexity@e75f -- REVIEWED 2026-11-13 v151 THR-A: single-pass token scanner; the branches are the grammar of the construct
var
  Idx, K, M, Q, LastTok, VarTok: Integer;
  R: TThrRoutine;
  Name: string;
  Dead: Boolean;
  SelfFree: TList<string>;

  function LocalOfFotClass(const AVar: string): Boolean;
  var
    T: Integer;
  begin
    Result:= False;
    for T:= R.HdrEnd + 1 to R.BodyBeg - 1 do
      if (AScan.L(T) = AVar) and (AScan.L(T + 1) = ':') and SelfFree.Contains(AScan.L(T + 2)) then Exit(True);
  end;

begin
  SelfFree:= TList<string>.Create;
  try
    // thread classes whose constructor sets FreeOnTerminate := True
    for Idx:= 0 to AScan.Routines.Count - 1 do
    begin
      R:= AScan.Routines[Idx];
      if (R.Kind = 'constructor') and (R.BodyBeg >= 0) and (R.OwnerLow <> '') then
        for K:= R.BodyBeg + 1 to R.BodyEnd - 1 do
          if (AScan.L(K) = 'freeonterminate') and (AScan.L(K + 1) = ':=') and (AScan.L(K + 2) = 'true') and (AScan.L(K - 1) <> '.') then
          begin
            SelfFree.Add(R.OwnerLow);
            Break;
          end;
    end;
    for Idx:= 0 to AScan.Routines.Count - 1 do
    begin
      R:= AScan.Routines[Idx];
      if R.BodyBeg < 0 then Continue;
      for K:= R.BodyBeg + 1 to R.BodyEnd - 1 do
      begin
        if AScan.Tok(K).Kind <> ttkIdent then Continue;
        // FreeAndNil(X) / X.DisposeOf with X known to free itself
        Name:= '';
        Q:= K;
        if (AScan.L(K) = 'freeandnil') and (AScan.L(K + 1) = '(') and (AScan.Tok(K + 2).Kind = ttkIdent) and (AScan.L(K + 3) = ')') then  // dl:ok magic-literal@c641 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
          Name:= AScan.L(K + 2)
        else if (AScan.L(K) = 'disposeof') and (AScan.L(K - 1) = '.') and (AScan.Tok(K - 2).Kind = ttkIdent) and (AScan.L(K - 3) <> '.') then  // dl:ok magic-literal@8e93 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
        begin
          Name:= AScan.L(K - 2);
          Q:= K - 2;
        end;
        if Name = '' then Continue;
        Dead:= False;
        // flag set to True earlier in this routine, with no reset in between
        for M:= R.BodyBeg + 1 to K - 1 do
        begin
          if (AScan.L(M) = Name) and (AScan.L(M + 1) = '.') and (AScan.L(M + 2) = 'freeonterminate') and (AScan.L(M + 3) = ':=')  // dl:ok magic-literal@1624 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
            and (AScan.L(M - 1) <> '.') then Dead:= AScan.L(M + 4) = 'true'  // dl:ok magic-literal@a517 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
          else if (AScan.L(M) = Name) and (AScan.L(M - 1) <> '.') and (AScan.L(M + 1) = ':=') then Dead:= False;
        end;
        if (not Dead) and LocalOfFotClass(Name) then
        begin
          Dead:= True;
          for M:= R.BodyBeg + 1 to K - 1 do
            if (AScan.L(M) = Name) and (AScan.L(M - 1) <> '.') and (AScan.L(M + 1) = ':=') and (AScan.L(M + 2) = 'nil') then Dead:= False;
        end;
        if Dead then
        begin
          if AScan.L(K) = 'freeandnil' then
          begin
            LastTok:= K + 3;  // dl:ok magic-literal@85a2 -- REVIEWED 2026-11-13 v151 THR-A: token lookahead offset in a fixed pattern, or a documented bound
            VarTok:= K + 2;
          end
          else
          begin
            LastTok:= K;
            VarTok:= Q;
          end;
          AOut.Add(ThrFinding(AScan, AHostRuleId, APath, Q, LastTok, 'warning',
            Format('%s frees itself when it terminates (FreeOnTerminate is True), so freeing it here with %s is a double free or frees a thread that is still running.',
              [AScan.Tok(VarTok).Text, AScan.Tok(K).Text])));
        end;
      end;
    end;
  finally
    SelfFree.Free;
  end;
end;

end.
