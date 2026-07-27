program host9;

{ 가설 검증: host8 은 SharedIntf 심볼을 참조하지 않으므로 CommonPkg 를
  임포트하지 않고, CommonPkg 는 SalesPkg 의 의존성으로만 로드된다.
  그렇다면 FreeLibrary(SalesPkg) 가 CommonPkg 까지 언맵하고,
  Classlist 에 남은 TPluginBase 항목이 dangling 이 된다.

  GetClass 는 일절 호출하지 않는다(AV 회피) — 모듈 핸들과
  저장해둔 VMT 포인터의 소속만 VirtualQuery 로 관찰한다. }

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

function OwnerImage(APtr: Pointer): string;
var
  LInfo: TMemoryBasicInformation;
  LBuf: array[0..259] of Char;
  LLen: DWORD;
begin
  if VirtualQuery(APtr, LInfo, SizeOf(LInfo)) = 0 then
    Exit('<unqueryable>');

  if LInfo.State <> MEM_COMMIT then
    Exit(Format('<unmapped state=%x>', [LInfo.State]));

  LLen := GetModuleFileName(HMODULE(LInfo.AllocationBase), LBuf, Length(LBuf));
  if LLen = 0 then
    Result := Format('<anonymous @%p>', [LInfo.AllocationBase])
  else
    Result := ExtractFileName(Copy(LBuf, 1, LLen));
end;

procedure DumpModules(const ATag: string);
begin
  WriteLn('== ', ATag, ' ==');
  WriteLn('    rtlpkg    handle = ', IntToHex(GetModuleHandle('rtlpkg.dll'), 1));
  WriteLn('    CommonPkg handle = ', IntToHex(GetModuleHandle('CommonPkg.dll'), 1));
  WriteLn('    SalesPkg  handle = ', IntToHex(GetModuleHandle('SalesPkg.dll'), 1));
end;

var
  GLib: HMODULE;
  GTable: PInitFinalTable;
  I: PtrUInt;
  GBase: Pointer;
  GSales: Pointer;
begin
  DumpModules('로드 전');

  GLib := LoadLibrary('SalesPkg.dll');
  GTable := PInitFinalTable(GetProcAddress(GLib, 'INITFINAL'));
  for I := 1 to GTable^.TableCount do
  begin
    if Assigned(GTable^.Procs[I].InitProc) then
      GTable^.Procs[I].InitProc();
    GTable^.InitCount := I;
  end;

  DumpModules('로드 후');

  { GetClass 는 지금(안전할 때) 한 번만 사용해 VMT 포인터를 캡처 }
  GBase := Pointer(GetClass('TPluginBase'));
  GSales := Pointer(GetClass('TSalesPlugin'));
  WriteLn('    TPluginBase  vmt=', HexStr(GBase), '  ', OwnerImage(GBase));
  WriteLn('    TSalesPlugin vmt=', HexStr(GSales), '  ', OwnerImage(GSales));

  while GTable^.InitCount > 0 do
  begin
    Dec(GTable^.InitCount);
    if Assigned(GTable^.Procs[GTable^.InitCount + 1].FinalProc) then
      GTable^.Procs[GTable^.InitCount + 1].FinalProc();
  end;

  FreeLibrary(GLib);

  DumpModules('FreeLibrary 후');
  WriteLn('    TPluginBase  vmt=', HexStr(GBase), '  ', OwnerImage(GBase));
  WriteLn('    TSalesPlugin vmt=', HexStr(GSales), '  ', OwnerImage(GSales));

  WriteLn('host9 ok - 종료 경로 진입');
end.
