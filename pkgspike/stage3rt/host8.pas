program host8;

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

{ 어느 이미지 소속인지 이름으로 알려준다 }
function OwnerImage(APtr: Pointer): string;
var
  LInfo: TMemoryBasicInformation;
  LBuf: array[0..259] of Char;
  LLen: DWORD;
begin
  Result := '?';
  if VirtualQuery(APtr, LInfo, SizeOf(LInfo)) = 0 then
    Exit;

  LLen := GetModuleFileName(HMODULE(LInfo.AllocationBase), LBuf, Length(LBuf));
  if LLen = 0 then
    Result := Format('<unmapped @%p>', [LInfo.AllocationBase])
  else
    Result := ExtractFileName(Copy(LBuf, 1, LLen));
end;

procedure Probe(const AName: string);
var
  LCls: TPersistentClass;
begin
  LCls := GetClass(AName);
  if LCls = nil then
    WriteLn(Format('    %-16s (none)', [AName]))
  else
    WriteLn(Format('    %-16s vmt=%p  %s', [AName, Pointer(LCls), OwnerImage(Pointer(LCls))]));
end;

procedure DumpClasses(const ATag: string);
begin
  WriteLn('== ', ATag, ' ==');
  Probe('TSalesPlugin');
  Probe('TPluginBase');
  Probe('TPersistent');
end;

var
  GLib: HMODULE;
  GTable: PInitFinalTable;
  I: PtrUInt;
begin
  DumpClasses('로드 전');

  GLib := LoadLibrary('SalesPkg.fpl');
  GTable := PInitFinalTable(GetProcAddress(GLib, 'INITFINAL'));
  for I := 1 to GTable^.TableCount do
  begin
    if Assigned(GTable^.Procs[I].InitProc) then
      GTable^.Procs[I].InitProc();
    GTable^.InitCount := I;
  end;

  DumpClasses('로드 후');

  while GTable^.InitCount > 0 do
  begin
    Dec(GTable^.InitCount);
    if Assigned(GTable^.Procs[GTable^.InitCount + 1].FinalProc) then
      GTable^.Procs[GTable^.InitCount + 1].FinalProc();
  end;

  DumpClasses('finalize 후 (FreeLibrary 전)');

  FreeLibrary(GLib);

  DumpClasses('FreeLibrary 후');

  WriteLn('host8 ok - 이제 종료 경로로 진입');
end.
