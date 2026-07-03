unit sample;

interface

type
  TFormatter = class
  public
    function Bold(const S: string): string;
    function Italic(const S: string): string;
    function Indent(const S: string): string;
    function Wrap(const S: string): string;
  end;

  TReport = class
  private
    FFmt: TFormatter;
  public
    function Header(const S: string): string;
    function Footer(const S: string): string;
    function Summarize(const S: string): string;
    procedure Print;
    procedure Balanced;
  end;

implementation

function TFormatter.Bold(const S: string): string;
begin
  Result := '<b>' + S + '</b>';
end;

function TFormatter.Italic(const S: string): string;
begin
  Result := '<i>' + S + '</i>';
end;

function TFormatter.Indent(const S: string): string;
begin
  Result := '  ' + S;
end;

function TFormatter.Wrap(const S: string): string;
begin
  Result := '[' + S + ']';
end;

function TReport.Header(const S: string): string;
begin
  Result := 'HEADER' + S;
end;

function TReport.Footer(const S: string): string;
begin
  Result := 'FOOTER' + S;
end;

function TReport.Summarize(const S: string): string;
begin
  Result := 'SUMMARY' + S;
end;

procedure TReport.Print;
var
  Line: string;
begin
  Line := Header(Line);
  Line := FFmt.Bold(Line);
  Line := FFmt.Italic(Line);
  Line := FFmt.Indent(Line);
  Line := FFmt.Wrap(Line);
end;

procedure TReport.Balanced;
var
  Line: string;
begin
  Line := Header(Line);
  Line := Footer(Line);
  Line := Summarize(Line);
  Line := FFmt.Bold(Line);
end;

end.
