unit DragLint.Plugin.CompletionText;

{ How one completion row READS: its kind word, and its signature split into a
  parameter list and a return type.

  PURE, and separate from DragLint.Plugin.CompletionForm because that unit pulls
  in the VCL and ToolsAPI and so cannot be exercised by a console harness. This
  can -- run_completion_text_guard.ps1 does -- which matters because everything
  here is user-visible text that drifts silently when it is wrong.

  WHAT THE OWNER ASKED FOR (live IDE, 2026-08-19):
    "the IDE autocomplete provides a full type - procedure instead of p etc.
     ... functions should show returned types. Could be procedures should show
     optional parameters. Not just prompt split for a string, but split(...)"

  So: the kind spelled out, the parameter list kept attached to the name, and
  the return type rendered after a colon. }

interface

uses
  System.SysUtils;

/// <summary>The LSP CompletionItemKind as the word Delphi itself uses.</summary>
/// <param name="AKind">LSP CompletionItemKind number.</param>
/// <returns>'procedure', 'function', 'property', ... or '' for a kind with no
/// natural Delphi word.</returns>
/// <remarks>This used to return a single letter -- 'p' for a property, 'f' for
/// a function -- which is a legend the reader must have memorised. The IDE's
/// own completion list never asks that.</remarks>
function CompletionKindWord(AKind: Integer): string;

/// <summary>Splits a stored signature into its parameter list and return type.</summary>
/// <param name="ASignature">TSymbol.Signature as the engine sends it in
/// `detail`: '(const S: string): string' for a routine, or the bare declared
/// type 'Boolean' for a property, field or variable.</param>
/// <param name="AParams">Receives '(const S: string)', parentheses included;
/// empty when the symbol takes none.</param>
/// <param name="AReturn">Receives 'string'; for a non-routine this is the
/// declared type, which is the whole signature.</param>
/// <remarks>Walks to the MATCHING close parenthesis rather than the first one:
/// a parameter's own type can carry parentheses, and cutting at the first
/// would split a parameter in half. An unbalanced signature is shown verbatim
/// rather than guessed at.</remarks>
procedure SplitCompletionSignature(const ASignature: string; out AParams, AReturn: string);

implementation

function CompletionKindWord(AKind: Integer): string;
begin
  case AKind of
    2 : Result:= 'method'     ;
    3 : Result:= 'function'   ;
    4 : Result:= 'constructor';
    5 : Result:= 'field'      ;
    6 : Result:= 'variable'   ;
    7 : Result:= 'class'      ;
    8 : Result:= 'interface'  ;
    9 : Result:= 'unit'       ;
    10: Result:= 'property'   ;
    13: Result:= 'enum'       ;
    21: Result:= 'const'      ;
    22: Result:= 'record'     ;
  else
    Result:= '';
  end;
end;

procedure SplitCompletionSignature(const ASignature: string; out AParams, AReturn: string);
var
  Depth, i, CloseAt: Integer;
  Sig              : string ;
begin
  AParams:= '';
  AReturn:= '';
  Sig    := Trim(ASignature);
  if Sig = '' then Exit;

  if Sig[Low(string)] <> '(' then
  begin
    { No parameter list: the signature IS the declared type -- a property, a
      field, a variable, an enum value's ordinal. }
    AReturn:= Sig;
    Exit;
  end;

  Depth  := 0;
  CloseAt:= 0;
  for i:= Low(string) to High(Sig) do
  begin
    if      Sig[i] = '(' then Inc(Depth)
    else if Sig[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        CloseAt:= i;
        Break;
      end;
    end;
  end;

  if CloseAt = 0 then
  begin
    { Unbalanced. Show it verbatim: inventing a split would put half a
      parameter where a return type belongs. }
    AParams:= Sig;
    Exit;
  end;

  AParams:= Copy(Sig, Low(string), CloseAt - Low(string) + 1);
  AReturn:= Trim(Copy(Sig, CloseAt + 1, MaxInt));
  if (AReturn <> '') and (AReturn[Low(string)] = ':') then
    AReturn:= Trim(Copy(AReturn, Low(string) + 1, MaxInt));
end;

end.
