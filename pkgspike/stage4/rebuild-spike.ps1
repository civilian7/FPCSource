# stage4 재빌드 - 런타임/디자인타임 패키지 검증 트리.
#
# stage3rt/rebuild-spike.ps1 과 같은 이유로 존재한다: 툴체인이 바뀌면
# 전부 다시 지어야 하는데 순서와 플래그를 기억에만 두면 틀린다.
#
# DirBad 는 {$DESIGNONLY}{$RUNONLY} 를 동시에 선언한 **의도된 거부 대상**이라
# 컴파일이 실패하는 것이 정상이다. Host1 도 마찬가지로 링크되면 안 되는 쪽이다.

param(
  [string]$Ppc = 'C:\works\fpc-unleashed\compiler\fcc64.exe',
  [string]$ResDir = 'C:\fpcunleashed\fpc322\bin\i386-win32'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$bases = @{
  'rtlpkg'  = '110000000'
  'BasePkg' = '120000000'
  'RegPkg'  = '130000000'
  'Reg2Pkg' = '140000000'
  'RunPkg'  = '150000000'
  'DirOk'   = '160000000'
  'DirRun'  = '170000000'
}

# 의존 순서. DirBad 는 여기 없다 - 거부되는 것이 기대값이라 따로 확인한다
$packages = @('rtlpkg', 'BasePkg', 'RegPkg', 'Reg2Pkg', 'RunPkg', 'DirOk', 'DirRun')
$units = @{
  'BasePkg' = @('BaseRegUnit')
  'RegPkg'  = @('RegUnit', 'RegUnit2')
  'Reg2Pkg' = @('Reg2Unit')
  'RunPkg'  = @('PlainUnit')
  'DirOk'   = @()          # PlainUnit 은 RunPkg 에서 이미 지었다
  'DirRun'  = @()
}

Get-ChildItem -Filter '*.fpl' | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Filter '*.fcp' | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem -Filter '*.exe' | Remove-Item -Force -ErrorAction SilentlyContinue

function Invoke-Ppc {
  param([string[]]$PpcArgs, [string]$What)

  & $Ppc @PpcArgs 2>&1 | Out-String -OutVariable out | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  [FAIL] $What"
    Write-Host $out
    exit 1
  }
}

foreach ($p in $packages) {
  if ($units.ContainsKey($p)) {
    foreach ($u in $units[$p]) {
      Invoke-Ppc @('-FE.', '-FU.', "$u.pas") "$p / $u"
    }
  }

  Invoke-Ppc @('-FE.', '-FU.', "-WB$($bases[$p])", '-Xm', "$p.dpk") "패키지 $p"
  Write-Host "  [OK]   $p.fpl"
}

foreach ($h in @('host13', 'host14', 'Probe')) {
  Invoke-Ppc @('-FPrtlpkg', "-FD$ResDir", "$h.pas") "호스트 $h"
  Write-Host "  [OK]   $h.exe"
}

Write-Host ''
Write-Host '재빌드 완료'
