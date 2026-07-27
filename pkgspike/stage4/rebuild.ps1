# stage4 재현 케이스 전체 재빌드 + 회귀 실행.
#
# stage4 는 두 종류의 픽스처를 담는다:
#   ① 컴파일러↔호스트 이음매 — DirOk/DirBad/DirRun/RunPkg/Host1.
#      PACKAGEFLAGS 비트값, 메시지 13030(지시어 둘 다 선언), 13031(디자인타임
#      전용을 프로그램에 링크). 둘은 **컴파일이 실패해야 정상**이라 검사가
#      뒤집힌다 - 성공하면 스크립트가 실패한다.
#   ② 등록/언로드 — BasePkg/RegPkg/Reg2Pkg/host13/host14.
#
# 예전에는 아래 'Remove-Item *.ppu, *.o, *.a' 가 디렉터리 전체를 지우면서
# ①은 다시 짓지 않아, 임포트 라이브러리가 사라진 채 옛 .dll/.exe 만 남고
# 다시 링크할 수도 없었다. 지금은 둘 다 짓고, 지은 다음 실제로 돌려본다.
#
# stage3rt\rebuild.ps1 과 같은 순서 규칙을 따른다:
#   ① contained 유닛을 -FP **없이** 선컴파일
#   ② 패키지(.dpk)
#   ③ 호스트만 -FP 를 받는다
#
# 각 패키지는 -WB 로 ImageBase 를 분리한다.
#
#   .\rebuild.ps1
#
# 종료 코드 0 = 전부 기대대로, 1 = 하나라도 어긋남.

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\fcc64.exe'
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot

$script:Failed = 0

function Write-Fail {
  param([string]$Message)

  Write-Host "  [FAIL] $Message" -ForegroundColor Red
  $script:Failed++
}

function Invoke-Ppc {
  param([string]$What, [string[]]$PpcArgs)

  $out = & $Ppc @PpcArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    $out | Select-String -Pattern 'Error:|Fatal:' | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    throw "$What 실패 (exit $LASTEXITCODE)"
  }

  Write-Host ("  [OK] {0}" -f $What)
}

# 컴파일이 **실패해야** 정상인 픽스처. 성공하면 그 자체가 회귀다.
# $Message 로 기대 진단번호까지 확인한다 - 다른 이유로 실패하면 픽스처가
# 증명하려던 것을 더는 증명하지 않기 때문이다.
function Invoke-PpcExpectFail {
  param([string]$What, [string]$Message, [string[]]$PpcArgs)

  # -vq: 진단에 메시지 번호를 붙인다. 없으면 본문만 나와서 "무엇으로
  # 거부됐는가" 를 번호로 못 잡는다.
  $PpcArgs = @('-vq') + $PpcArgs
  $out = & $Ppc @PpcArgs 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Fail "$What - 컴파일이 성공했다 (실패해야 한다)"
    return
  }

  if (($out -join "`n") -notmatch $Message) {
    $out | Select-String -Pattern 'Error:|Fatal:' | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    Write-Fail "$What - 실패는 했으나 기대 진단($Message)이 아니다"
    return
  }

  Write-Host ("  [OK] {0} (기대대로 거부: {1})" -f $What, $Message)
}

# Probe 가 읽어 온 PACKAGEFLAGS 비트값을 검사한다.
# bit 0 = designonly, bit 1 = runonly.
function Test-PackageFlags {
  param([string]$Dll, [int]$Expected)

  $out = & .\Probe.exe $Dll 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "Probe $Dll - exit $LASTEXITCODE"
    return
  }

  $m = ($out -join "`n") | Select-String -Pattern 'PACKAGEFLAGS\s*=\s*(\d+)'
  if (-not $m) {
    Write-Fail "Probe $Dll - PACKAGEFLAGS 를 읽지 못했다"
    return
  }

  $actual = [int]$m.Matches[0].Groups[1].Value
  if ($actual -ne $Expected) {
    Write-Fail "Probe $Dll - PACKAGEFLAGS = $actual (기대 $Expected)"
    return
  }

  Write-Host ("  [OK] {0} PACKAGEFLAGS = {1}" -f $Dll, $actual)
}

