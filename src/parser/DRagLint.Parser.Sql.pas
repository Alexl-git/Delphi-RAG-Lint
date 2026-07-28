unit DRagLint.Parser.Sql;

(* v0.40.5 Tier 1: Firebird DDL parser for MS*.SQL files.

   Implements IParser for files with extensions .sql / .SQL.
   Scans the source for top-level DDL blocks and emits TSymbol records
   into the shared symbols table (with kind = 'sql_table' / 'sql_column' /
   'sql_trigger' / 'sql_generator' / 'sql_view' / 'sql_procedure' /
   'sql_exception' / 'sql_domain' / 'sql_constraint').

   Recognised statements (case-insensitive):
     CREATE TABLE <name> ( <column_defs> )    + columns
     CREATE GENERATOR <name>
     CREATE SEQUENCE <name>                   (Firebird 3+ synonym)
     CREATE TRIGGER <name> FOR <table>        (trigger references emitted as type_use)
     CREATE VIEW <name>
     CREATE PROCEDURE <name>
     CREATE OR ALTER PROCEDURE <name>
     CREATE EXCEPTION <name>
     CREATE DOMAIN <name>                     (Firebird domain types like D_INTEGER)
     CREATE INDEX <name> ON <table>

   Scope:
     - Symbol-level only. Body of triggers/procedures is NOT parsed for
       INSERT/UPDATE/SELECT refs in v0.40.5 (deferred to v0.40.6 if needed).
     - INSERT/UPDATE INTO FIB$* metadata tables are NOT parsed in v0.40.5
       (deferred -- user-deferred decision).
     - Column data-types stored verbatim in symbols.signature.

   Robustness:
     - Tolerates extra whitespace, comments (-- and /* */), and SET TERM
       blocks.
     - Skips strings, comments, and parenthesised expressions when looking
       for the next top-level statement separator.
     - Doesn't validate semantics -- a malformed CREATE TABLE simply emits
       whatever it can extract before bailing. *)

interface

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  TFirebirdSqlParser = class(TInterfacedObject, IParser)
    public
      function LanguageName: string                                               ;
      function FileExtensions: TArray<string>                                     ;
      function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

implementation

type
  TSqlState = class
    Symbols   : TList<TSymbol>       ;
    References: TList<TReference>    ;
    Literals  : TList<TStringLiteral>;
    SourceText: string               ;
    constructor Create(const AText: string);
    destructor Destroy; override;
    function AddSymbol(AKind: TSymbolKind; const AName, AQName: string; AParentIdx: Integer; AStartLine, AStartCol, AEndLine,
      AEndCol: Integer; const ASignature: string = ''): Integer;
    procedure AddRef(const AKind, ANameText: string; AStartLine, AStartCol, AEndLine, AEndCol: Integer);
  end;

constructor TSqlState.Create(const AText: string);
begin
  inherited Create;
  SourceText:= AText;
  Symbols   := TList<TSymbol        >.Create;
  References:= TList<TReference     >.Create;
  Literals  := TList<TStringLiteral >.Create;
end;

destructor TSqlState.Destroy;
begin
  Symbols.Free;
  References.Free;
  Literals.Free;
  inherited;
end;

function TSqlState.AddSymbol(AKind: TSymbolKind; const AName, AQName: string; AParentIdx, AStartLine, AStartCol, AEndLine, AEndCol: Integer; const ASignature: string): Integer;
var
  S: TSymbol;
begin
  S:= Default(TSymbol);
  S.FileId:= -1; { indexer fills }
  S.ParentId     := AParentIdx;
  S.Kind         := AKind;
  S.Name         := AName;
  S.QualifiedName:= AQName;
  S.Signature    := ASignature;
  S.StartLine    := AStartLine;
  S.StartCol     := AStartCol;
  S.EndLine      := AEndLine;
  S.EndCol       := AEndCol;
  Result:= Symbols.Count;
  Symbols.Add(S);
end;

procedure TSqlState.AddRef(const AKind, ANameText: string; AStartLine, AStartCol, AEndLine, AEndCol: Integer);
var
  R: TReference;
begin
  R:= Default(TReference);
  R.FileId:= -1;
  R.Kind     := AKind;
  R.NameText := ANameText;
  R.StartLine:= AStartLine;
  R.StartCol := AStartCol;
  R.EndLine  := AEndLine;
  R.EndCol   := AEndCol;
  References.Add(R);
