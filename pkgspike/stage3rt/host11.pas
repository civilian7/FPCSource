program host11;

{ 검증 2: host4 의 종료 크래시 원인이 "main 의 WriteLn 임시 AnsiString 이
  SalesPkg.dll 데이터 섹션의 상수 문자열('sales-plugin')을 가리킨 채
  main 에필로그까지 살아남아, 언로드 뒤 FPC_ANSISTR_DECR_REF 가 언맵된
  이미지의 refcount 필드를 읽는 것" 이라면 — 플러그인 사용부를 별도
  프로시저로 격리해 임시가 언로드 *전에* 해제되게 하면 깨끗해야 한다.
  host4 와의 차이는 이 격리 하나뿐이다. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes,
  SharedIntf;

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
    Exit;

  for I := 1 to LTable^.TableCount do
  begin
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

  FreeLibrary(AHandle);
end;

{ host4 의 main 본문과 동일 - 단 임시 AnsiString 들이 이 프로시저의
  에필로그에서(= 언로드 전에) 해제된다 }
procedure RunPlugin;
var
  LCls: TPersistentClass;
  LObj: TPluginBase;
begin
  LCls := GetClass('TSalesPlugin');
  WriteLn('GetClass         : ', Assigned(LCls));
  if not Assigned(LCls) then
    Exit;

  LObj := TPluginBase(LCls.Create);
  try
    WriteLn('Describe         : ', LObj.Describe);
    WriteLn('ClassName        : ', LObj.ClassName);
    WriteLn('is TPluginBase   : ', LObj is TPluginBase);
    WriteLn('Parent           : ', LObj.ClassParent.ClassName);
  finally
    LObj.Free;
  end;
end;

var
  GLib: HMODULE;
begin
  GLib := LoadPackage('SalesPkg.fpl');
  WriteLn('LoadPackage      : ', GLib <> 0);
  if GLib = 0 then
  begin
    Halt(1);
  end;

  RunPlugin;

  UnloadPackage(GLib);
  WriteLn('언로드 후 GetClass: ', Assigned(GetClass('TSalesPlugin')));
  WriteLn('host11 ok');
end.
