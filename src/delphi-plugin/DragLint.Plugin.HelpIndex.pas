unit DragLint.Plugin.HelpIndex;

{ The pure half of the IDE help line (spec docs\superpowers\specs\
  2026-10-23-ide-help-line-design.md, sections 3.1-3.3): help-root URL rules,
  the offline feature list (WWW\help\dl\index.json) and the matcher.
  No VCL, no ToolsAPI -- tests\autotest\run_plugin_help_line.ps1 builds it
  headless. }

interface

const
  /// <summary>The help root used when the setting is empty or missing: the
  /// public website.</summary>
  DL_DEFAULT_HELP_ROOT = 'https://www.delphi-rag-lint.com';

/// <summary>Normalises a help root as typed by the user into the stored form.</summary>
/// <param name="pRoot">An http(s) URL, a file:/// URL or a plain Windows folder;
/// may carry trailing slashes or surrounding blanks.</param>
/// <returns>DL_DEFAULT_HELP_ROOT for an empty value; a folder becomes
/// file:///C:/dir (forward slashes); trailing slashes are removed.</returns>
function DLNormaliseHelpRoot(const pRoot: string): string;

/// <summary>Builds the help page URL of one registry feature.</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <param name="pFeatureId">Registry id (features\entries\&lt;id&gt;.json); empty
/// gives the all-features URL.</param>
/// <returns>&lt;root&gt;/help/dl/features/&lt;id&gt;/ for a web root;
/// the same plus index.html for a file: root (the rendered site tree).</returns>
function DLHelpUrl(const pRoot, pFeatureId: string): string;

/// <summary>URL of the complete feature list: &lt;root&gt;/help/dl/ (plus
/// index.html for a file: root).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The all-features URL.</returns>
function DLHelpAllUrl(const pRoot: string): string;

/// <summary>URL of the IDE menu tree page: &lt;root&gt;/help/dl/ide/ (plus
/// index.html for a file: root).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The menu-tree URL.</returns>
function DLHelpIdeUrl(const pRoot: string): string;

/// <summary>True when the (normalised) root is a file: root -- an offline copy.</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>True for file:/// roots and plain folders.</returns>
function DLIsFileHelpRoot(const pRoot: string): Boolean;

/// <summary>The local folder behind a file: root (file:///C:/dl-help -> C:\dl-help).</summary>
/// <param name="pRoot">Help root in any form DLNormaliseHelpRoot accepts.</param>
/// <returns>The Windows folder without a trailing backslash; '' for a web root.</returns>
function DLHelpRootFolder(const pRoot: string): string;

implementation

uses
  System.SysUtils
  ;

const
  FILE_SCHEME = 'file:///';
  HELP_DL     = '/help/dl/';
  INDEX_HTML  = 'index.html';

function StripTrailingSlashes(const pValue: string): string;
begin
  Result:= pValue;
  while (Result <> '') and CharInSet(Result[Length(Result)], ['/', '\']) do
    SetLength(Result, Length(Result) - 1);
end; // function

function DLNormaliseHelpRoot(const pRoot: string): string;
begin
  Result:= Trim(pRoot);
  if Result = '' then Exit(DL_DEFAULT_HELP_ROOT);
  if Result.StartsWith('http://', True) or Result.StartsWith('https://', True) then
    Exit(StripTrailingSlashes(Result));
  { A file: URL as typed, or a plain folder (C:\dir, \\server\share): one
    canonical file:/// form with forward slashes. }
  if Result.StartsWith('file:', True) then
  begin
    Result:= Result.Substring(Length('file:'));
    while Result.StartsWith('/') or Result.StartsWith('\') do Result:= Result.Substring(1);
  end; // if
  Result:= StripTrailingSlashes(Result.Replace('\', '/'));
  Result:= FILE_SCHEME + Result;
end; // function

function DLIsFileHelpRoot(const pRoot: string): Boolean;
begin
  Result:= DLNormaliseHelpRoot(pRoot).StartsWith(FILE_SCHEME, True);
end; // function

function DLHelpRootFolder(const pRoot: string): string;
var
  Root: string;
begin
  Root:= DLNormaliseHelpRoot(pRoot);
  if not Root.StartsWith(FILE_SCHEME, True) then Exit('');
  Result:= Root.Substring(Length(FILE_SCHEME)).Replace('/', '\');
end; // function

{ <root>/help/dl/<pRel>; a file: root names the page file itself, because a
  browser does not resolve a folder URL to its index.html on disk. }
function HelpPageUrl(const pRoot, pRel: string): string;
var
  Root: string;
begin
  Root:= DLNormaliseHelpRoot(pRoot);
  Result:= Root + HELP_DL + pRel;
  if Root.StartsWith(FILE_SCHEME, True) then Result:= Result + INDEX_HTML;
end; // function

function DLHelpUrl(const pRoot, pFeatureId: string): string;
begin
  if Trim(pFeatureId) = '' then Exit(DLHelpAllUrl(pRoot));
  Result:= HelpPageUrl(pRoot, 'features/' + Trim(pFeatureId) + '/');
end; // function

function DLHelpAllUrl(const pRoot: string): string;
begin
  Result:= HelpPageUrl(pRoot, '');
end; // function

function DLHelpIdeUrl(const pRoot: string): string;
begin
  Result:= HelpPageUrl(pRoot, 'ide/');
end; // function

end.
