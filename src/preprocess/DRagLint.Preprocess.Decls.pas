unit DRagLint.Preprocess.Decls;

// Lane INC3 (2026-10-27): the symbol table an IF directive is evaluated
// against. Delphi lets {$IF} use any TRUE constant declared before the
// directive -- in the same file, or in a unit of the uses clause -- and
// Declared(X) asks about any symbol kind. The preprocessor feeds every ACTIVE
// text chunk, in order, to a TPPDeclScanner; text inside an inactive branch is
// never fed, so a constant declared only there never counts.
//
// THE SCANNER is a token-level state machine, not a parser. It records:
//   * the uses clause (unit names, in order; 'in' file names skipped);
//   * const NAME = expr;      a TRUE constant; its value is computed at the ';'
//                             through OnEvalConst (the names it uses resolve in
//                             the same table, so later constants build on
//                             earlier ones);
//   * const NAME: T = v;      a TYPED constant: declared, NOT a true constant
//                             (dcc rejects it in $IF -- E2026);
//   * resourcestring, type, var/threadvar names and routine names: declared.
// Declarations are only recorded at block depth 0 (not inside a class/record
// body or a begin..end), so fields and class constants never count. Each
// declaration remembers whether it was in the INTERFACE section -- the part a
// unit exports to the units that use it.
//
// IPPUnitSource is how a uses-clause unit is asked about a name; the indexer
// side installs one process-wide (PPSetUnitSource) before it preprocesses.
//
// ENCODING: // comments only; no brace literals in comments.

interface

uses
  System.Generics.Collections,
  DRagLint.Preprocess.Expr;

type
  /// <summary>One declaration the scanner recorded.</summary>
  /// <remarks>Value is meaningful only when IsTrueConst and HasValue.</remarks>
  TPPDecl = record
    Name       : string;
    IsTrueConst: Boolean;
    /// <summary>EXT-E4: a TYPED constant (`NAME: T = v`); never IsTrueConst.</summary>
    IsTypedConst: Boolean;
    HasValue   : Boolean;
    Value      : TPPValue;
    InInterface: Boolean;
  end;

  /// <summary>Computes a constant declaration's value from its expression text.</summary>
  TPPConstEvaluator = reference to function(const AExpr: string; out AValue: TPPValue): Boolean;

  /// <summary>Answers whether a used unit declares a name, and its value when
  /// it is a true constant.</summary>
  /// <remarks>Implementations must be thread-safe: index and lint runs may
  /// preprocess several files at once.</remarks>
  IPPUnitSource = interface
    ['{6B0E3C5D-2F41-4C8A-9E7B-31D5A8C0F214}']
    /// <summary>Looks AName up among the symbols AUnit exports.</summary>
    /// <param name="AUnit">The unit name as the uses clause spells it (may be
    /// unqualified: SysUtils for System.SysUtils).</param>
    /// <param name="AName">The bare symbol name.</param>
    /// <param name="AValue">The value when pnkConst is returned.</param>
    /// <returns>pnkUnknown, pnkDeclared or pnkConst (see TPPNameKind).</returns>
    function LookupInUnit(const AUnit, AName: string; out AValue: TPPValue): TPPNameKind;
  end;

  /// <summary>The declaration scanner (see the unit header).</summary>
  /// <remarks>Not thread-safe; one instance per preprocess run, shared by
  /// reference with that run's include recursion.</remarks>
  TPPDeclScanner = class
  private type
    TSection = (secNone, secUses, secConst, secRes, secType, secVar, secSkip);
    TDeclState = (dsStart, dsAfterName, dsGeneric, dsConstExpr, dsTypeBody, dsTypeClassHead, dsSkipToSemi);
  private
    FDecls       : TDictionary<string, TPPDecl>;
    FUses        : TList<string>;
    FSection     : TSection;
    FState       : TDeclState;
    FParen       : Integer;
    FBlocks      : TList<Boolean>; // one entry per open block; True = a record body
    FInInterface : Boolean;
    FSawInterface: Boolean;
    FPrevTok     : string;
    FName        : string;
    FExpr        : string;
    FHintSeen    : Boolean;
    FGenericDepth: Integer;
    FVarNames    : TList<string>;
    FUsesCur     : string;
    FUsesAfterIn : Boolean;
    FRoutineNext : Boolean;
    FRoutineName : string;
    FSkipIdent   : Boolean;
    FNestedHead  : Boolean;
    FVarMore     : Boolean;
    FOnEvalConst : TPPConstEvaluator;
    procedure AddDecl(const AName: string; AIsTrueConst, AHasValue: Boolean; const AValue: TPPValue);
    procedure FlushUses;
    procedure FinishConst;
    procedure Token(const AText: string; AIsIdent, AEscaped: Boolean);
    function HandleBlock(const AText, L: string; AIsIdent: Boolean): Boolean;
    function HandleSectionKeyword(const L: string): Boolean;
    procedure HandleDecl(const AText, L: string; AIsIdent, AEscaped: Boolean);
  public
    /// <summary>Constructor: an empty scanner positioned before the first token.</summary>
    constructor Create;
    /// <summary>Frees the tables.</summary>
    destructor Destroy; override;
    /// <summary>Scans the next ACTIVE text chunk. Chunks must arrive in source
    /// order; state (an open const section, a half-read declaration) carries
    /// over from one chunk to the next.</summary>
    /// <param name="AText">The chunk text (directives already removed).</param>
    procedure Feed(const AText: string);
    /// <summary>Finds a declaration recorded so far (case-insensitive).</summary>
    /// <param name="AName">The bare name.</param>
    /// <param name="ADecl">The declaration when found.</param>
    /// <returns>True when AName was declared before this point.</returns>
    function TryGet(const AName: string; out ADecl: TPPDecl): Boolean;
    /// <summary>The uses-clause units seen so far, in source order.</summary>
    /// <returns>Unit names as spelled (dotted names kept).</returns>
    function UsedUnits: TArray<string>;
    /// <summary>The declarations another unit sees: the interface section's,
    /// or every one when the file has no interface section (a program, an
    /// include).</summary>
    /// <returns>The exported declarations, in no particular order.</returns>
    function ExportedDecls: TArray<TPPDecl>;
    /// <summary>Computes a true constant's value at its ';'; nil = values are
    /// never computed (every constant is then declared-only).</summary>
    property OnEvalConst: TPPConstEvaluator read FOnEvalConst write FOnEvalConst;
  end;

