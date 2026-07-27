unit Reg2Unit;

{ RegUnit 과 똑같이 BasePkg 의 TBaseThing 에서 파생하지만 다른 패키지
  (Reg2Pkg)에 담긴다. 두 패키지가 같은 required 패키지를 공유하게 만들어
  "다른 로드된 패키지가 아직 참조 중인 의존은 매핑된 채 남는다" 를
  시험하기 위한 것이다. host14 참조. }

{$mode delphi}

interface

uses
  Classes,
  BaseRegUnit;

type
  TReg2Demo = class(TBaseThing)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TReg2Demo);
end;

end.
