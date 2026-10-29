unit DRagLint.Fix.Shape;

{ Lane G2 -- shape fixers of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md): interface-without-guid
  and constructor-call-on-instance. collection-modified-in-loop is a pure
  sidecar template (rules\collection-modified-in-loop.json) and needs no code.
  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Hash
  , System.Math
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  ;

const
  GUID_GROUP_SIZES: array[0..4] of Integer = (4, 2, 2, 2, 6);
  GUID_VERSION_BYTE = 6;
  GUID_VARIANT_BYTE = 8;
  GUID_VERSION_KEEP = $0F;
  GUID_VERSION_SET  = $30;
  GUID_VARIANT_KEEP = $3F;
  GUID_VARIANT_SET  = $80;
  INTF_INDENT       = '  ';

{ A name-based GUID: MD5 of '<unit>.<interface>' (lower case), version 3 / RFC 4122 variant bits
  set. Deterministic on purpose -- the same declaration always gets the same IID, so the fix is
  reproducible and testable; CreateGUID would differ on every run. The text is the Delphi
  braced 8-4-4-4-12 hex form built from the digest bytes in order. }
function NameBasedGuid(const AUnitName, AInterfaceName: string): string;
var
  Digest: TBytes;
  G, I, P: Integer;
  SB: TStringBuilder;
begin
  Digest:= THashMD5.GetHashBytes(LowerCase(AUnitName + '.' + AInterfaceName));
  Digest[GUID_VERSION_BYTE]:= (Digest[GUID_VERSION_BYTE] and GUID_VERSION_KEEP) or GUID_VERSION_SET;
  Digest[GUID_VARIANT_BYTE]:= (Digest[GUID_VARIANT_BYTE] and GUID_VARIANT_KEEP) or GUID_VARIANT_SET;
  SB:= TStringBuilder.Create;
  try
    SB.Append('{');
    P:= 0;
    for G:= Low(GUID_GROUP_SIZES) to High(GUID_GROUP_SIZES) do
    begin
      if G > 0 then SB.Append('-');
      for I:= 1 to GUID_GROUP_SIZES[G] do
      begin
        SB.Append(IntToHex(Digest[P], 2));
        Inc(P);
      end;
    end;
    SB.Append('}');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ interface-without-guid: inserts a bracketed GUID literal on its own line right after the line that holds the
  `interface` keyword (and its optional parent list). Declines when anything but a comment follows
  the header on that line (a one-line interface, a parent list continued on the next line). }
function FixInterfaceWithoutGuid(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
const
  HEADER_TAIL = '^interface\s*(\([^)]*\))?\s*(//.*|\{[^}]*\})?\s*$';
  DECL_NAME   = '^\s*(?:type\s+)?([A-Za-z_]\w*)\s*=';
var
  Line : string;
  Tail : string;
  Match: TMatch;
  E    : TTextEdit;
  Indent: string;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.StartCol > Length(Line)) then Exit;
  Tail:= Copy(Line, AFinding.StartCol, MaxInt);
  if not TRegEx.IsMatch(Tail, HEADER_TAIL, [roIgnoreCase]) then Exit;
  Match:= TRegEx.Match(Copy(Line, 1, AFinding.StartCol - 1), DECL_NAME, [roIgnoreCase]);
  if not Match.Success then Exit;
  Indent:= Copy(Line, 1, Length(Line) - Length(TrimLeft(Line))) + INTF_INDENT;
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekInsertLines;
  E.Line      := AFinding.StartLine;
  E.Text      := Indent + '[''' + NameBasedGuid(ChangeFileExt(ExtractFileName(AFinding.FilePath), ''),
    Match.Groups[1].Value) + ''']';
  E.ExpectLine:= AFinding.StartLine;
  E.ExpectText:= 'interface';
  Result:= [E];
end;

{ True when AName is declared as a PARAMETER of the routine enclosing ALine: the nearest preceding
  routine header, scanned up to the first line that ends the header (a ';' after the closing ')'). }
function IsParameterOfEnclosingRoutine(ALines: TStringList; ALine: Integer; const AName: string): Boolean;
const
  ROUTINE_START = '^\s*(class\s+)?(procedure|function|constructor|destructor)\b';
var
  I     : Integer;
  J     : Integer;
  Header: string;
begin
  Result:= False;
  for I:= Min(ALine, ALines.Count) - 1 downto 0 do
    if TRegEx.IsMatch(ALines[I], ROUTINE_START, [roIgnoreCase]) then
    begin
      Header:= '';
      J:= I;
      while (J < ALines.Count) and (J < ALine) do
      begin
        Header:= Header + ' ' + ALines[J];
        if ALines[J].Contains(';') then Break;
        Inc(J);
      end;
      Exit(TRegEx.IsMatch(Header, '[(;]\s*(var\s+|const\s+|out\s+)?([A-Za-z_]\w*\s*,\s*)*' + TRegEx.Escape(AName) +
        '\s*[,:]', [roIgnoreCase]));
    end;
end;

{ constructor-call-on-instance: `X.Create(..)` -> `X := <declared type>.Create(..)` for a declared
  LOCAL (the type comes from DeclTypeOf, the scope walk the rule's own predicate uses). Declines for
  parameters (a const/var parameter cannot be reassigned meaningfully), fields and anything whose
  declared type the source does not show, and for a span that crosses lines. }
function FixConstructorCallOnInstance(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line    : string;
  Span    : string;
  Match   : TMatch;
  TypeName: string;
  E       : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.EndCol <= AFinding.StartCol) or (AFinding.EndCol > Length(Line) + 1) then Exit;
  Span := Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  Match:= TRegEx.Match(Span, '^([A-Za-z_]\w*)\.Create\b(.*)$', [roIgnoreCase, roSingleLine]);
  if not Match.Success then Exit;
  if IsParameterOfEnclosingRoutine(ALines, AFinding.StartLine, Match.Groups[1].Value) then Exit;
  TypeName:= DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Match.Groups[1].Value);
  if TypeName = '' then Exit;
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceInLine;
  E.Line      := AFinding.StartLine;
  E.Col       := AFinding.StartCol;
  E.EndCol    := AFinding.EndCol;
  E.ExpectText:= Span;
  E.Text      := Match.Groups[1].Value + ' := ' + TypeName + '.Create' + Match.Groups[2].Value;
  Result:= [E];
end;

initialization
  RegisterFixer('interface-without-guid', FixInterfaceWithoutGuid);
  RegisterFixer('constructor-call-on-instance', FixConstructorCallOnInstance, True);

end.