/// <summary>Installs the process-wide used-unit symbol source every later
/// preprocess run consults; nil uninstalls it.</summary>
/// <param name="ASource">The source, or nil.</param>
/// <remarks>Install before the run starts and uninstall after it ends; the
/// variable itself is not guarded against a concurrent swap.</remarks>
procedure PPSetUnitSource(const ASource: IPPUnitSource);

/// <summary>The installed used-unit symbol source, or nil.</summary>
/// <returns>The source set by PPSetUnitSource.</returns>
function PPUnitSource: IPPUnitSource;

implementation

uses
  System.SysUtils,
  System.StrUtils;

var
  GUnitSource: IPPUnitSource = nil;

procedure PPSetUnitSource(const ASource: IPPUnitSource);
begin
  GUnitSource:= ASource;
end;

function PPUnitSource: IPPUnitSource;
begin
  Result:= GUnitSource;
end;

const
  // Highest 7-bit code; above it a character is a (Unicode) identifier letter.
  MAX_ASCII = 127;
  // Words that end a declaration's value (hint directives).
  HINT_WORDS: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');
  // Reserved words that are never a declared name at a declaration start.
  RESERVED: array[0..24] of string = ('begin', 'end', 'class', 'object', 'record', 'packed',
    'of', 'array', 'set', 'file', 'string', 'nil', 'not', 'and', 'or', 'xor', 'div', 'mod',
    'shl', 'shr', 'in', 'is', 'as', 'property', 'inherited');

function InList(const S: string; const AList: array of string): Boolean;
begin
  for var X: string in AList do
    if X = S then Exit(True);
  Result:= False;
end;