function Test-HostExit {
  param([string]$Exe, [int]$Expected)

  if (-not (Test-Path $Exe)) {
    Write-Fail "$Exe 가 없다"
    return
  }

  $out = & ".\$Exe" 2>&1
  $code = $LASTEXITCODE
  if ($code -ne $Expected) {
    $out | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    Write-Fail "$Exe - exit $code (기대 $Expected)"
    return
  }

  Write-Host ("  [OK] {0} exit {1}" -f $Exe, $code)
}

try {
  Write-Host '중간 산출물 제거'
  Remove-Item *.ppu, *.o, *.a -ErrorAction SilentlyContinue
  # 거부되어야 하는 픽스처의 옛 산출물도 지운다. 남겨두면 "이번에도
  # 안 지어졌다" 와 "옛 바이너리가 그대로 있다" 를 구분할 수 없다.
  Remove-Item DirBad.dll, Host1.exe -ErrorAction SilentlyContinue

  Write-Host 'RTL 패키지'
  # -Xm: 맵 파일. 있어야 장애 주소를 "이미지 범위 안" 추정이 아니라
  # 심볼로 확정할 수 있다 (stage3rt 도 같은 이유로 넘긴다).
  Invoke-Ppc 'rtlpkg.dpk' @('-WB110000000', '-Xm', 'rtlpkg.dpk')

  Write-Host '유닛 선컴파일 (-FP 없이)'
  foreach ($u in @('PlainUnit.pas', 'BaseRegUnit.pas', 'RegUnit.pas', 'RegUnit2.pas', 'Reg2Unit.pas')) {
    Invoke-Ppc $u @($u)
  }

  Write-Host '지시어 픽스처 패키지'
  # DirOk = designonly(1), DirRun = 지시어 없음(0), RunPkg = runonly(2).
  Invoke-Ppc 'DirOk.dpk'  @('-WB25000000', 'DirOk.dpk')
  Invoke-Ppc 'DirRun.dpk' @('-WB26000000', 'DirRun.dpk')
  Invoke-Ppc 'RunPkg.dpk' @('-WB27000000', 'RunPkg.dpk')
  # DirBad 는 {$DESIGNONLY} 와 {$RUNONLY} 를 동시에 선언한다 - 13030.
  Invoke-PpcExpectFail 'DirBad.dpk' '13030' @('-WB28000000', 'DirBad.dpk')

  Write-Host '등록/언로드 패키지'
  Invoke-Ppc 'BasePkg.dpk' @('-WB22000000', 'BasePkg.dpk')
  Invoke-Ppc 'RegPkg.dpk'  @('-WB23000000', 'RegPkg.dpk')
  # Reg2Pkg 도 BasePkg 를 requires 한다 - host14 가 요구하는 공유 의존.
  Invoke-Ppc 'Reg2Pkg.dpk' @('-WB24000000', 'Reg2Pkg.dpk')

  Write-Host '호스트 (-FP 는 여기서만)'
  # host13/host14 는 rtlpkg 만 링크한다. BasePkg 를 링크하면 핀 고정되어
  # 의존 언매핑이 일어나지 않고 회귀가 무의미해진다.
  Invoke-Ppc 'host13.pas' @('-FPrtlpkg', 'host13.pas')
  Invoke-Ppc 'host14.pas' @('-FPrtlpkg', 'host14.pas')
  Invoke-Ppc 'Probe.pas'  @('Probe.pas')
  # Host1 은 디자인타임 전용 패키지를 프로그램에 링크하려 한다 - 13031.
  Invoke-PpcExpectFail 'Host1.pas -FPDirOk' '13031' @('-FPDirOk', 'Host1.pas')
  if (Test-Path 'Host1.exe') {
    Write-Fail 'Host1.exe 가 만들어졌다 (링크가 거부되어야 한다)'
  }

  Write-Host '회귀: PACKAGEFLAGS 비트값'
  Test-PackageFlags 'DirOk.dll'  1
  Test-PackageFlags 'DirRun.dll' 0
  Test-PackageFlags 'RunPkg.dll' 2

  Write-Host '회귀: 호스트 실행'
  Test-HostExit 'host13.exe' 0
  Test-HostExit 'host14.exe' 0

  if ($script:Failed -gt 0) {
    Write-Host ("재빌드 실패 - {0}건 어긋남" -f $script:Failed) -ForegroundColor Red
    exit 1
  }

  Write-Host '재빌드 + 회귀 통과' -ForegroundColor Green
}
finally {
  Pop-Location
}
