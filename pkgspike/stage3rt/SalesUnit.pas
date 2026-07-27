unit SalesUnit;

{$mode delphi}

interface

uses
  Classes,
  SharedIntf;

type
  TSalesPlugin = class(TPluginBase)
  public
    function Describe: string; override;
  end;

implementation

function TSalesPlugin.Describe: string;
begin
  Result := 'sales-plugin';
end;

initialization
  { 전역 클래스 레지스트리에 등록 - 레지스트리는 rtlpkg 의 classes 안에 있다 }
  RegisterClass(TSalesPlugin);

finalization
  { 언로드 시 반드시 해제해야 한다. 레지스트리는 rtlpkg 에 살아남고
    TSalesPlugin 의 VMT 는 이 DLL 과 함께 사라지므로, 남겨두면
    다음 GetClass 가 죽은 메모리를 읽는다. 델파이 BPL 과 동일한 규칙. }
  UnRegisterClass(TSalesPlugin);

end.
