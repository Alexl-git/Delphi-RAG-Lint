@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /D "%~dp0"
if not exist ..\dcu_t mkdir ..\dcu_t
dcc32 -U"..\..\..\analysis;..\..\..\charts;..\..\..\cli;..\..\..\config;..\..\..\context;..\..\..\core;..\..\..\delphi-plugin;..\..\..\diagnostics;..\..\..\doc;..\..\..\forms;..\..\..\index;..\..\..\lint;..\..\..\lsp;..\..\..\mcp;..\..\..\output;..\..\..\parser;..\..\..\preprocess;..\..\..\project;..\..\..\query;..\..\..\refactor;..\..\..\report;..\..\..\resolver;..\..\..\sql;..\..\..\storage;..\..\..\workspace" -B -NU..\dcu_t -E. -NSSystem;Winapi;System.Win ProjectCtxTests.dpr
echo BUILD_EXITCODE=%errorlevel%
