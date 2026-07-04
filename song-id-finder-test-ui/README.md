# 영상 배경음악 인식 테스트 GUI

`song-id-finder` Rust 모듈이 만드는 HTTP 호출을 그대로 PowerShell로 옮겨서, 실제
영상으로 손으로 눌러보며 테스트하는 프로그램입니다. `reels-fhd-test-ui`와 같은
방식(PowerShell + WinForms, 설치 없이 `run.bat` 더블클릭)입니다.

**영상/음원을 다운로드하는 기능은 없습니다.** 곡을 찾아서 유튜브 링크만 만들어줍니다.

## 필요한 것

- **ffmpeg가 PATH에 설치돼 있어야 합니다.** ([ffmpeg.org](https://ffmpeg.org)) 없으면 위쪽에 빨간 경고가 뜨고 버튼이 비활성화됩니다.
- AcoustID를 쓰려면 **Chromaprint의 `fpcalc`**가 PATH에 있어야 합니다. ([acoustid.org/chromaprint](https://acoustid.org/chromaprint)) 없으면 주황색 경고만 뜨고, AcoustID만 건너뜁니다 (다른 서비스는 정상 동작).
- 서비스별 API 키는 최소 하나만 있으면 됩니다. 키를 안 넣은 서비스는 그냥 건너뜁니다.

## 실행 방법

1. 이 리포를 본인 컴퓨터에 `git pull`
2. `song-id-finder-test-ui` 폴더의 `run.bat` 더블클릭
3. 영상 선택 (Browse 또는 드래그앤드롭) → API 키 입력(한 번 입력하면 다음부터 자동으로 채워짐) → **Identify Song** 클릭

## 기능

- 영상에서 앞부분 20초만 오디오로 추출 (ffmpeg)
- 키가 설정된 서비스(AudD / ACRCloud / AcoustID)를 전부 돌려서 각각 결과 표시
- 매칭된 곡마다 유튜브 링크 생성 (YouTube Data API 키가 있으면 검색 1등 영상 직행 링크, 없으면 검색결과 페이지 링크) — 클릭하면 기본 브라우저로 열림

## 검증 관련 참고

이 환경은 Linux 샌드박스라 실제 WinForms 창을 띄워서 끝까지 눌러보는 검증은 못
했습니다. 대신 아래는 실제로 돌려서 확인했습니다:

- PowerShell 파서로 전체 스크립트 구문 오류 없음 확인
- HMAC-SHA1 서명 로직을 표준 테스트 벡터로 검증 (정확히 일치)
- 멀티파트 업로드 함수(`Invoke-MultipartUpload`)를 로컬 에코 서버에 실제로 쏴서 필드값과 파일 바이트가 정확히 전달되는 것 확인
- 각 서비스의 "매칭 없음"/에러 응답 형태(예: ACRCloud가 `metadata` 키 자체를 안 주는 경우, AcoustID가 `results`가 비어있거나 `recordings`가 없는 경우)를 흉내낸 JSON으로 널 안전성 확인 — PowerShell은 `$null[0]` 같은 배열 인덱싱을 바로 하면 에러가 나서, `Get-SafeFirst` 헬퍼로 감쌌습니다

실제 API 키로 처음 실행할 때 한 번 테스트해보시는 걸 권장합니다 (특히 ACRCloud는 호스트 지역(`identify-eu-west-1.acrcloud.com` 등)이 가입한 프로젝트마다 다릅니다 - 콘솔에서 확인).
