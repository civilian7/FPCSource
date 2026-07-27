unit PlainUnit;

{$mode delphi}

interface

uses
  Classes;

type
  { 조상이 전부 rtlpkg 안에 있다 (TPersistent) - 언로드되는 DLL 밖 }
  TPlainPlugin = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

var
  GFlag: Integer = 3;
  GStr: string;

implementation

function TPlainPlugin.Describe: string;
begin
  Result := 'plain';
end;

initialization
  GStr := 'loaded';
  GFlag := 7;
  RegisterClass(TPlainPlugin);

finalization
  UnRegisterClass(TPlainPlugin);
  GStr := '';
  GFlag := 0;

end.
