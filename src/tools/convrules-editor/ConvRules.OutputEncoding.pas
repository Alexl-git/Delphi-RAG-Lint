unit ConvRules.OutputEncoding;

{ OUTENC (2026-10-27): the pure decisions behind how the editor reads the engine's
  pipes. Engine 1.36.0 writes stdout/stderr as ASCII with \uXXXX escapes by default
  (or in the "outputEncoding" a .drag-lint.json names) and accepts the global
  --output-encoding ascii|utf8|utf16; older engines write the system ANSI code page
  (R7) and REJECT the flag (exit 3, unknown-flag). So the editor passes
  --output-encoding utf8 and decodes the pipes as UTF-8 exactly when the engine's
  `info --json` version says it understands the flag, and otherwise keeps CP_ACP.
  No VCL, no engine call: pinned by ConvRulesModelTests (outenc.*). }

interface

uses
  System.SysUtils;

const
  /// <summary>The first engine that accepts --output-encoding (ENGINE lane OUTENC,
  /// dd742f83, shipped in 1.36.0).</summary>
  /// <remarks>No `info --json` capability reports the flag (1.36.0 lists none), so the gate
  /// is the version. Only the numbers count: 1.36.0-alpha is 1.36.0.</remarks>
  OUTPUT_ENCODING_MIN_ENGINE_VERSION = '1.36.0';

/// <summary>PURE: does the engine that wrote this `info --json` output accept
/// --output-encoding?</summary>
/// <param name="AInfoOutput">Raw `info --json` output; the JSON is sliced from the first '{'
/// to the last '}' (the "(loaded defaults from ...)" line shares the pipe).</param>
/// <returns>True when its "version" is at or above OUTPUT_ENCODING_MIN_ENGINE_VERSION; False
/// for an older engine, a missing or unreadable version, or output that is not a JSON object.</returns>
function SupportsOutputEncoding(const AInfoOutput: string): Boolean;

/// <summary>PURE: the argument that selects the engine's pipe encoding.</summary>
/// <param name="AUtf8">True when the engine accepts --output-encoding (SupportsOutputEncoding).</param>
/// <returns>' --output-encoding utf8' (leading space, ready to append to a command line) or ''
/// -- an older engine rejects the flag on every verb but --version.</returns>
/// <remarks>Passed explicitly even though utf8 may be the configured default: the flag
/// overrides a "outputEncoding" key in .drag-lint.json, so the editor never decodes in a mode
/// the user's config chose behind its back.</remarks>
function OutputEncodingArgs(AUtf8: Boolean): string;

/// <summary>PURE: the code page the editor decodes the engine's pipes in.</summary>
/// <param name="AUtf8">As for OutputEncodingArgs.</param>
/// <returns>CP_UTF8 when the flag is passed, else CP_ACP (R7: the pre-1.36 contract).</returns>
function PipeCodePage(AUtf8: Boolean): Cardinal;

/// <summary>PURE: how many leading bytes of ABytes end on a UTF-8 character boundary.</summary>
/// <param name="ABytes">Pipe bytes, possibly cut inside a multi-byte sequence.</param>
/// <returns>Length(ABytes) minus an incomplete trailing sequence (a lead byte followed by
/// fewer continuation bytes than it announces); the whole length when the bytes end on a
/// boundary or the tail is not a valid sequence start (invalid bytes are never held back).</returns>
function Utf8CompletePrefixLen(const ABytes: TBytes): Integer;

implementation

uses
  System.JSON,
  ConvRules.CapabilityProbe;

const
  UTF8_FLAG = ' --output-encoding utf8';
  UTF8_MAX_SEQ = 4;
  UTF8_SEQ3 = 3;
  UTF8_CONT_MASK = $C0; // the top two bits of a byte
  UTF8_CONT_BITS = $80; // ... are 10 in a continuation byte

function SupportsOutputEncoding(const AInfoOutput: string): Boolean;
var
  Root: TJSONValue;
  LText: string;
  LHave, LNeed: TEngineVersion;
begin
  Result:= False;
  var LFirst: Integer:= Pos('{', AInfoOutput);
  var LLast : Integer:= LastDelimiter('}', AInfoOutput);
  if (LFirst = 0) or (LLast < LFirst) then
    Exit;
  Root:= TJSONObject.ParseJSONValue(Copy(AInfoOutput, LFirst, LLast - LFirst + 1));
  try
    if not ((Root is TJSONObject) and TJSONObject(Root).TryGetValue<string>('version', LText)) then
      Exit;
  finally
    Root.Free;
  end; // try
  TryParseEngineVersion(OUTPUT_ENCODING_MIN_ENGINE_VERSION, LNeed);
  Result:= TryParseEngineVersion(LText, LHave) and (CompareEngineVersions(LHave, LNeed) >= 0);
end;

function OutputEncodingArgs(AUtf8: Boolean): string;
begin
  Result:= if AUtf8 then UTF8_FLAG else '';
end;

function PipeCodePage(AUtf8: Boolean): Cardinal;
begin
  Result:= if AUtf8 then CP_UTF8 else CP_ACP;
end;

// The sequence length a UTF-8 lead byte announces; 0 for a continuation or invalid byte.
function Utf8SeqLen(AByte: Byte): Integer;
begin
  case AByte of
    $00..$7F: Result:= 1;
    $C2..$DF: Result:= 2;
    $E0..$EF: Result:= UTF8_SEQ3;
    $F0..$F4: Result:= UTF8_MAX_SEQ;
  else
    Result:= 0;
  end;
end;

function Utf8CompletePrefixLen(const ABytes: TBytes): Integer;
begin
  Result:= Length(ABytes);
  // Walk back over at most three continuation bytes to the byte that starts the last sequence.
  var LStart: Integer:= Result - 1;
  while (LStart >= 0) and (Result - LStart < UTF8_MAX_SEQ) and ((ABytes[LStart] and UTF8_CONT_MASK) = UTF8_CONT_BITS) do
    Dec(LStart);
  if LStart < 0 then
    Exit;
  var LNeed: Integer:= Utf8SeqLen(ABytes[LStart]);
  if (LNeed > 1) and (Result - LStart < LNeed) then
    Result:= LStart;
end;

end.