{ TPPDeclScanner }

constructor TPPDeclScanner.Create;
begin
  inherited Create;
  FDecls   := TDictionary<string, TPPDecl>.Create;
  FUses    := TList<string>.Create;
  FBlocks  := TList<Boolean>.Create;
  FVarNames:= TList<string>.Create;
end;

destructor TPPDeclScanner.Destroy;
begin
  FVarNames.Free;
  FBlocks.Free;
  FUses.Free;
  FDecls.Free;
  inherited Destroy;
end;

procedure TPPDeclScanner.AddDecl(const AName: string; AIsTrueConst, AHasValue: Boolean; const AValue: TPPValue);
var
  D: TPPDecl;
begin
  if AName = '' then Exit;
  D:= Default(TPPDecl);
  D.Name       := AName;
  D.IsTrueConst:= AIsTrueConst;
  D.HasValue   := AHasValue;
  D.Value      := AValue;
  D.InInterface:= FInInterface;
  FDecls.AddOrSetValue(LowerCase(AName), D);
end;

procedure TPPDeclScanner.FlushUses;
begin
  if FUsesCur <> '' then FUses.Add(FUsesCur);
  FUsesCur    := '';
  FUsesAfterIn:= False;
end;

procedure TPPDeclScanner.FinishConst;
var
  V  : TPPValue;
  Has: Boolean;
begin
  V:= Default(TPPValue);
  Has:= Assigned(FOnEvalConst) and FOnEvalConst(Trim(FExpr), V);
  AddDecl(FName, True, Has, V);
  FState:= dsStart;
end;

function TPPDeclScanner.TryGet(const AName: string; out ADecl: TPPDecl): Boolean;
begin
  Result:= FDecls.TryGetValue(LowerCase(AName), ADecl);
end;

function TPPDeclScanner.UsedUnits: TArray<string>;
begin
  Result:= FUses.ToArray;
end;

function TPPDeclScanner.ExportedDecls: TArray<TPPDecl>;
begin
  Result:= nil;
  for var D: TPPDecl in FDecls.Values do
    if D.InInterface or not FSawInterface then Result:= Result + [D];
end;

// Inside an open block (a begin..end, a class or record body) nothing is
// declared; only the nesting is tracked. True when the token was consumed.
function TPPDeclScanner.HandleBlock(const AText, L: string; AIsIdent: Boolean): Boolean; // dl:ok too-many-exit-points@8c7c -- REVIEWED 2026-10-27 each Exit consumes one class-head token
begin
  if FBlocks.Count = 0 then Exit(False);
  Result:= True;
  // A nested 'class' / 'interface' head inside a body: a body follows unless
  // the head is 'class of', a forward 'class;' or a short 'class(TBar);'.
  if FNestedHead then
  begin
    if (L = 'sealed') or (L = 'abstract') or (L = 'helper') then Exit;
    if L = 'for' then
    begin
      FSkipIdent:= True;
      Exit;
    end;
    if AIsIdent and FSkipIdent then
    begin
      FSkipIdent:= False;
      Exit;
    end;
    FNestedHead:= False;
    if (L = 'of') or (AText = ';') then Exit;
    if L = 'end' then Exit; // an empty body opens and closes at once
    FBlocks.Add(False);
    Exit;
  end;
  if not AIsIdent then Exit;
  if L = 'end' then FBlocks.Delete(FBlocks.Count - 1)
  else if (L = 'begin') or (L = 'try') or (L = 'asm') then FBlocks.Add(False)
  // A variant part's 'case' has no 'end' of its own (the record's closes it).
  else if (L = 'case') and not FBlocks[FBlocks.Count - 1] then FBlocks.Add(False)
  else if L = 'record' then FBlocks.Add(True)
  else if ((L = 'class') or (L = 'object') or (L = 'interface') or (L = 'dispinterface')) and (FPrevTok = '=') then
    FNestedHead:= True;
end;

