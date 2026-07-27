program host14;

{ 2라운드 통지의 *판별력* 회귀 - 기계 검사판.

  host13 은 "의존으로 언매핑된 이미지의 항목이 치워진다" 를 본다.
  여기서 보는 것은 그 반대쪽, 즉 **과잉 제거가 없다**는 쪽이다.

  host12/host13 의 TPersistent 검사는 이 판별을 시험하지 못한다.
  TPersistent 는 rtlpkg 에 있고 rtlpkg 는 -FPrtlpkg 로 로드타임
  바인딩되어 참조수가 0 이 될 수 없다 - "전부 날리지는 않는다" 만
  증명할 뿐이다. 2라운드가 실제로 의존하는 판별은 이것이다:

    동적으로 로드됐고 *다른 로드된 패키지가 아직 참조 중인* required
    패키지는 매핑된 채 남아야 하고, 그 패키지 소속 등록도 살아남아야 한다.

  구성: RegPkg 와 Reg2Pkg 가 **둘 다** BasePkg 를 requires 한다.
  호스트는 rtlpkg 만 링크하므로 BasePkg 는 오직 이 두 패키지의 import
  로만 매핑된다(참조수 2).

    RegPkg 언로드  -> BasePkg 참조수 1, 매핑 유지
                      => TBaseThing 은 **살아남아야** 한다  (핵심 가드)
    Reg2Pkg 언로드 -> BasePkg 참조수 0, 언매핑
                      => TBaseThing 은 사라져야 한다

  전부 Halt(1) 로 기계 검사한다. 값만 찍고 통과하지 않는다. }

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

var
  GFailed: Boolean = False;

{ 기대와 다르면 그 자리에서 기록한다. 마지막에 Halt(1). }
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

procedure CallRegisterProcs(AModule: HMODULE);
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

  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].Proc) then
    begin
      LTable^.Procs[I].Proc();
    end;
  end;
end;

function IsMapped(const AName: string): Boolean;
begin
  Result := GetModuleHandle(PChar(AName)) <> 0;
end;

var
  GReg: HMODULE;
  GReg2: HMODULE;
begin
  GReg := LoadPackage('RegPkg.fpl');
  GReg2 := LoadPackage('Reg2Pkg.fpl');
  CallRegisterProcs(GReg);
  CallRegisterProcs(GReg2);

  WriteLn('== 둘 다 로드, 등록 후 ==');
  Expect('BasePkg 매핑', IsMapped('BasePkg.fpl'), True);
  Expect('TBaseThing', Assigned(GetClass('TBaseThing')), True);
  Expect('TRegDemo', Assigned(GetClass('TRegDemo')), True);
  Expect('TReg2Demo', Assigned(GetClass('TReg2Demo')), True);

  { RegPkg 만 언로드한다. Reg2Pkg 가 아직 BasePkg 를 붙들고 있으므로
    BasePkg 는 언매핑되지 않는다. 2라운드가 staleness 만으로 판정하는
    것이 옳다면 TBaseThing 은 반드시 살아남는다. }
  UnloadPackage(GReg);
  WriteLn('== RegPkg 만 언로드 (Reg2Pkg 가 BasePkg 를 아직 참조) ==');
  Expect('BasePkg 매핑', IsMapped('BasePkg.fpl'), True);
  Expect('TRegDemo (RegPkg 소유, 치워져야)', Assigned(GetClass('TRegDemo')), False);
  Expect('TBaseThing (살아남아야 - 핵심 가드)', Assigned(GetClass('TBaseThing')), True);
  Expect('TReg2Demo (Reg2Pkg 살아있음)', Assigned(GetClass('TReg2Demo')), True);

  { 마지막 참조자를 놓으면 BasePkg 가 의존으로 언매핑된다. 이제는
    치워져야 한다 - 안 치우면 다음 GetClass 가 죽는다. }
  UnloadPackage(GReg2);
  WriteLn('== Reg2Pkg 도 언로드 (BasePkg 참조수 0) ==');
  Expect('BasePkg 매핑', IsMapped('BasePkg.fpl'), False);
  Expect('TReg2Demo (Reg2Pkg 소유, 치워져야)', Assigned(GetClass('TReg2Demo')), False);
  Expect('TBaseThing (의존 언매핑, 치워져야)', Assigned(GetClass('TBaseThing')), False);
  Expect('TPersistent (rtlpkg 는 핀 고정)', Assigned(GetClass('TPersistent')), True);

  if GFailed then
  begin
    WriteLn('host14 FAILED');
    Halt(1);
  end;

  WriteLn('host14 ok');
end.
