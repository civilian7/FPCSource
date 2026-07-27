unit LazyUnit;

{ 일부러 "게으른" 패키지 유닛 - initialization 에서 클래스를 등록만 하고
  finalization 에서 해제하지 않는다. RTL UnloadPackage 의 모듈 언로드 훅
  (Classes 의 UnRegisterModuleClasses) 이 잔존 등록을 치우는지 검증용. }

{$mode delphi}

interface

uses
  Classes;

type
  TLazyPlugin = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

implementation

function TLazyPlugin.Describe: string;
begin
  Result := 'lazy';
end;

initialization
  RegisterClass(TLazyPlugin);

{ finalization 없음 - UnRegisterClass 를 일부러 생략 }

end.
