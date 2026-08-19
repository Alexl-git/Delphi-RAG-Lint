program HoverSignatureHarness;

{ Console harness for DragLint.Plugin.HoverSignature (pure, no ToolsAPI/VCL),
  in the shape of CallerFilterHarness.

  It runs each case through BOTH composers:

    NEW = ComposeHoverSignature  -- the unit under test
    OLD = OldCompose below       -- a faithful reproduction of the code that
                                    shipped before 2026-08-19: append ": X" only
                                    from return_type, and consult the raw
                                    signature only for enum values

  Both are printed so the .ps1 can assert the guard DISCRIMINATES. Asserting
  only NEW would pass just as happily against a composer that pastes the raw
  signature onto everything -- which would put a routine's parameter list where
  its return type belongs. The FUNCTION and ENUMVAL cases exist to catch that. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DragLint.Plugin.HoverSignature in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.HoverSignature.pas';

function P(const AMod, AName, AType: string): TDLSigParam;
begin
  Result.Modifier:= AMod ;
  Result.Name    := AName;
  Result.TypeText:= AType;
end;

{ The composer that shipped before 2026-08-19, reproduced exactly. }
function OldCompose(const AKind, AQualifiedName: string; const AParams: TDLSigParams;
  const AReturnType, ARawSignature: string): string;
var
  SB: TStringBuilder;
  i : Integer       ;
  Pm: TDLSigParam   ;
begin
  SB:= TStringBuilder.Create;
  try
    if AKind <> '' then SB.Append(AKind).Append(' ');
    SB.Append(AQualifiedName);
    if Length(AParams) > 0 then
    begin
      SB.Append('(');
      for i:= 0 to High(AParams) do
      begin
        Pm:= AParams[i];
        if i > 0 then SB.Append('; ');
        if Pm.Modifier <> '' then SB.Append(Pm.Modifier).Append(' ');
        SB.Append(Pm.Name);
        if Pm.TypeText <> '' then SB.Append(': ').Append(Pm.TypeText);
      end;
      SB.Append(')');
    end;
    if AReturnType <> '' then SB.Append(': ').Append(AReturnType);
    if (AKind = 'enum value') and (ARawSignature <> '') then SB.Append(' = ').Append(ARawSignature);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure Emit(const AId, AKind, AQName: string; const AParams: TDLSigParams;
  const ARet, ARaw: string);
begin
  Writeln(AId, '.NEW=', ComposeHoverSignature(AKind, AQName, AParams, ARet, ARaw));
  Writeln(AId, '.OLD=', OldCompose          (AKind, AQName, AParams, ARet, ARaw));
end;

var
  NoParams: TDLSigParams;
  OneParam: TDLSigParams;
begin
  SetLength(NoParams, 0);
  SetLength(OneParam, 1);
  OneParam[0]:= P('const', 'S', 'string');

  { PROPERTY -- the reported defect. Real payload, measured from
    `hover --qname Vcl.ExtCtrls.TTimer.Enabled --format json`:
      kind=property signature=Boolean return_type='' params=[] }
  Emit('PROP', 'property', 'Vcl.ExtCtrls.TTimer.Enabled', NoParams, '', 'Boolean');

  { PROPERTY of a non-trivial type -- the type must survive verbatim. }
  Emit('PROPEV', 'property', 'Vcl.ExtCtrls.TTimer.OnTimer', NoParams, '', 'TNotifyEvent');

  { FIELD -- same shape, same fix.
      kind=field signature=TComponentName return_type='' }
  Emit('FIELD', 'field', 'System.Classes.TComponent.FName', NoParams, '', 'TComponentName');

  { FUNCTION -- THE CONTROL. Its raw signature is a PARAMETER LIST; pasting it
    after a colon would render "function Trim(const S: string): (const S: string)".
      kind=function signature=(const S: string): string return_type=string }
  Emit('FUNC', 'function', 'System.SysUtils.Trim', OneParam, 'string', '(const S: string): string');

  { ENUM VALUE -- THE OTHER CONTROL. Parenthesis-free like a property type, so
    a bare-type rule that did not check this first would print ": 0" instead of
    " = 0".
      kind=enum value signature=0 return_type='' }
  Emit('ENUMVAL', 'enum value', 'System.Classes.TAlignment.taLeftJustify', NoParams, '', '0');

  { METHOD with nothing to add -- must be unchanged by the fix. }
  Emit('BARE', 'method', 'System.Classes.TComponent.Create', NoParams, '', '');

  Writeln('DONE');
end.
