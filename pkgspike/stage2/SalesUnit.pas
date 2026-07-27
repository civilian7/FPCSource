unit SalesUnit;

{$mode delphi}

interface

uses
  BaseUnit;

type
  { 다른 패키지의 클래스를 상속 - VMT 크로스 모듈 참조 }
  TSales = class(TBase)
  public
    function Describe: string; override;
  end;

implementation

function TSales.Describe: string;
begin
  { inherited 호출 - 부모 코드는 CommonPkg.dll 안에 있다 }
  Result := 'sales(' + inherited Describe + ')';
end;

end.
