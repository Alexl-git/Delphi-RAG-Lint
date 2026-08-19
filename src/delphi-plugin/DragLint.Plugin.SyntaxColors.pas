unit DragLint.Plugin.SyntaxColors;

{ The IDE's editor colours, resolved once and shared by every drag-lint popup.

  WHY IT EXISTS. This lived inside TDragLintHoverForm as a private method over a
  private field, so the hover popup rendered in the user's theme and the
  COMPLETION popup -- a plain TListBox drawing one flat string per row -- did
  not. Reported 2026-08-19: "The popup that we get for autocompletion is still
  not colored as the theme."

  Two popups reading one palette is the point: a role that renders blue in the
  hover cannot render grey in the completion list, because there is only one
  place that decides.

  REAL COLOUR WITH FALLBACK. When the IDE's editor-colour interface is
  available, the user's own configured colour for the mapped TOTASyntaxCode
  wins. On a nil interface, a clNone/clDefault answer, or any exception, the
  fixed CL_* palette below is used. Resolve the interface ONCE per render and
  pass it in -- never once per token. }

interface

uses
  Vcl.Graphics
  , ToolsAPI
  , ToolsAPI.Editor   { INTACodeEditorServices / INTACodeEditorOptions }
  ;

type
  /// <summary>What a token MEANS, which is what decides its colour -- as
  /// opposed to what it looks like.</summary>
  TDLSynRole = (srKeyword, srType, srName, srParam, srOperator, srLiteralNum,
                srLiteralStr, srMuted, srSection, srError, srKind);

const
  { Fixed fallback palette (light-theme base), used when the IDE editor colours
    are unavailable. Every value is still run through the contrast guard against
    the actual background before it is emitted. TColor is BGR, so these bytes
    are the reverse of the #RRGGBB the comments name. }
  CL_KEYWORD = TColor($00D0570B); // #0B57D0 blue
  CL_TYPE    = TColor($003C7A21); // #217A3C green
  CL_NAME    = TColor($00DB561A); // #1A56DB
  CL_PARAM   = TColor($00C1426F); // #6F42C1
  CL_OP      = TColor($00333333);
  CL_LITNUM  = TColor($001515A3); // #A31515
  CL_LITSTR  = TColor($001515A3);
  CL_MUT     = TColor($008A8A8A);
  { Section headers -- a strong blue, distinct from the softer keyword blue. }
  CL_SECTION = TColor($00D66015); // #1560D6
  { Diagnostic text. A deep red rather than pure #FF0000 so it survives the
    contrast guard on a light background without vibrating, and stays legible
    when that guard lightens it for a dark one. }
  CL_ERROR   = TColor($001C2BC4); // #C42B1C
  { The KIND word ('function', 'property', ...). Gold, and a ROLE rather than a
    literal at one call site, so the hover popup can adopt the same word in the
    same colour without a second decision being made somewhere else -- which is
    the reason this whole unit exists. It was drawn with srKeyword, i.e. the
    same blue as a reserved word, which made "function" look like part of the
    signature instead of a label ON it. }
  CL_KIND    = TColor($000B86B8); // #B8860B gold

/// <summary>The IDE's editor-colour interface, or nil.</summary>
/// <returns>The interface, or nil when it cannot be obtained.</returns>
/// <remarks>Guarded: never raises. Call ONCE per render and pass the result to
/// SyntaxColorFor; resolving per token is what this signature exists to
/// prevent.</remarks>
function AcquireEditorColors: INTACodeEditorOptions;

/// <summary>The colour for one syntax role.</summary>
/// <param name="AOpts">From AcquireEditorColors; nil is fine and yields the
/// fixed fallback.</param>
/// <param name="ARole">What the token means.</param>
/// <returns>A concrete TColor, never clNone or clDefault.</returns>
/// <remarks>srType, srSection and srKind deliberately IGNORE the IDE and return
/// fixed colours. The IDE's atIdentifier is dark or grey on most themes, which
/// made types indistinguishable from plain names; a fixed green reads as "this
/// is a type" at a glance. The IDE has no "section header" or "kind label"
/// syntax kind at all -- they describe a symbol rather than appearing in
/// source, so there is nothing for the editor's palette to map them to.</remarks>
function SyntaxColorFor(const AOpts: INTACodeEditorOptions; ARole: TDLSynRole): TColor;

implementation

uses
  System.SysUtils;

function AcquireEditorColors: INTACodeEditorOptions;
var
  Svcs: INTACodeEditorServices;
begin
  Result:= nil;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svcs) then Result:= Svcs.Options;
  except
    Result:= nil;
  end;
end;

function SyntaxColorFor(const AOpts: INTACodeEditorOptions; ARole: TDLSynRole): TColor;
var
  Code    : TOTASyntaxCode;
  Fallback: TColor        ;
  C       : TColor        ;
begin
  case ARole of
    srKeyword   : begin Code:= atReservedWord; Fallback:= CL_KEYWORD; end;
    srType      : Exit(CL_TYPE);     { fixed on purpose -- see the remarks }
    srName      : begin Code:= atIdentifier  ; Fallback:= CL_NAME   ; end;
    srParam     : begin Code:= atIdentifier  ; Fallback:= CL_PARAM  ; end;
    srOperator  : begin Code:= atSymbol      ; Fallback:= CL_OP     ; end;
    srLiteralNum: begin Code:= atNumber      ; Fallback:= CL_LITNUM ; end;
    srLiteralStr: begin Code:= atString      ; Fallback:= CL_LITSTR ; end;
    srMuted     : begin Code:= atComment     ; Fallback:= CL_MUT    ; end;
    srSection   : Exit(CL_SECTION);  { the IDE has no such syntax kind }
    srError     : Exit(CL_ERROR  );
    srKind      : Exit(CL_KIND   );  { a LABEL, not a token -- no IDE equivalent }
  else
    begin Code:= atIdentifier; Fallback:= CL_NAME; end;
  end;

  Result:= Fallback;
  if AOpts = nil then Exit;
  try
    C:= AOpts.GetFontColor(Code);
    { clNone/clDefault mean "the theme did not say", not "draw it invisible". }
    if (C <> clNone) and (C <> clDefault) then Result:= C;
  except
    Result:= Fallback;
  end;
end;

end.
