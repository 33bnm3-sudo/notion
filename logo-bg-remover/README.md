# 로고 배경 제거기 (백엔드 로직)

로고 이미지를 SVG로 벡터화하기 전 단계로, 배경을 깔끔하게 지워서 알파 채널이 있는 PNG로 만들어주는 핵심 로직입니다. 단독 프로그램이 아니라 나중에 Tauri 앱에 붙여 넣을 Rust 모듈(`src/lib.rs`)입니다. SVG 변환 자체는 범위 밖이고, 배경 제거까지만 합니다.

## 왜 이 방식인가

로고 배경이 항상 깔끔한 흰색은 아니라고 하셔서(간판/사진 속 로고 등), 색상 하나만 보고 지우는 방식 대신 AI 세그멘테이션 모델(`isnet-general-use`, rembg 프로젝트 기본 모델)로 처리합니다. 깔끔한 단색 배경이든 복잡한 배경이든 같은 코드로 처리됩니다.

GPU 없는 서피스에서 쓰신다고 해서 실시간/배치가 아니라 이미지 한 장을 몇 초 안에 처리하는 걸 목표로 잡았습니다 (CPU 추론).

## 동작 방식

1. `ensure_model_downloaded()` — 모델 파일이 로컬 캐시(OS별 캐시 디렉토리)에 없으면 [rembg 공식 배포처](https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx)에서 자동 다운로드 (약 176MB, 최초 1회만)
2. `remove_background()` — 이미지를 1024x1024로 리사이즈해 모델에 입력 → 전경/배경 마스크 추론 → 마스크를 원본 해상도로 되돌려서 알파 채널로 합성 → PNG로 저장

## 사용 예

```rust
let model_path = logo_bg_remover::ensure_model_downloaded()?;
logo_bg_remover::remove_background(&model_path, Path::new("logo.jpg"), Path::new("logo-transparent.png"))?;
```

## Tauri 앱에 합칠 때

```rust
#[tauri::command]
async fn remove_logo_background(input: String, output: String) -> Result<(), String> {
    let model_path = logo_bg_remover::ensure_model_downloaded()?;
    logo_bg_remover::remove_background(&model_path, std::path::Path::new(&input), std::path::Path::new(&output))
}
```

앱 실행 중 처음 이 기능을 쓸 때 자동으로 모델을 다운로드하니, UI에서는 "처음 실행 시 다운로드 중..." 같은 진행 표시를 붙이면 좋습니다. 이미 만들어두신 다른 프로그램의 "확인 후 없으면 다운로드" 패턴과 동일합니다.

## 검증 관련 참고

이 샌드박스 환경은 조직 네트워크 정책상 `ort` 크레이트가 기본으로 받아오는 ONNX Runtime 바이너리 호스트(`cdn.pyke.io`)가 막혀 있어서, 이 자리에서 `cargo build`로 100% 링크까지 확인은 못 했습니다. 대신 `ort` 2.0.0-rc.12 크레이트 소스를 직접 읽어서 여기서 쓴 API(`Session::builder`, `Tensor::from_array`, `session.run`, `try_extract_tensor` 등)들의 실제 시그니처를 하나하나 대조했고, 그 과정에서 `session`에 `mut`이 빠진 실수 하나를 발견해서 고쳤습니다. 일반 네트워크 환경(사용자 PC)에서는 `cargo build`가 모델 바이너리를 정상적으로 받아와서 그대로 빌드될 것으로 예상하지만, 실제 파일로 최종 실행 검증은 못 했다는 점은 알려드립니다.

## 아직 안 정한 것

- 알파 마스크 경계를 더 깨끗하게 다듬는 후처리(예: 임계값 이진화, 가장자리 블러 제거) — 로고처럼 딱 떨어지는 형태가 필요하면 추가하는 게 좋을 수 있음
- 진행률 콜백 (모델 다운로드/추론 진행 상황을 UI에 표시하고 싶을 때)
