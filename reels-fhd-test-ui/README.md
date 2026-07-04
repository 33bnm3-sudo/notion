# 릴스 FHD 변환 테스트 GUI

`reels-fhd-converter` Rust 모듈이 만드는 ffmpeg 명령을 그대로 PowerShell로 옮겨서, 실제 영상으로 손으로 눌러보며 테스트하는 프로그램입니다. `gemini-image-test-ui`와 같은 방식(PowerShell + WinForms, 설치 없이 `run.bat` 더블클릭)입니다.

## 필요한 것

**ffmpeg와 ffprobe가 PATH에 설치돼 있어야 합니다.** ([ffmpeg.org](https://ffmpeg.org)에서 다운로드) 없으면 프로그램 위쪽에 빨간 경고가 뜨고 Convert 버튼이 비활성화됩니다.

## 실행 방법

1. 이 리포를 본인 컴퓨터에 `git pull`
2. `reels-fhd-test-ui` 폴더의 `run.bat` 더블클릭

## 기능

- **입력 영상** — Browse 또는 드래그앤드롭 (mp4/mov/mkv/avi/webm/m4v)
- **출력 경로** — 입력 파일을 고르면 자동으로 `원본이름-fhd.mp4`로 채워지고, Save As로 바꿀 수 있습니다
- **CRF** (0~51, 기본 26) — 낮을수록 고화질/큰 용량
- **Preset** (기본 slow) — 느릴수록 압축 효율 좋음
- 세로/가로는 원본 해상도를 보고 자동 판단 (Rust 모듈과 동일 로직)
- 변환 중 ffmpeg 진행 로그가 그대로 표시되고, 끝나면 결과 파일이 탐색기에서 선택된 채로 열립니다

## 검증 관련 참고

이 환경에는 ffmpeg가 없어서 실제 영상으로 끝까지 돌려보는 검증은 못 했습니다. `reels-fhd-converter` Rust 모듈이 만드는 ffmpeg 명령(디노이즈 → Lanczos 리사이즈 → 언샵 → libx265)을 그대로 옮겨 적었고, 코드를 여러 번 읽으면서 확인했습니다. 처음 실행할 때 짧은 영상으로 한 번 테스트해보시는 걸 권장합니다.
