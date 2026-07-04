# 로고 SVG 변환 테스트 GUI

`logo-to-svg` Rust 모듈을 실제 이미지로 손으로 눌러보며 테스트하는 프로그램입니다. `gemini-image-test-ui`, `reels-fhd-test-ui`와 같은 방식(PowerShell + WinForms, `run.bat` 더블클릭)이지만, 이번엔 안에서 **`logo-to-svg-cli.exe`**라는 실제 컴파일된 프로그램을 호출합니다.

## 왜 다른 것들과 다르게 exe가 같이 들어있나요

`logo-to-svg`는 순수 Rust 라이브러리(vtracer)라서 PowerShell만으로는 재현할 수 없어서, 이 리포에 있는 `logo-to-svg` 크레이트에 CLI 진입점(`src/bin/logo-to-svg-cli.rs`)을 하나 추가하고, 그걸 윈도우용으로 크로스 컴파일해서 `logo-to-svg-cli.exe`로 여기 같이 넣어뒀습니다. PowerShell GUI는 이 exe를 그냥 호출만 합니다.

## 검증 관련 참고

- 리눅스 환경에서 **같은 소스로 빌드한 리눅스 바이너리는 실제로 실행해서 검증**했습니다 (빨간 원 + 파란 사각형 테스트 이미지 → SVG로 정상 변환, 곡선 경로 확인).
- 이 폴더에 든 `.exe`는 그 **동일한 소스를 윈도우용으로 크로스 컴파일**한 것인데, 이 샌드박스가 리눅스라 그 `.exe` 자체를 직접 실행해서 검증하지는 못했습니다. vtracer는 OS별로 다르게 동작할 만한 코드가 없는 순수 이미지 처리 라이브러리라 동작이 같을 거라 보지만, **처음 쓰실 때 한 번은 직접 확인**해봐 주세요.
- exe를 신뢰하기 싫으시면, `logo-to-svg` 폴더에서 본인 컴퓨터에 Rust를 설치하고 `cargo build --release`로 직접 빌드하셔도 됩니다 (`target\release\logo-to-svg-cli.exe`가 생깁니다). 그 경우 이 폴더의 `Convert-Logo.ps1` 상단 `$CliPath`가 가리키는 위치에 복사해 넣으면 됩니다.

## 실행 방법

1. 이 리포를 본인 컴퓨터에 `git pull`
2. `logo-to-svg-test-ui` 폴더의 `run.bat` 더블클릭

## 기능

- **입력 PNG** — Browse 또는 드래그앤드롭. 배경이 투명한 PNG여야 합니다 (`logo-bg-remover` 결과물 등)
- **출력 SVG** — 입력을 고르면 자동으로 같은 이름의 `.svg`로 채워지고, Save As로 바꿀 수 있습니다
- **색상 정밀도(1-8)**, **잡티 필터**, **코너 각도** — `logo-to-svg`의 `SvgOptions`와 동일한 옵션
- 변환 후 결과 SVG가 탐색기에서 선택된 채로 열립니다
