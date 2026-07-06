unit DRagLint.Preprocess;

// PP-Task-4: the chunk processor -- the core of tree-sitter-delphi13
// preprocessor/preprocess.js (the preprocess() function). Walks the lexer's
// chunk stream, maintains a defines table + a nested-IF state stack, and emits
// a preprocessed byte buffer where INACTIVE branches and ALL directives are
// BLANKED to spaces with newlines preserved.
//
// THE OFFSET-IDENTITY INVARIANT (the whole point of this design):
//   Length(Preprocess(bytes)) = Length(bytes)   -- in BYTES.
// Because output length == input length byte-for-byte, tree-sitter spans over
// the resolved text map 1:1 back to the original file with NO source map. So
// ALL blanking is done at the BYTE level: for each chunk we operate on the
// ORIGINAL input bytes AUtf8[SrcStart..SrcEnd) (not a re-encoded copy of the
// chunk's Value string), guaranteeing the byte count is preserved even if a
// text span carries multi-byte UTF-8. A blanked byte is a space (byte 32); the
// ONLY byte preserved through blanking is LF (byte 10) -- CR (byte 13) is
// blanked like any other non-newline byte, matching the JS regex
// text.replace(/[^\n]/g, ' ').
//
// INCLUDES ARE OUT OF SCOPE FOR THIS TASK. An {$I}/{$INCLUDE} directive is
// simply BLANKED (its bytes -> spaces) here; real include handling (defines-only
// recursion / body splice) lands in Task 6. This mirrors preprocess.js EXCEPT
// its include-body block at lines 149-186.
//
// ENCODING NOTE: this feature is ABOUT braces, so this unit never writes a bare
// brace inside a // comment. Brace/dollar/space/newline literals in code are
// BYTE constants: 32 = space, 10 = newline (LF), 13 = CR.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Preprocess.Types;

/// <summary>Runs the compiler-directive preprocessor over AUtf8 under the given
/// define profile, returning a byte buffer of identical length where inactive
/// conditional branches and every directive are blanked to spaces (newlines
/// preserved). A faithful port of preprocess.js's preprocess() chunk walk,
/// minus include-body expansion (an include directive is blanked in this
/// version).</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Not modified.</param>
/// <param name="AProfile">The active define profile: Defines are lowercased
/// symbol names seeding the live defines set; NumericDefines map lowercased
/// names to integers for {$IF X op N} comparisons.</param>
/// <returns>A new TBytes with Length = Length(AUtf8) exactly (the offset-identity
/// invariant). Active-branch bytes are copied verbatim; inactive-branch and
/// directive bytes are replaced by spaces with LF (byte 10) preserved.</returns>
/// <remarks>Not thread-safe in the sense of sharing state, but has no shared
/// mutable state -- each call builds its own defines dictionary and IF stack.</remarks>
function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes;

implementation

uses
  DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Expr;

type
  // One nested-IF state frame (preprocess.js stack entries):
  //   Active        -- is THIS frame emitting text right now?
  //   TakenBranch   -- has any THEN/ELSEIF branch of this IF already been taken?
  //   AnyOuterFalse -- was some ancestor IF false (whole subtree inactive)?
  TIfState = record
    Active       : Boolean;
    TakenBranch  : Boolean;
    AnyOuterFalse: Boolean;
  end;

function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes;
var
  Src     : string             ;
  Chunks  : TArray<TPPChunk>   ;
  C       : TPPChunk           ;
  Defines : TDictionary<string, Boolean>;
  Numeric : TDictionary<string, Integer>;
  Stack   : TArray<TIfState>   ;
  OutLen  : Integer            ;
  OutPos  : Integer            ;
  D       : string             ;
  P       : TPair<string, Integer>;

  // Every stack frame Active? (preprocess.js effectivelyActive: stack.every).
  function EffectivelyActive: Boolean;
  var
    K: Integer;
  begin
    for K:= 0 to High(Stack) do
      if not Stack[K].Active then Exit(False);
    Result:= True;
  end;

  // Append a run of ACount space bytes (byte 32) at OutPos.
  procedure EmitSpaces(ACount: Integer);
  var
    K: Integer;
  begin
    for K:= 0 to ACount - 1 do
    begin
      Result[OutPos]:= 32;
      Inc(OutPos);
    end;
  end;

  // Emit the chunk's ORIGINAL input bytes [AStart, AEnd). If effectively active,
  // copy them verbatim; else blank every byte to a space EXCEPT LF (byte 10),
  // which is preserved so line numbers stay aligned. Byte-level -> byte-exact.
  procedure BlankifyOrEmit(AStart, AEnd: Integer);
  var
    K   : Integer;
    Live: Boolean;
  begin
    Live:= EffectivelyActive;
    for K:= AStart to AEnd - 1 do
    begin
      if Live then Result[OutPos]:= AUtf8[K]
      else if AUtf8[K] = 10 then Result[OutPos]:= 10
      else Result[OutPos]:= 32;
      Inc(OutPos);
    end;
  end;

  // A directive is ALWAYS blanked (its bytes -> spaces), regardless of active
  // state -- directive text never survives into the resolved output.
  procedure BlankifyDirective(AStart, AEnd: Integer);
  begin
    EmitSpaces(AEnd - AStart);
  end;

  // First whitespace-split token of AArgs, lowercased (JS ch.args.split(/\s+/)[0]).
  // Empty when AArgs is empty/all-whitespace (guards an empty-name add/remove).
  function FirstArgLower(const AArgs: string): string;
  var
    T: string;
  begin
    T:= Trim(AArgs);
    var SpacePos: Integer:= 1;
    while (SpacePos <= Length(T)) and (T[SpacePos] > ' ') do Inc(SpacePos);
    Result:= LowerCase(Copy(T, 1, SpacePos - 1));
  end;

