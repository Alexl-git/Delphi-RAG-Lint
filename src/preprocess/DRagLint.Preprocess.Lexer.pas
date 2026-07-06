unit DRagLint.Preprocess.Lexer;

// Directive lexer -- byte-faithful port of tree-sitter-delphi13
// preprocessor/lexer.js (the lex() function). Emits a flat sequence of chunks:
// plain-text spans and recognized compiler-directive records. The evaluator
// (Task 3) and chunk processor (later tasks) consume this sequence.
//
// SCANNER MODEL: the JS uses charCodeAt over a UTF-16 string and documents its
// srcStart/srcEnd as BYTE offsets into the input. To make that exact for our
// corpus -- where directive bytes are ASCII but text spans can carry non-ASCII
// UTF-8 bytes (e.g. 0xAE / 0xA9 in real Delphi source) -- we scan the input's
// UTF-8 TBytes directly, so SrcStart/SrcEnd are byte offsets BY CONSTRUCTION,
// not char counts. Only the directive keyword/args slices and text-chunk Value
// are converted back to string for the chunk fields.
//
// ENCODING NOTE: this feature is ABOUT braces, so this unit never writes a bare
// brace inside a comment. Directive/brace/dollar literals in code are byte
// constants: 123 = open-brace, 125 = close-brace, 36 = dollar, 39 = quote,
// 47 = slash, 40 = open-paren, 42 = asterisk, 41 = close-paren, 10 = newline.
//
// Directive forms recognized (known keyword set): define, undef, ifdef, ifndef,
// if, ifopt, ifend, else, elseif, endif, i, include. Anything else under a
// dollar-directive is passthrough -- emitted as a TEXT chunk so the downstream
// parser still sees the directive bytes as a regular pp token.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Preprocess.Types;

/// <summary>Lexes AInput into a flat chunk stream: plain-text spans and
/// recognized compiler directives. A byte-faithful port of lexer.js lex().</summary>
/// <param name="AInput">The source text. Converted to UTF-8 bytes internally so
/// SrcStart/SrcEnd on every chunk are exact byte offsets into that UTF-8
/// encoding (matching tree-sitter's byte model).</param>
/// <returns>The chunks in source order. Text chunks carry Value + span; directive
/// chunks carry lowercased Dir + trimmed Args + span + 0-based Line. Comments and
/// string literals are skipped (their bytes stay inside surrounding text chunks);
/// unknown dollar-directives become passthrough TEXT chunks.</returns>
/// <remarks>Concatenating every chunk's [SrcStart, SrcEnd) span, in order,
/// reproduces the whole input UTF-8 byte stream exactly (no gaps, no overlaps).</remarks>
function LexDirectives(const AInput: string): TArray<TPPChunk>;

implementation

// The known directive keyword set. Membership decides directive-vs-passthrough
// (lexer.js DIR_KEYWORDS). Compared against a lowercased keyword.
function IsKnownKeyword(const AKw: string): Boolean;
begin
  Result:=
       (AKw = 'define') or (AKw = 'undef')
    or (AKw = 'ifdef')  or (AKw = 'ifndef') or (AKw = 'if')
    or (AKw = 'ifopt')  or (AKw = 'ifend')
    or (AKw = 'else')   or (AKw = 'elseif') or (AKw = 'endif')
    or (AKw = 'i')      or (AKw = 'include');
end;

// True when ByteVal is an ASCII letter [A-Za-z] (the keyword character class).
function IsAsciiLetter(AByte: Byte): Boolean;
begin
  Result:= ((AByte >= 65) and (AByte <= 90)) or ((AByte >= 97) and (AByte <= 122));
end;

// Decodes a byte slice [AStart, AEnd) of ABytes back to a Delphi string as UTF-8.
function SliceToStr(const ABytes: TBytes; AStart, AEnd: Integer): string;
var
  Len: Integer;
  Sub: TBytes;
begin
  Len:= AEnd - AStart;
  if Len <= 0 then Exit('');
  SetLength(Sub, Len);
  Move(ABytes[AStart], Sub[0], Len);
  Result:= TEncoding.UTF8.GetString(Sub);
end;

function LexDirectives(const AInput: string): TArray<TPPChunk>;
var
  Bytes    : TBytes           ;
  N        : Integer          ;
  I        : Integer          ;
  TextStart: Integer          ;
  Chunks   : TList<TPPChunk>  ;
  Newlines : TList<Integer>   ;
  K        : Integer          ;

  // Emits a text chunk for [TextStart, AEnd) only when TextStart < AEnd.
  procedure FlushText(AEnd: Integer);
  var
    Ch: TPPChunk;
  begin
    if TextStart < AEnd then
    begin
      Ch:= Default(TPPChunk);
      Ch.Kind    := ckText;
      Ch.Value   := SliceToStr(Bytes, TextStart, AEnd);
      Ch.SrcStart:= TextStart;
      Ch.SrcEnd  := AEnd;
      Chunks.Add(Ch);
    end;
  end;

  // Binary search over the sorted newline byte positions -> 0-based line index.
  // Ported EXACTLY from lexer.js:62-69 (lo=0, hi=len; mid=(lo+hi) shr 1;
  // if newlines[mid] < pos then lo:=mid+1 else hi:=mid; return lo).
  function LineAt(APos: Integer): Integer;
  var
    Lo, Hi, Mid: Integer;
  begin
    Lo:= 0; Hi:= Newlines.Count;
    while Lo < Hi do
    begin
      Mid:= (Lo + Hi) shr 1;
      if Newlines[Mid] < APos then Lo:= Mid + 1 else Hi:= Mid;
    end;
    Result:= Lo;
  end;

