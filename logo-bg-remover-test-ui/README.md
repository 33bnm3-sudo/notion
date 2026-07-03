# 로고 배경 제거 테스트 GUI

`logo-bg-remover` Rust 모듈을 실제 이미지로 손으로 눌러보며 테스트하는 프로그램입니다. `gemini-image-test-ui`, `reels-fhd-test-ui`, `logo-to-svg-test-ui`와 같은 방식(PowerShell + WinForms)이지만, **이번엔 exe가 리포에 같이 들어있지 않습니다.** 딱 한 번 직접 빌드하셔야 해요.

## 왜 exe가 없나요

`logo-bg-remover`는 AI 세그멘테이션 모델(ONNX)을 돌리는데, 빌드할 때 `ort` 크레이트가 ONNX Runtime 바이너리를 자동으로 다운로드합니다. 이게 두 가지 이유로 여기(원격 샌드박스)에서 못 만들었어요:

1. 이 샌드박스의 네트워크 정책이 그 다운로드 주소(`cdn.pyke.io`)를 막고 있음
2. `logo-to-svg`처럼 mingw로 크로스 컴파일을 시도해봤는데, `ort`가 애초에 Windows GNU 타입(MinGW) 빌드용 사전 컴파일 바이너리를 제공하지 않고 MSVC 타입만 지원합니다 — 즉 이 방식 자체가 리눅스에서는 안 되는 조합이에요

그래서 `logo-to-svg-cli.exe`처럼 미리 빌드해서 넣어드릴 수가 없었습니다. 대신 CLI 진입점(`logo-bg-remover/src/bin/logo-bg-remover-cli.rs`)만 만들어뒀고, **본인 컴퓨터(정상적인 인터넷 + Windows용 MSVC 빌드 도구)에서 딱 한 번 빌드**하면 됩니다.

## 빌드 방법 (한 번만 하면 됨)

1. [Rust 설치](https://rustup.rs) (윈도우용 설치 시 "Visual Studio C++ Build Tools" 설치도 같이 안내됨 — 그것도 설치)
2. 이 리포의 `logo-bg-remover` 폴더로 이동
3. `cargo build --release` 실행 (처음엔 ONNX Runtime 다운로드 때문에 시간 좀 걸림)
4. 빌드가 끝나면 `logo-bg-remover\target\release\logo-bg-remover-cli.exe` 생김
5. 그 파일을 복사해서 이 폴더(`logo-bg-remover-test-ui`)에 붙여넣기

## 검증 관련 참고

이 CLI 코드(`logo-bg-remover-cli.rs`)는 이 샌드박스에서 컴파일 자체를 못 해봤습니다 (위에 설명한 네트워크 제약 때문에, 크로스 컴파일도 네이티브 빌드도 둘 다 막혀서). `logo-to-svg-cli.rs`랑 완전히 같은 패턴(인자 파싱, 에러 처리)으로 작성했고, `logo-bg-remover` 라이브러리의 실제 함수 시그니처(`ensure_model_downloaded()`, `remove_background(model_path, input, output)`)를 그대로 가져다 썼지만, **실제로 빌드/실행해서 검증은 못 한 코드**라는 점 꼭 알아주세요. 빌드하실 때 에러가 나면 알려주시면 바로 고쳐드릴게요.

## 실행 방법 (빌드 후)

1. 이 리포를 본인 컴퓨터에 `git pull` (또는 빌드 후 다시 pull)
2. `logo-bg-remover-test-ui` 폴더의 `run.bat` 더블클릭

## 기능

- **입력 이미지** — Browse 또는 드래그앤드롭 (png/jpg/jpeg)
- **출력 PNG** — 입력을 고르면 자동으로 `원본이름-nobg.png`로 채워지고, Save As로 바꿀 수 있습니다
- 첫 실행 시 모델 파일(~176MB)을 자동으로 다운로드합니다 (한 번만, 이후엔 캐시 사용)
- 변환 후 결과 PNG가 탐색기에서 선택된 채로 열립니다
