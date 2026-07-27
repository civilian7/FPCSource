# 패키지 모드(indirect ABI)로 RTL 을 다시 빌드한다.
#
# ⚠️ 왜 필요한가 — `tf_supports_packages` 는 프로젝트별 옵션이 아니라
#    타깃 전체의 ABI 스위치다. 이 플래그가 켜지면 컴파일러가 전역 데이터를
#    `..$indirect` 심볼로 참조하므로(aasmdef.pas 의 AT_DATA 처리, ncgld.pas,
#    hlcgobj.pas), 플래그 없이 빌드된 기존 RTL 과는 링크되지 않는다.
#    그래서 패치된 컴파일러를 쓰려면 RTL 도 같은 모드로 다시 지어야 한다.
#
# 산출물: rtl\units\x86_64-win64\  (약 90개 .ppu)
#
#   .\build-rtl.ps1
#   .\build-rtl.ps1 -Clean

param(
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$Root     = $PSScriptRoot
$Compiler = Join-Path $Root 'compiler\ppcx64_pkg.exe'
$RtlDir   = Join-Path $Root 'rtl'

# FPC 배포본이 함께 싣는 GNU make 와 보조 도구(cp/mv/rm/gmkdir…). RTL Makefile 이 이것들을 쓴다.
$MakeDir  = 'C:\fpcunleashed\fpc322\bin\i386-win32'

if (-not (Test-Path $Compiler)) {
    throw "패치된 컴파일러가 없습니다. 먼저 .\build-ppc.ps1 을 실행하세요: $Compiler"
}

if (-not (Test-Path (Join-Path $MakeDir 'make.exe'))) {
    throw "make.exe 를 찾을 수 없습니다: $MakeDir"
}

$env:PATH = "$MakeDir;$env:PATH"

$targets = if ($Clean) { @('clean', 'all') } else { @('all') }

Push-Location $RtlDir
try {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & make.exe @targets "PP=$Compiler" OS_TARGET=win64 CPU_TARGET=x86_64 2>&1 |
        Select-String 'Error|Fatal|Warning' |
        Select-Object -First 20
    $sw.Stop()

    if ($LASTEXITCODE -ne 0) {
        throw "RTL 빌드 실패 (exit $LASTEXITCODE)"
    }

    $units = Get-ChildItem (Join-Path $RtlDir 'units\x86_64-win64\*.ppu')
    '{0} units  ({1:N1} 초)' -f $units.Count, $sw.Elapsed.TotalSeconds
}
finally {
    Pop-Location
}
