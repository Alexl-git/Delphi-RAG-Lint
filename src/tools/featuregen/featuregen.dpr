program featuregen;

{ featuregen: owns the drag-lint feature registry (features\) and generates docs
  from it. Task 1 scaffold: verb dispatch only; unknown verb prints usage, exit 2. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , FeatureGen.Json in 'FeatureGen.Json.pas'
  , FeatureGen.Model in 'FeatureGen.Model.pas'
  ;

procedure PrintUsage;
begin
  Writeln('usage: featuregen <verb> [options]');
  Writeln('  (no verbs implemented yet)');
end;

begin
  PrintUsage;
  ExitCode := 2;
end.