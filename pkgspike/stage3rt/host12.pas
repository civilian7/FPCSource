program host12;

{ RTL 이관 검증 - 40줄 사용자 코드 대신 SysUtils 의
  LoadPackage / UnloadPackage 를 그대로 쓴다.

  LazyPkg 는 finalization 에서 UnRegisterClass 를 일부러 생략한
  "게으른" 패키지다. UnloadPackage 의 모듈 언로드 훅(Classes 가
  등록한 UnRegisterModuleClasses)이 떠나는 이미지 소속 잔존 등록을
  치워야 언로드 후 GetClass 순회가 안전하다.

  기대:
    언로드 전  GetClass(TLazyPlugin) = TRUE
    언로드 후  GetClass(TLazyPlugin) = FALSE  (훅이 치웠다)
    언로드 후  GetClass(TPersistent) = TRUE   (남의 이미지는 안 건드림)
    exit 0 (종료 경로 포함 깨끗)

  기대값은 전부 Require 로 기계 검사한다. 값만 찍으면 과잉 제거
  (TPersistent 가 FALSE 가 되는 회귀)가 exit 0 으로 조용히 통과한다 -
  이 가드가 존재하는 이유가 바로 그것이다. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes;

var
  GFailed: Boolean = False;

{ 통과하면 아무것도 찍지 않는다 - 위 출력 형식을 그대로 보존하기 위해서다.
  어긋날 때만 말하고 마지막에 Halt(1) 한다. }
procedure Require(const AWhat: string; AActual, AExpected: Boolean);
const
  NAMES: array[Boolean] of string = ('FALSE', 'TRUE');
begin
  if AActual <> AExpected then
  begin
    WriteLn('  [FAIL] ', AWhat, ' = ', NAMES[AActual], ' (기대 ', NAMES[AExpected], ')');
    GFailed := True;
  end;
end;

{ 임시 AnsiString(패키지 리터럴)이 언로드 전에 해제되도록 격리 - 언로드 계약 }
procedure RunPlugin;
var
  LCls: TPersistentClass;
  LObj: TPersistent;
begin
  LCls := GetClass('TLazyPlugin');
  WriteLn('로드 후 GetClass  : ', Assigned(LCls));
  Require('로드 후 TLazyPlugin', Assigned(LCls), True);
  if not Assigned(LCls) then
  begin
    Exit;
  end;

  LObj := LCls.Create;
  try
    WriteLn('ClassName         : ', LObj.ClassName);
    WriteLn('Parent            : ', LObj.ClassParent.ClassName);
  finally
    LObj.Free;
  end;
end;

var
  GLib: HMODULE;
  GLazy: Boolean;
  GPersist: Boolean;
begin
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('로드 전 GetClass  : ', GLazy);
  Require('로드 전 TLazyPlugin', GLazy, False);

  GLib := LoadPackage('LazyPkg.dll');
  WriteLn('LoadPackage       : ', GLib <> 0);

  RunPlugin;

  UnloadPackage(GLib);
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('언로드 후 Lazy    : ', GLazy, ' (기대 FALSE - 훅이 치움)');
  Require('언로드 후 TLazyPlugin', GLazy, False);

  GPersist := Assigned(GetClass('TPersistent'));
  WriteLn('언로드 후 Persist : ', GPersist, ' (기대 TRUE - 과잉 제거 없음)');
  Require('언로드 후 TPersistent (과잉 제거)', GPersist, True);

  { 두 번째 사이클 - 재로드가 멀쩡한지 }
  GLib := LoadPackage('LazyPkg.dll');
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('재로드 GetClass   : ', GLazy);
  Require('재로드 TLazyPlugin', GLazy, True);

  UnloadPackage(GLib);
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('재언로드 Lazy     : ', GLazy);
  Require('재언로드 TLazyPlugin', GLazy, False);

  if GFailed then
  begin
    WriteLn('host12 FAILED');
    Halt(1);
  end;

  WriteLn('host12 ok');
end.