// Section keywords at block depth 0. True when the token was one.
function TPPDeclScanner.HandleSectionKeyword(const L: string): Boolean; // dl:ok cognitive-complexity@cdd3 -- REVIEWED 2026-10-27 a flat keyword table
begin
  Result:= True;
  if L = 'interface' then
  begin
    FInInterface := True;
    FSawInterface:= True;
    FSection     := secNone;
  end
  else if L = 'implementation' then
  begin
    FInInterface:= False;
    FSection    := secNone;
  end
  else if (L = 'uses') or (L = 'contains') or (L = 'requires') then
  begin
    FSection    := secUses;
    FUsesCur    := '';
    FUsesAfterIn:= False;
  end
  else if L = 'const' then FSection:= secConst
  else if L = 'resourcestring' then FSection:= secRes
  else if L = 'type' then FSection:= secType
  else if (L = 'var') or (L = 'threadvar') then FSection:= secVar
  else if (L = 'label') or (L = 'exports') then FSection:= secSkip
  else if (L = 'procedure') or (L = 'function') or (L = 'constructor') or (L = 'destructor') or (L = 'operator') then
  begin
    FSection    := secNone;
    FRoutineNext:= True;
  end
  else if (L = 'begin') or (L = 'initialization') or (L = 'finalization') then
  begin
    FSection:= secNone;
    FBlocks.Add(False);
  end
  else Result:= False;
  if Result then FState:= dsStart;
end;

procedure TPPDeclScanner.HandleDecl(const AText, L: string; AIsIdent, AEscaped: Boolean); // dl:ok cognitive-complexity@8c61, cyclomatic-complexity@b95e -- REVIEWED 2026-10-28 the declaration state machine, one case arm per state (EXT-E4 added the typed-const flag)
var
  Kw: Boolean;
begin
  Kw:= AIsIdent and not AEscaped;
  case FState of
    dsAfterName:
      begin
        if AText = '=' then
        begin
          case FSection of
            secConst:
              begin
                FState   := dsConstExpr;
                FExpr    := '';
                FHintSeen:= False;
              end;
            secRes:
              begin
                AddDecl(FName, False, False, Default(TPPValue));
                FState:= dsSkipToSemi;
              end;
            secType:
              begin
                AddDecl(FName, False, False, Default(TPPValue));
                FState:= dsTypeBody;
              end;
          else
            FState:= dsSkipToSemi;
          end;
        end
        else if (FSection = secVar) and (AText = ',') then
        begin
          FVarMore:= True; // A, B: T -- the next name joins this declaration
          FState  := dsStart;
        end
        else if (FSection = secVar) and (AText = ':') then
        begin
          for var N: string in FVarNames do AddDecl(N, False, False, Default(TPPValue));
          FVarNames.Clear;
          FState:= dsSkipToSemi;
        end
        else if (AText = ':') and (FSection = secConst) then
        begin
          AddDecl(FName, False, False, Default(TPPValue)); // typed constant
          var LTyped: TPPDecl;
          if FDecls.TryGetValue(LowerCase(FName), LTyped) then
          begin
            LTyped.IsTypedConst:= True;
            FDecls.AddOrSetValue(LowerCase(FName), LTyped);
          end;
          FState:= dsSkipToSemi;
        end
        else if (AText = '<') and (FSection = secType) then
        begin
          FGenericDepth:= 1;
          FState:= dsGeneric;
        end
        else FState:= dsStart;
      end;
    dsGeneric:
      begin
        if AText = '<' then Inc(FGenericDepth)
        else if AText = '>' then
        begin
          Dec(FGenericDepth);
          if FGenericDepth = 0 then FState:= dsAfterName;
        end
        else if AText = '>=' then // TFoo<T>= class: the close and the '=' fused
        begin
          Dec(FGenericDepth);
          if FGenericDepth = 0 then
          begin
            FState:= dsAfterName;
            HandleDecl('=', '', False, False);
          end;
        end;
      end;
    dsTypeBody:
      begin
        if Kw and (L = 'packed') then Exit;
        if Kw and ((L = 'class') or (L = 'object') or (L = 'interface') or (L = 'dispinterface')) then FState:= dsTypeClassHead
        else if Kw and (L = 'record') then
        begin
          FBlocks.Add(True);
          FState:= dsStart;
        end
        else FState:= if AText = ';' then dsStart else dsSkipToSemi;
      end;
    dsTypeClassHead:
      begin
        if AText = ';' then FState:= dsStart // forward declaration / class(TBar);
        else if Kw and (L = 'of') then FState:= dsSkipToSemi
        else if Kw and ((L = 'sealed') or (L = 'abstract') or (L = 'helper')) then Exit
        else if Kw and (L = 'for') then FSkipIdent:= True
        else if AIsIdent and FSkipIdent then FSkipIdent:= False
        else
        begin
          // The body starts: everything up to its 'end' is a nested block.
          FBlocks.Add(False);
          FState:= dsStart;
          if Kw and (L = 'end') then FBlocks.Delete(FBlocks.Count - 1);
        end;
      end;
    dsSkipToSemi:
      begin
        if AText = ';' then FState:= dsStart
        else if Kw and (L = 'record') then FBlocks.Add(True);
      end;
  else // dsStart
    begin
      if AIsIdent and FRoutineNext then
      begin
        FRoutineNext:= False;
        FRoutineName:= AText;
        Exit;
      end;
      if not AIsIdent then Exit;
      if Kw and InList(L, RESERVED) then Exit;
      case FSection of
        secConst, secRes, secType:
          begin
            FName := AText;
            FState:= dsAfterName;
          end;
        secVar:
          begin
            if not FVarMore then FVarNames.Clear;
            FVarMore:= False;
            FVarNames.Add(AText);
            FName := AText;
            FState:= dsAfterName;
          end;
      end;
    end;
  end;
