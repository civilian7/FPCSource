unit SharedIntf;

{$mode delphi}

interface

uses
  Classes;

type
  { 호스트와 플러그인이 공유하는 베이스. rtlpkg 의 TPersistent 를 상속한다. }
  TPluginBase = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

implementation

function TPluginBase.Describe: string;
begin
  Result := 'base';
end;

end.
