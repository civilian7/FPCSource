program host13;

{ 의존 패키지가 함께 언로드될 때 ClassList 에 남는 dangling 등록 회귀.

  RegPkg 는 BasePkg 를 requires 하고, TRegDemo = class(TBaseThing) 이다.
  RegisterClass 는 조상 체인을 전부 등록하므로 RegPkg 의 Register 하나가
  BasePkg 소속인 TBaseThing 까지 ClassList 에 넣는다.

  호스트는 rtlpkg 만 링크한다(-FPrtlpkg). BasePkg 는 오직 RegPkg 의 PE
  import 로만 매핑되므로, FreeLibrary(RegPkg) 가 참조수를 0 으로 만들면서
  *자기 몫의 모듈 언로드 통지 없이* 언매핑된다.

  통지 시점에는 BasePkg 가 아직 매핑·커밋 상태라 소유권 검사도 staleness
  검사도 걸리지 않는다. 그래서 수정 전에는 TBaseThing 항목이 언매핑된
  이미지를 가리킨 채 남고, 다음 GetClass 순회가 그 VMT 를 읽는 순간
  액세스 위반이 난다.

  RegPkg 는 Register 를 가진 contained 유닛이 둘(RegUnit, RegUnit2)이고
  BaseRegUnit 은 required 패키지 소속이라 빠져야 한다. 그래서 TableCount
  자체도 기계 검사한다 - 값만 찍으면 엔트리가 하나뿐인 워크나 BaseRegUnit
  이 잘못 실린 워크가 조용히 통과한다. TBaseThing 기대는 조상 체인 등록
  으로도 채워지므로 그것만으로는 후자를 잡지 못한다. TRegDemo2 를 따로
  본다 - 두 번째 엔트리가 실제로 불렸는지는 그 클래스로만 드러난다.

  기대(수정 후):
    REGPROCS 엔트리       = 2
    로드 후   BasePkg 매핑 = TRUE
    등록 후   TRegDemo2    = TRUE
    등록 후   TBaseThing   = TRUE
    언로드 후 BasePkg 매핑 = FALSE  (의존으로 함께 언매핑)
    언로드 후 TBaseThing   = FALSE  (2차 통지의 staleness 청소가 걷어냄)
    언로드 후 TPersistent  = TRUE   (살아 있는 이미지는 과잉 제거 없음)
    exit 0

  수정 전에는 "GetClass 호출 직전" 까지만 찍히고 액세스 위반으로 죽는다.

  전부 Halt(1) 로 기계 검사한다 - 값만 찍으면 과잉 제거가 조용히
  통과해버린다. 다만 여기 TPersistent 는 rtlpkg 소속이고 rtlpkg 는
  로드타임 바인딩이라 "전부 날리지는 않는다" 까지만 증명한다.
  실제 판별력(살아 있는 의존은 남아야 한다)은 host14 가 본다. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes;

type
  TRegisterProc = procedure;

  TRegProcRec = record
    Proc: TRegisterProc;
    UnitName: ^ShortString;
  end;

  PRegProcTable = ^TRegProcTable;
  TRegProcTable = record
    TableCount: PtrUInt;
    Procs: array[1..1024] of TRegProcRec;
  end;

{ 설계시 등록 테이블을 걸어 contained 유닛의 Register 를 전부 부른다.
  IDE 가 하는 일을 최소한으로 흉내낸 것이다. 호출한 엔트리 수를 돌려주어
  호출부가 테이블 크기까지 검사할 수 있게 한다. }
function CallRegisterProcs(AModule: HMODULE): PtrUInt;
var
  LTable: PRegProcTable;
  I: PtrUInt;
begin
  LTable := PRegProcTable(GetProcAddress(AModule, 'REGPROCS'));
  if LTable = nil then
  begin
    WriteLn('REGPROCS 없음 - 설계시 패키지가 아니다');
    Halt(1);
  end;

  WriteLn('REGPROCS TableCount: ', LTable^.TableCount);
  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].Proc) then
    begin
      LTable^.Procs[I].Proc();
    end;
  end;

  Result := LTable^.TableCount;
end;

function IsMapped(const AName: string): Boolean;
begin
  Result := GetModuleHandle(PChar(AName)) <> 0;
end;

var
  GFailed: Boolean = False;

{ 기대와 다르면 기록해 두고 마지막에 Halt(1). }
procedure Expect(const AWhat: string; AActual, AExpected: Boolean);
const
  NAMES: array[Boolean] of string = ('FALSE', 'TRUE');
begin
  if AActual = AExpected then
  begin
    WriteLn('  [OK]   ', AWhat, ' = ', NAMES[AActual]);
  end
  else
  begin
    WriteLn('  [FAIL] ', AWhat, ' = ', NAMES[AActual], ' (기대 ', NAMES[AExpected], ')');
    GFailed := True;
  end;
end;

var
  GLib: HMODULE;
  GCount: PtrUInt;
begin
  Expect('로드 전 BasePkg 매핑', IsMapped('BasePkg.fpl'), False);

  { LoadPackage 는 실패하면 EPackageError 를 던진다. 돌아왔다는 사실
    자체가 성공이므로 핸들을 0 과 비교해봐야 항상 참이다 - 대신
    의존 패키지가 함께 매핑됐는지를 본다. }
  GLib := LoadPackage('RegPkg.fpl');
  Expect('로드 후 BasePkg 매핑 (의존으로 매핑)', IsMapped('BasePkg.fpl'), True);

  GCount := CallRegisterProcs(GLib);
  { RegUnit + RegUnit2 만. BaseRegUnit 은 required 패키지(BasePkg) 소속이라
    RegPkg 의 테이블에 실리면 안 된다 - 3 이면 스킵 규칙이 깨진 것이고
    1 이면 다중 엔트리 워크가 깨진 것이다. }
  Expect('REGPROCS 엔트리 2개 (RegUnit, RegUnit2)', GCount = 2, True);

  Expect('등록 후 TRegDemo', Assigned(GetClass('TRegDemo')), True);
  { 두 번째 엔트리가 실제로 불렸는가 - TRegDemo2 는 RegUnit2.Register 로만
    등록되고 어떤 조상 체인으로도 딸려오지 않는다. }
  Expect('등록 후 TRegDemo2 (두 번째 엔트리)', Assigned(GetClass('TRegDemo2')), True);
  Expect('등록 후 TBaseThing (조상 체인 등록)', Assigned(GetClass('TBaseThing')), True);

  UnloadPackage(GLib);
  Expect('언로드 후 BasePkg 매핑 (통지 없이 언매핑)', IsMapped('BasePkg.fpl'), False);

  { 여기서부터가 문제 구간이다. 수정 전이라면 아래 GetClass 가
    언매핑된 이미지의 VMT 를 읽고 죽는다. }
  WriteLn('GetClass 호출 직전');
  Expect('언로드 후 TBaseThing', Assigned(GetClass('TBaseThing')), False);
  Expect('언로드 후 TRegDemo', Assigned(GetClass('TRegDemo')), False);
  Expect('언로드 후 TPersistent (과잉 제거 없음)', Assigned(GetClass('TPersistent')), True);

  if GFailed then
  begin
    WriteLn('host13 FAILED');
    Halt(1);
  end;

  WriteLn('host13 ok');
end.