var
  Start  : Integer ;
  KwStart: Integer ;
  Kw     : string  ;
  ArgStart: Integer;
  ArgEnd : Integer ;
  Depth  : Integer ;
  Ch     : TPPChunk;
begin
  Bytes:= TEncoding.UTF8.GetBytes(AInput);
  N:= Length(Bytes);
  I:= 0;
  TextStart:= 0;

  Chunks  := TList<TPPChunk>.Create;
  Newlines:= TList<Integer>.Create;
  try
    // Precompute sorted newline byte positions once (byte 10 = LF).
    for K:= 0 to N - 1 do
      if Bytes[K] = 10 then Newlines.Add(K);

    while I < N do
    begin
      // // line comment -- passthrough (47 = slash). Skip to newline.
      if (Bytes[I] = 47) and (I + 1 < N) and (Bytes[I + 1] = 47) then
      begin
        while (I < N) and (Bytes[I] <> 10) do Inc(I);
        Continue;
      end;

      // (* ... *) block comment -- passthrough (40 = open-paren, 42 = asterisk,
      // 41 = close-paren).
      if (Bytes[I] = 40) and (I + 1 < N) and (Bytes[I + 1] = 42) then
      begin
        Inc(I, 2);
        while (I < N - 1) and not ((Bytes[I] = 42) and (Bytes[I + 1] = 41)) do Inc(I);
        // Math.min(n, i + 2) -- consume the closing star-paren without overrun.
        if I + 2 < N then I:= I + 2 else I:= N;
        Continue;
      end;

      // String literal -- skip without interpreting any brace inside (39 = quote).
      if Bytes[I] = 39 then
      begin
        Inc(I);
        while (I < N) and not ((Bytes[I] = 39) and ((I + 1 >= N) or (Bytes[I + 1] <> 39))) do
        begin
          // Doubled quote = escaped quote: consume both bytes and continue.
          if (Bytes[I] = 39) and (I + 1 < N) and (Bytes[I + 1] = 39) then
          begin
            Inc(I, 2);
            Continue;
          end;
          Inc(I);
        end;
        if I < N then Inc(I); // consume the closing quote
        Continue;
      end;

      // Open-brace (123): dollar-directive (if next byte is 36) or brace comment.
      if Bytes[I] = 123 then
      begin
        if (I + 1 < N) and (Bytes[I + 1] = 36) then
        begin
          // Directive. Flush preceding text first.
          FlushText(I);
          Start:= I;
          Inc(I, 2); // past the open-brace + dollar
          // Read the directive keyword [A-Za-z]* and lowercase it.
          KwStart:= I;
          while (I < N) and IsAsciiLetter(Bytes[I]) do Inc(I);
          Kw:= LowerCase(SliceToStr(Bytes, KwStart, I));
          // Read arguments up to the matching close-brace (125), depth-counted.
          ArgStart:= I;
          Depth:= 1;
          while (I < N) and (Depth > 0) do
          begin
            if Bytes[I] = 125 then
            begin
              Dec(Depth);
              if Depth = 0 then Break;
            end;
            Inc(I);
          end;
          ArgEnd:= I;
          if I < N then Inc(I); // consume the close-brace

          Ch:= Default(TPPChunk);
          if IsKnownKeyword(Kw) then
          begin
            Ch.Kind    := ckDirective;
            Ch.Dir     := Kw;
            Ch.Args    := Trim(SliceToStr(Bytes, ArgStart, ArgEnd));
            Ch.SrcStart:= Start;
            Ch.SrcEnd  := I;
            Ch.Line    := LineAt(Start);
          end
          else
          begin
            // Unknown / passthrough directive -- emit as a TEXT chunk so the
            // downstream parser still sees the directive bytes as a pp token.
            Ch.Kind    := ckText;
            Ch.Value   := SliceToStr(Bytes, Start, I);
            Ch.SrcStart:= Start;
            Ch.SrcEnd  := I;
          end;
          Chunks.Add(Ch);
          // Advance TextStart past it either way so the next FlushText does not
          // re-emit the directive bytes (the O(N^2) guard, lexer.js:129-130).
          TextStart:= I;
          Continue;
        end;
        // Brace comment -- passthrough. Skip to the close-brace (125), consume it.
        while (I < N) and (Bytes[I] <> 125) do Inc(I);
        if I < N then Inc(I);
        Continue;
      end;

      Inc(I);
    end;

    FlushText(N);
    Result:= Chunks.ToArray;
  finally
    Chunks.Free;
    Newlines.Free;
  end;
end;

end.
