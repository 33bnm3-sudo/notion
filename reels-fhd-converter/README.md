# 릴스/쇼츠 FHD 변환기 (백엔드 로직)

4K 이상 화질로 찍은 영상을 릴스/쇼츠용 FHD로 다운스케일하면서 화질을 개선하는 핵심 로직만 미리 만들어 둔 것입니다. 단독 실행 프로그램이 아니라, 나중에 Tauri 앱에 그대로 붙여 넣을 Rust 모듈(`src/lib.rs`)입니다.

## 전제

- `ffmpeg`, `ffprobe`가 실행 환경 PATH에 있어야 합니다 (Tauri 프로젝트에 이미 포함돼 있다고 하셔서 별도 번들링 로직은 넣지 않았습니다).
- 이미지 변환은 뺐습니다. 영상 전용입니다.
- 배치 처리는 뺐습니다. 파일 하나를 확실히 처리하는 데 집중합니다.

## 처리 파이프라인 (`convert_to_fhd`)

1. `ffprobe`로 원본 해상도 확인 → 가로가 세로보다 길면 가로(1920x1080), 아니면 세로(1080x1920)로 목표 해상도 자동 결정 → 원본이 그보다 작으면 업스케일을 막기 위해 에러 반환
2. `hqdn3d` 디노이즈 — 폰카메라 근접샷(2m 이내)에서 흔한 저조도 노이즈 제거. 샤프닝보다 먼저 적용해야 노이즈가 같이 도드라지지 않음
3. `scale` (Lanczos, 강제 스트레치) — 종횡비 유지 없이 목표 해상도로 그대로 늘림/줄임
4. `unsharp` — 다운스케일로 흐려진 디테일을 살짝 복구
5. `libx265`(H.265) 인코딩 — CRF 기반, 압축 효율 우선. 프레임레이트는 원본 그대로 유지(재인코딩 안 함)
6. 오디오는 재인코딩 없이 원본 그대로 복사(`-c:a copy`)

가로 영상과 세로 영상을 각각 따로 넣어도 파일마다 알아서 맞는 방향으로 처리됩니다. 호출하는 쪽에서 방향을 지정할 필요 없음.

## 옵션 (`ConvertOptions`)

| 필드 | 설명 | 기본값 |
|---|---|---|
| `crf` | 낮을수록 고화질·큰 용량. 18~28 권장 | `26` |
| `preset` | x265 인코딩 프리셋. 압축 효율 우선이면 `slow`~`veryslow` (그만큼 느려짐) | `"slow"` |

밤새 켜두고 인코딩할 거라고 하셨으니 속도보다 압축 효율을 우선했습니다. 더 압축하고 싶으면 `preset`을 `"veryslow"`로, 용량을 더 줄이고 싶으면 `crf`를 28~30 쪽으로 올리면 됩니다.

## Tauri 앱에 합칠 때

`convert_to_fhd(input, output, &opts)`를 그대로 `#[tauri::command]` 함수 안에서 호출하면 됩니다. 예:

```rust
#[tauri::command]
async fn convert_video(input: String, output: String) -> Result<(), String> {
    let opts = reels_fhd_converter::ConvertOptions::default();
    reels_fhd_converter::convert_to_fhd(
        std::path::Path::new(&input),
        std::path::Path::new(&output),
        &opts,
    )
}
```

## 아직 안 정한 것 (필요하면 다음에 채우기)

- 진행률(progress) 콜백 — ffmpeg `-progress` 옵션으로 stdout 파싱해서 UI 프로그레스바에 연결 가능
- 변환 취소 기능
- HDR 원본(폰 시네마틱/HDR 촬영 모드) → SDR 톤매핑 처리
