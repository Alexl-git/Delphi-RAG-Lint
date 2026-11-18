unit ToolsAPI;
interface
type
  IOTAProject = interface
    ['{11111111-0000-0000-0000-000000000001}']
    function GetFileName: string;
    property FileName: string read GetFileName;
  end;
  IOTAProjectGroup = interface
    ['{11111111-0000-0000-0000-000000000002}']
    function GetActiveProject: IOTAProject;
    property ActiveProject: IOTAProject read GetActiveProject;
  end;
  IOTAModuleServices = interface
    ['{11111111-0000-0000-0000-000000000003}']
    function GetMainProjectGroup: IOTAProjectGroup;
    property MainProjectGroup: IOTAProjectGroup read GetMainProjectGroup;
  end;
var
  BorlandIDEServices: IInterface;
implementation
end.