end;

procedure TPPDeclScanner.Token(const AText: string; AIsIdent, AEscaped: Boolean); // dl:ok cognitive-complexity@75e1, cyclomatic-complexity@80cd -- REVIEWED 2026-10-28 token dispatch in precedence order (const value, parens, blocks, sections)
var
  L: string;
begin
  L:= if AIsIdent and not AEscaped then LowerCase(AText) else '';

  // A constant's value: everything to the ';' at paren depth 0.
  if FState = dsConstExpr then
  begin
    if (AText = '(') or (AText = '[') then Inc(FParen)
    else if ((AText = ')') or (AText = ']')) and (FParen > 0) then Dec(FParen);
    if (AText = ';') and (FParen = 0) then
    begin
      FinishConst;
      FPrevTok:= ';';
      Exit;
    end;
    if (FParen = 0) and (L <> '') and InList(L, HINT_WORDS) then FHintSeen:= True;
    if not FHintSeen then FExpr:= FExpr + ' ' + AText;
    Exit;
  end;

  // A routine name is recorded unless the next token qualifies it (TFoo.Bar).
  if FRoutineName <> '' then
  begin
    if (AText <> '.') and (FBlocks.Count = 0) then AddDecl(FRoutineName, False, False, Default(TPPValue));
    FRoutineName:= '';
  end;

  if (AText = '(') or (AText = '[') then
  begin
    // '[' right after an interface head is the GUID, i.e. the body has begun.
    if (FState = dsTypeClassHead) and (AText = '[') then HandleDecl(AText, L, AIsIdent, AEscaped);
    Inc(FParen);
    FPrevTok:= AText;
    Exit;
  end;
  if (AText = ')') or (AText = ']') then
  begin
    if FParen > 0 then Dec(FParen);
    FPrevTok:= AText;
    Exit;
  end;
  if FParen > 0 then
  begin
    FPrevTok:= AText;
    Exit;
  end;

  if not HandleBlock(AText, L, AIsIdent) then
  begin
    if FSection = secUses then
    begin
      if AText = ';' then
      begin
        FlushUses;
        FSection:= secNone;
      end
      else if AText = ',' then FlushUses
      else if L = 'in' then FUsesAfterIn:= True
      else if not FUsesAfterIn and (AIsIdent or (AText = '.')) then FUsesCur:= FUsesCur + AText;
    end
    else if (FSection = secSkip) and (AText = ';') then FSection:= secNone
    else if (FState = dsStart) and (L <> '') and HandleSectionKeyword(L) then
    // section switched
    else
      HandleDecl(AText, L, AIsIdent, AEscaped);
  end;
  FPrevTok:= AText;
