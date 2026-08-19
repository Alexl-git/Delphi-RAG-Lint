unit DragLint.Plugin.HoverSignature;

{ Composes the one-line display signature the hover popup's header shows.

  PURE, and separate from DragLint.Plugin.HoverForm on purpose: that unit pulls
  in ToolsAPI and the VCL, so nothing in it can be exercised by a console
  harness. This can, which is what run_hover_signature_guard.ps1 does -- same
  arrangement as DragLint.Plugin.CallerFilter.

  THE DEFECT THAT MOVED IT HERE (owner, live IDE, 2026-08-19): "when pointing on
  other properties it doesn't report type. We need type. IDE shows type why not
  us?" Hovering TTimer.Enabled showed `property Vcl.ExtCtrls.TTimer.Enabled`
  with no type at all, while the IDE showed `Enabled: Boolean`.

  The engine was never at fault. `hover --format json` reports, for a property:

      "kind":"property","signature":"Boolean","return_type":"","params":[]

  -- the type is in SIGNATURE. The composer appended `: X` only from
  return_type, which is empty for a property, and consulted the raw signature
  only for enum values. So the one fact the user wanted was the one fact that
  was dropped, for every property and every field.

  WHY A BARE-TYPE TEST RATHER THAN A LIST OF KINDS: the same shape holds for
  fields (`signature` = the type) and would hold for any future kind that
  declares a type without a parameter list. A kind whitelist would have to be
  edited every time the extractor learns a new one, and the failure mode of
  forgetting is silent -- exactly this bug again. A routine's signature always
  carries a parameter list in parentheses, so "no parens and no params" is a
  structural test that cannot mistake one for the other. }

interface

uses
  System.SysUtils;

type
  /// <summary>One parsed parameter: the leading const/var/out modifier (if
  /// any), the name, and the type text. Mirrors the hover model's parameter
  /// shape without depending on the VCL unit that declares it.</summary>
  TDLSigParam = record
    Modifier: string;
    Name    : string;
    TypeText: string;
  end;

  TDLSigParams = TArray<TDLSigParam>;

/// <summary>Builds the popup header's one-line signature.</summary>
/// <param name="AKind">Friendly kind from the CLI ('function', 'property',
/// 'field', 'enum value', ...). Leads the line so the header reads
/// "function Unit.Foo(...)"; omitted when empty.</param>
/// <param name="AQualifiedName">Fully qualified symbol name.</param>
/// <param name="AParams">Parsed parameters; empty for non-routines.</param>
/// <param name="AReturnType">Return type; empty for procedures and for every
/// kind that is not a routine.</param>
/// <param name="ARawSignature">The CLI's `signature` field verbatim. For a
/// routine this is the parenthesised parameter list; for a property or field it
/// is the DECLARED TYPE; for an enum value it is the ordinal.</param>
/// <returns>The composed line. Never raises.</returns>
/// <remarks>Pure: no I/O, no globals, no VCL. Deliberately testable from a
/// console harness -- see the unit header.</remarks>
function ComposeHoverSignature(const AKind, AQualifiedName: string;
  const AParams: TDLSigParams; const AReturnType, ARawSignature: string): string;

implementation

function ComposeHoverSignature(const AKind, AQualifiedName: string;
  const AParams: TDLSigParams; const AReturnType, ARawSignature: string): string;
var
  SB: TStringBuilder;
  i : Integer       ;
  P : TDLSigParam   ;
begin
  SB:= TStringBuilder.Create;
  try
    { Lead with the friendly kind qualifier so the header reads e.g.
      "function Unit.Foo(...)". EmitSignatureHeader colors the keyword. }
    if AKind <> '' then SB.Append(AKind).Append(' ');
    SB.Append(AQualifiedName);

    if Length(AParams) > 0 then
    begin
      SB.Append('(');
      for i:= 0 to High(AParams) do
      begin
        P:= AParams[i];
        if i > 0 then SB.Append('; ');
        if P.Modifier <> '' then SB.Append(P.Modifier).Append(' ');
        SB.Append(P.Name);
        if P.TypeText <> '' then SB.Append(': ').Append(P.TypeText);
      end;
      SB.Append(')');
    end;

    if AReturnType <> '' then
      SB.Append(': ').Append(AReturnType)
    { Show the ordinal like the IDE ("... ptObject = 128"). The CLI puts the
      value in the raw signature for enum-value symbols. Checked BEFORE the
      bare-type branch below, because an ordinal is also parenthesis-free. }
    else if (AKind = 'enum value') and (ARawSignature <> '') then
      SB.Append(' = ').Append(ARawSignature)
    { A property or field declares a TYPE and no parameter list, and the CLI
      reports that type in `signature` with return_type empty. Without this the
      popup showed the name and nothing else -- the reported defect. The
      parenthesis test keeps a routine's parameter list from being pasted here
      as if it were a type. }
    else if (Length(AParams) = 0) and (ARawSignature <> '')
        and (Pos('(', ARawSignature) = 0) then
      SB.Append(': ').Append(Trim(ARawSignature));

    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end; // function

end.