end;

{ ---- helpers ---- }

procedure ComputeLineCol(const AText: string; APos: Integer; out ALine, ACol: Integer);
var
  I     : Integer;
  LastNl: Integer;
begin
  ALine := 1;
  LastNl:= 0;
  for I:= 1 to APos - 1 do
    if (I <= Length(AText)) and (AText[I] = #10) then
    begin
      Inc(ALine);
      LastNl:= I;
    end;
  ACol:= APos - LastNl;
  if ACol < 1 then ACol:= 1;
end;

function StripCommentsAndStrings(const AText: string): string;
{ Replaces comments and string literals with spaces so the regex passes
  don't see SQL keywords that appear inside them. Length-preserving so
  positions still map back to the original. }
var
  I         : Integer       ;
  N         : Integer       ;
  C         : Char          ;
  C2        : Char          ;
  Buf       : TStringBuilder;
  InLineCmt : Boolean       ;
  InBlockCmt: Boolean       ;
  InString  : Boolean       ;
begin
  N:= Length(AText);
  Buf:= TStringBuilder.Create(N);
  try
    InLineCmt := False;
    InBlockCmt:= False;
    InString  := False;
    I         := 1;
    while I <= N do
    begin
      C:= AText[I];
      if I < N then C2:= AText[I + 1] else C2:= #0;

      if InLineCmt then
      begin
        if C = #10 then InLineCmt:= False;
        if (C = #13) or (C = #10) then Buf.Append(C) else Buf.Append(' ');
      end
      else if InBlockCmt then
      begin
        if (C = '*') and (C2 = '/') then
        begin
          InBlockCmt:= False;
          Buf.Append('  ');
          Inc(I, 2);
          Continue;
        end;
        if (C = #13) or (C = #10) then Buf.Append(C) else Buf.Append(' ');
      end
      else if InString then
      begin
        if C = '''' then
        begin
          if C2 = '''' then
          begin
            Buf.Append('  ');
            Inc(I, 2);
            Continue;
          end
          else InString:= False;
        end;
        if (C = #13) or (C = #10) then Buf.Append(C)
        else if C = '''' then Buf.Append('''')
        else Buf.Append(' ');
      end
      else
      begin
        if (C = '-') and (C2 = '-') then begin InLineCmt:= True; Buf.Append(' '); end
        else if (C = '/') and (C2 = '*') then begin InBlockCmt:= True; Buf.Append(' '); end
        else if C = '''' then begin InString:= True; Buf.Append(''''); end
        else Buf.Append(C);
      end;
      Inc(I);
    end; // while
    Result:= Buf.ToString;
  finally
    Buf.Free;
  end; // try
end; // function

function FindMatchingParen(const AText: string; AOpenIdx: Integer): Integer;
{ Scans from the '(' at AOpenIdx for the matching ')'. Returns 0 on no match.
  String/comment-stripped text only -- callers must pass the cleaned text. }
var
  Depth: Integer;
  I    : Integer;
  N    : Integer;
begin
  Result:= 0;
  N:= Length(AText);
  if (AOpenIdx < 1) or (AOpenIdx > N) or (AText[AOpenIdx] <> '(') then Exit;
  Depth:= 0;
  for I:= AOpenIdx to N do
  begin
    if AText[I]      = '(' then Inc(Depth)
    else if AText[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(I);
    end;
  end;
end;

procedure ParseColumnList(const AText: string; ATableIdx: Integer; const ATableName: string; AStartPos, AEndPos: Integer; AState: TSqlState);
{ Splits a comma-separated column-def list at the top level (respecting
  nested parens used in NUMERIC(10,2) etc.) and emits a sql_column per item.
  ATableIdx is the table's symbol index for parent linkage. }
var
  Depth   : Integer;
  I       : Integer;
  Start   : Integer;
  Name    : string ;
  TypeText: string ;
  AbsStart: Integer;
  ColLine : Integer;
  ColCol  : Integer;

  procedure FlushItem(AItemStart, AItemEnd: Integer);
  var
    Item   : string ;
    Trimmed: string ;
    P      : Integer;
    J      : Integer;
  begin
    Item:= Copy(AText, AItemStart, AItemEnd - AItemStart + 1);
    Trimmed:= Trim(Item);
    if Trimmed = '' then Exit;
    { Skip table-level constraint clauses. }
    if AnsiStartsText('PRIMARY KEY', Trimmed) then Exit;
    if AnsiStartsText('FOREIGN KEY', Trimmed) then Exit;
    if AnsiStartsText('UNIQUE'     , Trimmed) then Exit;
    if AnsiStartsText('CHECK'      , Trimmed) then Exit;
    if AnsiStartsText('CONSTRAINT' , Trimmed) then Exit;
    { Pull the first word as the column name; rest is the type/signature. }
    J:= 1;
    while (J <= Length(Trimmed)) and (CharInSet(Trimmed[J], ['A'..'Z','a'..'z','0'..'9','_','$'])) do Inc(J);
    Name:= Trim(Copy(Trimmed, 1, J - 1));
    TypeText:= Trim(Copy(Trimmed, J + 1, MaxInt));
    if Name = '' then Exit;
    ComputeLineCol(AText, AItemStart, ColLine, ColCol);
    AState.AddSymbol(skSqlColumn, Name, ATableName + '.' + Name, ATableIdx, ColLine, ColCol, ColLine, ColCol + Length(Name), TypeText);
  end; // procedure

begin
  if (AStartPos < 1) or (AEndPos < AStartPos) then Exit;
  Depth:= 0;
  Start:= AStartPos;
  for I:= AStartPos to AEndPos do
  begin
    case AText[I] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      ',': if Depth = 0 then
      begin
        FlushItem(Start, I - 1);
        Start:= I + 1;
      end;
    end;
  end;
  FlushItem(Start, AEndPos);
end; // begin

// v10: read the single-quoted message after `CREATE EXCEPTION name`. AScanFrom
// is 1-based, just past the name. Skips whitespace; if the next non-space char
// is a quote, decodes the literal ('' -> ') and returns it, setting AOpenPos/
// AClosePos (1-based) to the opening/closing quote positions. Returns '' with
// AOpenPos=0 when no string follows (a bare re-raise).
function ReadSqlExceptionMessage(const ARaw: string; AScanFrom: Integer;
  out AOpenPos, AClosePos: Integer): string;
var i, n: Integer; ch: Char;
begin
  Result:= ''; AOpenPos:= 0; AClosePos:= 0;
  n:= Length(ARaw);
  i:= AScanFrom;
  while (i <= n) and (ARaw[i] <= ' ') do Inc(i);
  if (i > n) or (ARaw[i] <> '''') then Exit;
  AOpenPos:= i;
  Inc(i);
  while i <= n do
  begin
    ch:= ARaw[i];
    if ch = '''' then
    begin
      if (i < n) and (ARaw[i + 1] = '''') then
      begin
        Result:= Result + '''';
        Inc(i, 2);
        Continue;
      end
      else
      begin
        AClosePos:= i;
        Break;
      end;
    end;
    Result:= Result + ch;
    Inc(i);
  end;
end;

{ ---- TFirebirdSqlParser ---- }

function TFirebirdSqlParser.LanguageName: string;
begin
  Result:= 'firebird-sql';
end;

function TFirebirdSqlParser.FileExtensions: TArray<string>;
begin
  Result:= ['.sql'];
end;

function TFirebirdSqlParser.Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
var
  State  : TSqlState;
  Raw    : string   ;
  Cleaned: string   ;
  RxTable: TRegEx   ;
  RxGen  : TRegEx   ;
  RxTrig : TRegEx   ;
  RxView : TRegEx   ;
  RxProc : TRegEx   ;
  RxExc  : TRegEx   ;
  RxDom  : TRegEx   ;
  RxIdx  : TRegEx   ;
  M      : TMatch   ;
  Line   : Integer  ;
  Col    : Integer  ;
  EndLine: Integer  ;
  EndCol : Integer  ;
  Name   : string   ;
  Idx    : Integer  ;
  OpenP  : Integer  ;
  CloseP : Integer  ;
begin
  Result:= Default(TParseResult);
  Raw:= TEncoding.UTF8.GetString(ASource);
  { Decode strict-ANSI fallback: project rule says .pas/.dfm are 7-bit ANSI,
    SQL is the same. UTF-8 decoder handles ASCII transparently. }
  Cleaned:= StripCommentsAndStrings(Raw);

  State:= TSqlState.Create(Raw);
  try
    RxTable:= TRegEx.Create( '\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*\(', [roIgnoreCase]);
    RxGen:= TRegEx.Create( '\bCREATE\s+(?:GENERATOR|SEQUENCE)\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxTrig:= TRegEx.Create( '\bCREATE\s+(?:OR\s+ALTER\s+)?TRIGGER\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+(?:FOR|ON)\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxView:= TRegEx.Create( '\bCREATE\s+(?:OR\s+ALTER\s+)?VIEW\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxProc:= TRegEx.Create( '\bCREATE\s+(?:OR\s+ALTER\s+)?PROCEDURE\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxExc:= TRegEx.Create( '\bCREATE\s+EXCEPTION\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxDom:= TRegEx.Create( '\bCREATE\s+DOMAIN\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);
    RxIdx:= TRegEx.Create( '\bCREATE\s+(?:UNIQUE\s+)?(?:ASC|DESC|ASCENDING|DESCENDING)?\s*INDEX\s+([A-Za-z_$][A-Za-z0-9_$]*)\s+ON\s+([A-Za-z_$][A-Za-z0-9_$]*)', [roIgnoreCase]);

    { ---- CREATE TABLE + columns ---- }
    M:= RxTable.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      { Find paren of the column list (the regex anchors at the '(' that ends
        the match -- we need its position in the cleaned text). }
      OpenP:= M.Index + M.Length - 1;
      CloseP:= FindMatchingParen(Cleaned, OpenP);
      if CloseP > OpenP then ComputeLineCol(Raw, CloseP, EndLine, EndCol)
      else
      begin
        EndLine:= Line;
        EndCol:= Col + Length(Name);
      end;
      Idx:= State.AddSymbol(skSqlTable, Name, Name, -1, Line, Col, EndLine, EndCol);
      if CloseP > OpenP then ParseColumnList(Raw, Idx, Name, OpenP + 1, CloseP - 1, State);
      M:= M.NextMatch;
    end; // while

    { ---- CREATE GENERATOR / SEQUENCE ---- }
    M:= RxGen.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlGenerator, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      M:= M.NextMatch;
    end;

    { ---- CREATE TRIGGER ---- (emits a ref to the target table) }
    M:= RxTrig.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      Idx:= State.AddSymbol(skSqlTrigger, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      State.AddRef('sql_table_ref', M.Groups[2].Value, Line, Col, Line, Col + M.Length);
      M:= M.NextMatch;
    end;

    M:= RxView.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlView, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      M:= M.NextMatch;
    end;

    M:= RxProc.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlProcedure, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      M:= M.NextMatch;
    end;

    M:= RxExc.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlException, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      // v10: harvest the exception message text for the text index.
      var OpenPos, ClosePos: Integer;
      var Msg: string;
      Msg:= ReadSqlExceptionMessage(Raw, M.Groups[1].Index + M.Groups[1].Length, OpenPos, ClosePos);
      if (Msg <> '') and (OpenPos > 0) then
      begin
        var MLine, MCol, ELine, ECol: Integer;
        ComputeLineCol(Raw, OpenPos, MLine, MCol);
        if ClosePos > 0 then ComputeLineCol(Raw, ClosePos, ELine, ECol)
        else begin ELine:= MLine; ECol:= MCol + Length(Msg); end;
        var Lit: TStringLiteral;
        Lit:= Default(TStringLiteral);
        Lit.Source:= 'sql'; Lit.Kind:= 'sql-exception'; Lit.OwnerName:= Name; Lit.Text:= Msg;
        Lit.StartLine:= MLine; Lit.StartCol:= MCol;
        Lit.EndLine:= ELine; Lit.EndCol:= ECol + 1;
        State.Literals.Add(Lit);
      end;
      M:= M.NextMatch;
    end;

    M:= RxDom.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlDomain, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      M:= M.NextMatch;
    end;

    M:= RxIdx.Match(Cleaned);
    while M.Success do
    begin
      Name:= M.Groups[1].Value;
      ComputeLineCol(Raw, M.Index, Line, Col);
      State.AddSymbol(skSqlIndex, Name, Name, -1, Line, Col, Line, Col + Length(Name));
      State.AddRef('sql_table_ref', M.Groups[2].Value, Line, Col, Line, Col + M.Length);
      M:= M.NextMatch;
    end;

    Result.Symbols   := State.Symbols   .ToArray;
    Result.References:= State.References.ToArray;
    Result.Literals  := State.Literals  .ToArray;
  finally
    State.Free;
  end; // try
end; // function

end.