end;

procedure TPPDeclScanner.Feed(const AText: string); // dl:ok cognitive-complexity@b13a -- REVIEWED 2026-10-27 the tokenizer: one arm per lexical class  // dl:ok cyclomatic-complexity@bbd3 -- REVIEWED 2026-10-27 same tokenizer
var
  I, N, S: Integer;
  C      : Char;
begin
  N:= Length(AText);
  I:= 1;
  while I <= N do
  begin
    C:= AText[I];
    if CharInSet(C, [' ', #9, #10, #11, #12, #13]) then
    begin
      Inc(I);
      Continue;
    end;
    // Comments.
    if C = '{' then
    begin
      while (I <= N) and (AText[I] <> '}') do Inc(I);
      Inc(I);
      Continue;
    end;
    if (C = '(') and (I < N) and (AText[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I < N) and not ((AText[I] = '*') and (AText[I + 1] = ')')) do Inc(I);
      Inc(I, 2);
      Continue;
    end;
    if (C = '/') and (I < N) and (AText[I + 1] = '/') then
    begin
      while (I <= N) and not CharInSet(AText[I], [#10, #13]) do Inc(I);
      Continue;
    end;
    S:= I;
    // Identifiers (an '&' prefix escapes a reserved word).
    if CharInSet(C, ['A'..'Z', 'a'..'z', '_', '&']) or (Ord(C) > MAX_ASCII) then
    begin
      Inc(I);
      while (I <= N) and (CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AText[I]) > MAX_ASCII)) do Inc(I);
      if C = '&' then Token(Copy(AText, S + 1, I - S - 1), True, True)
      else Token(Copy(AText, S, I - S), True, False);
      Continue;
    end;
    // Numbers: $hex, digits, a fraction (not a '..' range), an exponent.
    if CharInSet(C, ['0'..'9', '$']) then
    begin
      Inc(I);
      while (I <= N) and CharInSet(AText[I], ['0'..'9', 'A'..'F', 'a'..'f']) do Inc(I);
      if (I < N) and (AText[I] = '.') and CharInSet(AText[I + 1], ['0'..'9']) then
      begin
        Inc(I);
        while (I <= N) and CharInSet(AText[I], ['0'..'9']) do Inc(I);
      end;
      if (I <= N) and CharInSet(AText[I], ['e', 'E']) and (I < N) and CharInSet(AText[I + 1], ['0'..'9', '+', '-']) then
      begin
        Inc(I, 2);
        while (I <= N) and CharInSet(AText[I], ['0'..'9']) do Inc(I);
      end;
      Token(Copy(AText, S, I - S), False, False);
      Continue;
    end;
    // Strings and #char codes, one token per run.
    if CharInSet(C, ['''', '#']) then
    begin
      while (I <= N) and CharInSet(AText[I], ['''', '#']) do
      begin
        if AText[I] = '#' then
        begin
          Inc(I);
          while (I <= N) and CharInSet(AText[I], ['0'..'9', 'A'..'F', 'a'..'f', '$']) do Inc(I);
        end
        else
        begin
          Inc(I);
          while I <= N do
          begin
            if AText[I] = '''' then
            begin
              if (I < N) and (AText[I + 1] = '''') then Inc(I, 2)
              else
              begin
                Inc(I);
                Break;
              end;
            end
            else if CharInSet(AText[I], [#10, #13]) then Break
            else Inc(I);
          end;
        end;
      end;
      Token(Copy(AText, S, I - S), False, False);
      Continue;
    end;
    // Two-character symbols, then single characters.
    if (I < N) and MatchStr(Copy(AText, I, 2), [':=', '<=', '>=', '<>', '..']) then
    begin
      Token(Copy(AText, I, 2), False, False);
      Inc(I, 2);
      Continue;
    end;
    Token(C, False, False);
    Inc(I);
  end;
end;

end.