begin
  // Rebuild a string for the lexer (it re-encodes to UTF-8 internally, so the
  // byte offsets it returns index back into AUtf8 identically). We keep AUtf8 as
  // the authoritative byte source for all copying/blanking below.
  Src:= TEncoding.UTF8.GetString(AUtf8);
  Chunks:= LexDirectives(Src);

  OutLen:= Length(AUtf8);
  SetLength(Result, OutLen);
  OutPos:= 0;

  Defines:= TDictionary<string, Boolean>.Create;
  Numeric:= TDictionary<string, Integer>.Create;
  try
    // Seed the live defines set from the profile (already lowercased).
    for D in AProfile.Defines do
      if D <> '' then Defines.AddOrSetValue(LowerCase(D), True);
    for P in AProfile.NumericDefines do
      Numeric.AddOrSetValue(LowerCase(P.Key), P.Value);

    // The base frame: active, branch taken, no outer-false (preprocess.js:50).
    SetLength(Stack, 1);
    Stack[0].Active       := True;
    Stack[0].TakenBranch  := True;
    Stack[0].AnyOuterFalse:= False;

    for C in Chunks do
    begin
      if C.Kind = ckText then
      begin
        BlankifyOrEmit(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      // Directive.
      if (C.Dir = 'define') or (C.Dir = 'undef') then
      begin
        if EffectivelyActive then
        begin
          var Name: string:= FirstArgLower(C.Args);
          if Name <> '' then
          begin
            if C.Dir = 'define' then Defines.AddOrSetValue(Name, True)
            else Defines.Remove(Name);
          end;
        end;
        BlankifyDirective(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      if (C.Dir = 'ifdef') or (C.Dir = 'ifndef') or (C.Dir = 'if') or (C.Dir = 'ifopt') then
      begin
        var Cond: Boolean;
        if C.Dir = 'ifdef' then Cond:= Defines.ContainsKey(LowerCase(C.Args))
        else if C.Dir = 'ifndef' then Cond:= not Defines.ContainsKey(LowerCase(C.Args))
        else if C.Dir = 'if' then Cond:= EvalPPExpr(C.Args, Defines, Numeric)
        else Cond:= False; // ifopt -- conservative
        var OuterInactive: Boolean:= not EffectivelyActive;
        SetLength(Stack, Length(Stack) + 1);
        Stack[High(Stack)].Active       := Cond and (not OuterInactive);
        Stack[High(Stack)].TakenBranch  := Cond;
        Stack[High(Stack)].AnyOuterFalse:= OuterInactive;
        BlankifyDirective(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      if C.Dir = 'else' then
      begin
        // Mutate the TOP frame in place (a record in a dynamic array is a value
        // type; index the array directly so the write persists).
        Stack[High(Stack)].Active     := (not Stack[High(Stack)].TakenBranch)
                                         and (not Stack[High(Stack)].AnyOuterFalse);
        Stack[High(Stack)].TakenBranch:= True;
        BlankifyDirective(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      if C.Dir = 'elseif' then
      begin
        if Stack[High(Stack)].TakenBranch then
          Stack[High(Stack)].Active:= False
        else
        begin
          var Cond2: Boolean:= EvalPPExpr(C.Args, Defines, Numeric);
          Stack[High(Stack)].Active:= Cond2 and (not Stack[High(Stack)].AnyOuterFalse);
          if Cond2 then Stack[High(Stack)].TakenBranch:= True;
        end;
        BlankifyDirective(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      if (C.Dir = 'endif') or (C.Dir = 'ifend') then
      begin
        if Length(Stack) > 1 then SetLength(Stack, Length(Stack) - 1);
        BlankifyDirective(C.SrcStart, C.SrcEnd);
        Continue;
      end;

      // {$I}/{$INCLUDE}: OUT OF SCOPE for this task -- just blank the directive
      // (Task 6 adds real include handling). Any other directive is also blanked
      // (the lexer routes unknown directives to text chunks, so this is a guard).
      BlankifyDirective(C.SrcStart, C.SrcEnd);
    end;
  finally
    Numeric.Free;
    Defines.Free;
  end;
end;

end.
