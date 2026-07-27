program host5;

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes,
  SharedIntf;

{ ── 델파이 LoadPackage 의 최소 구현 ───────────────────────────
  패키지 DLL 은 자기 초기화 테이블을 'INITFINAL' 로 내보낸다.
  그것을 걸어 contained 유닛의 initialization 을 실행한다. }
type
  TProcedure = procedure;

  TInitFinalRec = record
    InitProc: TProcedure;
    FinalProc: TProcedure;
    UnitName: ^ShortString;
  end;

  PInitFinalTable = ^TInitFinalTable;
  TInitFinalTable = record
    TableCount: PtrUInt;
    InitCount: PtrUInt;
    Procs: array[1..1024] of TInitFinalRec;
  end;

function LoadPackage(const AName: string): HMODULE;
var
  LTable: PInitFinalTable;
  I: PtrUInt;
begin
  Result := LoadLibrary(PChar(AName));
  if Result = 0 then
    Exit;

  LTable := PInitFinalTable(GetProcAddress(Result, 'INITFINAL'));
  if LTable = nil then
  begin
    WriteLn('  경고: INITFINAL 익스포트 없음');
    Exit;
  end;

  WriteLn('  유닛 ', LTable^.TableCount, '개 초기화');
  for I := 1 to LTable^.TableCount do
  begin
    if Assigned(LTable^.Procs[I].UnitName) then
      WriteLn('    - ', LTable^.Procs[I].UnitName^);
    if Assigned(LTable^.Procs[I].InitProc) then
      LTable^.Procs[I].InitProc();
    LTable^.InitCount := I;
  end;
end;

procedure UnloadPackage(AHandle: HMODULE);
var
  LTable: PInitFinalTable;
begin
  LTable := PInitFinalTable(GetProcAddress(AHandle, 'INITFINAL'));
  if LTable <> nil then
    while LTable^.InitCount > 0 do
    begin
      Dec(LTable^.InitCount);
      if Assigned(LTable^.Procs[LTable^.InitCount + 1].FinalProc) then
        LTable^.Procs[LTable^.InitCount + 1].FinalProc();
    end;

  { FreeLibrary 생략 - 종료 경로 격리용 }
end;

var
  GLib: HMODULE;
  GCls: TPersistentClass;
  GObj: TPluginBase;
begin
  WriteLn('로드 전 GetClass : ', Assigned(GetClass('TSalesPlugin')));

  GLib := LoadPackage('SalesPkg.dll');
  WriteLn('LoadPackage      : ', GLib <> 0);
  if GLib = 0 then
  begin
    WriteLn('  GetLastError = ', GetLastError);
    Halt(1);
  end;

  GCls := GetClass('TSalesPlugin');
  WriteLn('로드 후 GetClass : ', Assigned(GCls));
  if not Assigned(GCls) then
  begin
    UnloadPackage(GLib);
    Halt(2);
  end;

  GObj := TPluginBase(GCls.Create);
  try
    WriteLn('Describe         : ', GObj.Describe);
    WriteLn('ClassName        : ', GObj.ClassName);
    WriteLn('is TPluginBase   : ', GObj is TPluginBase);
    WriteLn('Parent           : ', GObj.ClassParent.ClassName);
  finally
    GObj.Free;
  end;

  UnloadPackage(GLib);
  WriteLn('언로드 후 GetClass: ', Assigned(GetClass('TSalesPlugin')));
  WriteLn('host4 ok');
end.
