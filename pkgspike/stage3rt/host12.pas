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
    exit 0 (종료 경로 포함 깨끗) }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes;

{ 임시 AnsiString(패키지 리터럴)이 언로드 전에 해제되도록 격리 - 언로드 계약 }
procedure RunPlugin;
var
  LCls: TPersistentClass;
  LObj: TPersistent;
begin
  LCls := GetClass('TLazyPlugin');
  WriteLn('로드 후 GetClass  : ', Assigned(LCls));
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
begin
  WriteLn('로드 전 GetClass  : ', Assigned(GetClass('TLazyPlugin')));

  GLib := LoadPackage('LazyPkg.dll');
  WriteLn('LoadPackage       : ', GLib <> 0);

  RunPlugin;

  UnloadPackage(GLib);
  WriteLn('언로드 후 Lazy    : ', Assigned(GetClass('TLazyPlugin')), ' (기대 FALSE - 훅이 치움)');
  WriteLn('언로드 후 Persist : ', Assigned(GetClass('TPersistent')), ' (기대 TRUE - 과잉 제거 없음)');

  { 두 번째 사이클 - 재로드가 멀쩡한지 }
  GLib := LoadPackage('LazyPkg.dll');
  WriteLn('재로드 GetClass   : ', Assigned(GetClass('TLazyPlugin')));
  UnloadPackage(GLib);
  WriteLn('재언로드 Lazy     : ', Assigned(GetClass('TLazyPlugin')));

  WriteLn('host12 ok');
end.
