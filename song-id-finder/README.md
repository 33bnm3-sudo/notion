# 영상 배경음악 인식기 (백엔드 로직)

쇼츠/릴스 영상을 넣으면 배경음악의 곡 제목/아티스트를 찾아주고, 유튜브 링크까지
만들어주는 핵심 로직만 미리 만들어 둔 것입니다. 단독 실행 프로그램이 아니라,
나중에 Tauri 앱(타임랩스 메이커 등)에 그대로 붙여 넣을 Rust 모듈(`src/lib.rs`)입니다.

**영상/음원 파일을 다운로드하는 기능은 없습니다.** 여기서 만드는 건 "이 노래가
뭔지 찾아서 링크로 알려주는 것"까지입니다. 링크를 열어서 유튜브의 "이 사운드
사용하기" 기능으로 라이선스된 음원을 쓰거나, 정식 구매/스트리밍 서비스로
이어가는 건 사용하는 사람 몫입니다.

## 전제

- `ffmpeg`가 PATH에 있어야 합니다 (오디오 추출용).
- AcoustID를 쓰려면 Chromaprint의 `fpcalc` 실행 파일이 PATH에 있어야 합니다.
- 인식 서비스는 API 키가 있는 것만 자동으로 돌아갑니다. 하나도 설정 안 하면
  `identify_song_all`은 빈 배열을 반환합니다.

## 처리 파이프라인

1. `extract_audio` — ffmpeg로 영상에서 오디오 앞부분(기본 파라미터로 원하는 초만큼)만 mp3로 추출. 업로드 용량/시간 절약.
2. `identify_song_all` — 설정된 서비스를 전부 돌려서 각각 결과를 모음:
   - **AudD** (`identify_with_audd`) — 무료 티어 있음, 상업 트렌드 음원 커버리지 좋음.
   - **ACRCloud** (`identify_with_acrcloud`) — 무료 체험 크레딧, HMAC-SHA1 서명 필요.
   - **AcoustID** (`identify_with_acoustid`) — 완전 무료, Chromaprint 지문 기반. 정식 발매 음원 위주라 쇼츠 트렌드 리믹스/속도조절 사운드는 놓칠 수 있음.
   - 서비스 하나가 실패해도 나머지 결과는 그대로 반환됩니다. 여러 개를 동시에 돌리는 이유는 서비스마다 데이터베이스가 달라 하나만으론 인식 성공률이 낮기 때문입니다.
3. `youtube_search_url` / `youtube_top_result_url` — 찾은 곡 제목/아티스트로 유튜브 링크 생성:
   - `youtube_search_url`: API 키 없이 항상 되는 검색결과 페이지 링크.
   - `youtube_top_result_url`: YouTube Data API 키가 있으면 검색 결과 1등 영상으로 바로 연결.

## API 키 발급

| 서비스 | 발급 위치 | 비용 |
|---|---|---|
| AudD | https://dashboard.audd.io/ | 무료 티어 (가입 시 확인) |
| ACRCloud | https://console.acrcloud.com/ | 무료 체험 크레딧, 이후 사용량 과금 |
| AcoustID | https://acoustid.org/api-key | 무료 (비상업적 개인 용도) |
| YouTube Data API | https://console.cloud.google.com/apis/library/youtube.googleapis.com | 무료 할당량 (하루 10,000 유닛, 검색 1회 100유닛 ≈ 하루 100회) |

## Tauri 앱에 합칠 때

```rust
#[tauri::command]
async fn identify_bgm(video_path: String) -> Result<Vec<String>, String> {
    let audio_path = std::env::temp_dir().join("bgm_sample.mp3");
    song_id_finder::extract_audio(std::path::Path::new(&video_path), &audio_path, 20)?;

    let config = song_id_finder::IdConfig {
        audd_token: Some("...".into()),
        acrcloud: None,
        acoustid_api_key: Some("...".into()),
    };

    let results = song_id_finder::identify_song_all(&audio_path, &config);
    Ok(results
        .into_iter()
        .filter_map(|r| r.result.ok().flatten())
        .map(|m| song_id_finder::youtube_search_url(&m.title, &m.artist))
        .collect())
}
```

## 아직 안 정한 것 (필요하면 다음에 채우기)

- 여러 서비스 결과 중 뭘 "정답"으로 고를지(다수결/최고 score/AudD 우선 등) — 지금은 전부 반환만 하고 판단은 호출하는 쪽 몫
- 오디오 추출 구간을 앞부분 고정이 아니라 여러 구간 샘플링
- API 키 저장/암호화 방식 (지금은 호출자가 알아서 넘겨야 함)
