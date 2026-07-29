# Win64 동적 패키지 작업용 컴파일러 빌드 스크립트.
#
# 부트스트랩 컴파일러(설치본 ppcx64)로 이 저장소의 컴파일러를 빌드한다.
# 산출물: compiler\fcc64.exe
#
#   .\build-ppc.ps1            # 빌드
#   .\build-ppc.ps1 -Clean     # 산출물 지우고 빌드

param(
    [switch]$Clean,
    # 스택 트레이스에 파일·행이 찍히게 한다. 패키지 경로를 파고들 때 필수.
    # ⚠️ -O2 이상은 프레임 포인터를 생략해 트레이스를 망가뜨리므로 -O1 로 낮춘다.
    [switch]$Debug,
    # 빌드한 컴파일러를 여기로 배포한다. 빈 문자열이면 배포하지 않는다.
    # LumiPascal 는 이것을 lumi.json 의 compiler.path 로 가리켜 환경변수 없이 선다.
    [string]$DeployTo = 'C:\works\LumiPascal\bin'
)

$ErrorActionPreference = 'Stop'

$Bootstrap = 'C:\fpcunleashed\fpc\bin\x86_64-win64\ppcx64.exe'
$Root      = $PSScriptRoot
$Compiler  = Join-Path $Root 'compiler'
$Output    = Join-Path $Compiler 'fcc64.exe'

if (-not (Test-Path $Bootstrap)) {
    throw "부트스트랩 컴파일러를 찾을 수 없습니다: $Bootstrap"
}

if ($Clean) {
    Get-ChildItem $Compiler -Include *.ppu, *.o -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Force
    Remove-Item $Output -Force -ErrorAction SilentlyContinue
}

# msgtxt.inc / msgidx.inc 는 msg\errore.msg 에서 생성되는 파일이라 저장소에 없다.
# Makefile 의 `msgtxt.inc: $(MSGFILE)` 규칙과 같은 일을 한다.
$MsgTxt  = Join-Path $Compiler 'msgtxt.inc'
$MsgFile = Join-Path $Compiler 'msg\errore.msg'

if ($Clean) {
    Remove-Item $MsgTxt, (Join-Path $Compiler 'msgidx.inc') -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $MsgTxt) -or
    ((Get-Item $MsgFile).LastWriteTime -gt (Get-Item $MsgTxt).LastWriteTime)) {

    Write-Host '  메시지 테이블 생성 (msg2inc)'
    Push-Location $Compiler
    try {
        & $Bootstrap -FE. utils\msg2inc.pp 2>&1 | Select-String 'Fatal|Error:' | Out-Host
        & .\msg2inc.exe msg\errore.msg msg msg 2>&1 | Out-Null

        if (-not (Test-Path $MsgTxt)) {
            throw 'msgtxt.inc 생성 실패'
        }
    }
    finally {
        Pop-Location
    }
}

Push-Location $Compiler
try {
    # -Fu 는 유닛 검색 경로, -Fi 는 include 검색 경로. x86_64 는 x86 의 공용 코드를 함께 쓴다.
    #
    # 하나의 OS(Windows), 하나의 타깃(Win64)만 지원한다 - 좁지만 깊게.
    # x86_64/cputarg.pas 가 {$ifndef NOTARGETxxx} 로 감싸 둔 opt-out 스위치를 쓴다.
    # 스탭스도 뺀다 - 우리는 DWARF(-gw3)만 쓴다.
    #
    # ⚠️ define 을 바꾼 뒤에는 반드시 -Clean 으로 지어야 한다. FPC 는 define 이
    #    달라져도 기존 .ppu 를 재사용하므로(실측), systems\·x86_64\ 의 낡은
    #    .ppu 가 남아 있으면 스위치가 조용히 무시된다.
    $narrow = @(
        '-dNOTARGETLINUX', '-dNOTARGETFREEBSD', '-dNOTARGETDARWIN',
        '-dNOTARGETNATIVENT', '-dNOTARGETSUNOS', '-dNOTARGETAROS',
        '-dNOTARGETHAIKU', '-dNOTARGETEMBEDDED', '-dNOTARGETANDROID',
        '-dNoDbgStabs'
    )

    $fa = @(
        '-dx86_64', '-dGDB',
        '-Fux86_64', '-Fux86', '-Fusystems',
        '-Fix86_64', '-Fix86', '-Fisystems', '-Fimsg',
        '-FE.', '-ofcc64'
    ) + $narrow

    if ($Debug) {
        $fa += @('-O1', '-gw3', '-gl')
    }
    else {
        $fa += '-dRELEASE'
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Bootstrap @fa pp.pas 2>&1 |
        Select-String -NotMatch '^Compiling|Note:|Hint:' |
        Select-Object -Last 6
    $sw.Stop()

    # -o 가 확장자를 떼므로 되돌린다
    if (Test-Path (Join-Path $Compiler 'fcc64')) {
        Move-Item (Join-Path $Compiler 'fcc64') $Output -Force
    }

    if (-not (Test-Path $Output)) {
        throw '빌드 실패 - 산출물이 없습니다'
    }

    '{0}  ({1:N1} 초)' -f $Output, $sw.Elapsed.TotalSeconds

    if ($DeployTo) {
        $deployParent = Split-Path -Parent $DeployTo
        if ($deployParent -and -not (Test-Path $deployParent)) {
            # 배포 대상의 부모 폴더조차 없다는 것은 이 트리가 LumiPascal 워크스페이스가
            # 아니라는 뜻이다 - 관련 없는 컴퓨터에 엉뚱한 폴더를 새로 만들지 않는다.
            "배포 건너뜀: {0} 의 상위 폴더가 없습니다" -f $DeployTo
        }
        else {
            if (-not (Test-Path $DeployTo)) {
                New-Item -ItemType Directory -Path $DeployTo -Force | Out-Null
            }

            Copy-Item $Output $DeployTo -Force
            '배포: {0}' -f (Join-Path $DeployTo 'fcc64.exe')
        }
    }
}
finally {
    Pop-Location
}
