# Gemini 이미지 생성기 (백엔드 로직)

프롬프트로 이미지를 생성해서 파일로 저장하는 핵심 로직입니다. 단독 프로그램이 아니라 나중에 Tauri 앱에 붙여 넣을 Rust 모듈(`src/lib.rs`)입니다. 프롬프트를 어떻게 만들지는 호출하는 쪽(사용자 입력) 책임이고, 이 모듈은 "프롬프트 → 이미지 파일" 한 단계만 합니다.

예: 릴스에서 본 티셔츠 로고가 마음에 들어서 "그 로고만 분리해서, 검정 실루엣, 배경 없이 그려줘" 같은 프롬프트로 이미지를 만들고 → `logo-bg-remover`로 배경 제거 → `logo-to-svg`로 벡터화 → 3D 모델링. 이 모듈은 그 파이프라인의 첫 단계입니다.

## 왜 Nano Banana(Gemini API)인가

Imagen 모델은 2026년 8월 17일에 서비스 종료 예정이라, 구글이 권장하는 최신 이미지 생성 모델인 **Nano Banana**(`gemini-3.1-flash-image`)를 기본으로 씁니다. 기존 Gemini API의 `generateContent` 엔드포인트를 그대로 쓰고, `responseModalities: ["TEXT", "IMAGE"]`와 `imageConfig`(종횡비/해상도)만 추가하는 방식입니다.

- [Nano Banana 이미지 생성 문서](https://ai.google.dev/gemini-api/docs/image-generation)
- [Gemini API 레퍼런스](https://ai.google.dev/api)

## 검증 관련 참고

이 샌드박스에는 실제 Gemini API 키가 없어서 진짜 API 호출까지는 못 해봤습니다. 대신 공식 문서에 나온 응답 스키마(`candidates[].content.parts[].inlineData.data`, `promptFeedback.blockReason`, `error.message` 등)를 그대로 흉내 낸 가짜 JSON으로 파싱 로직만 단위 테스트했고 (`cargo test`, 4개 통과), HTTP 통신 부분은 컴파일 확인만 했습니다. 실제 키로 한 번 테스트해보시는 걸 권장합니다.

## 사용 예

```rust
let opts = gemini_image_generator::ImageOptions::default();
gemini_image_generator::generate_image(
    "YOUR_API_KEY",
    "검정 실루엣 로고, 배경 없음, 심플한 라인아트",
    &opts,
    Path::new("generated-logo.png"),
)?;
```

## 옵션 (`ImageOptions`)

| 필드 | 설명 | 기본값 |
|---|---|---|
| `model` | 사용할 모델 | `"gemini-3.1-flash-image"` |
| `aspect_ratio` | `"1:1"`, `"16:9"`, `"9:16"` 등 | `"1:1"` |
| `image_size` | `"1K"`, `"2K"`, `"4K"` | `"2K"` |

## API 키

이 모듈은 API 키를 저장하지 않습니다. 호출할 때 문자열로 그대로 받아서 요청 헤더(`x-goog-api-key`)에 넣기만 합니다. 키 보관/입력은 Tauri 앱 쪽(설정 화면, OS 보안 저장소 등)에서 책임집니다.

## 에러 처리

재시도 로직은 없습니다. rate limit(429), 안전 필터 차단, 이미지 누락을 각각 구분한 에러 메시지를 그대로 반환하니, 재시도가 필요하면 호출하는 쪽(Tauri UI)에서 판단해서 처리하면 됩니다.

## Tauri 앱에 합칠 때

```rust
#[tauri::command]
async fn generate_logo_image(api_key: String, prompt: String, output: String) -> Result<(), String> {
    let opts = gemini_image_generator::ImageOptions::default();
    gemini_image_generator::generate_image(&api_key, &prompt, &opts, std::path::Path::new(&output))
}
```

이 모듈이 만든 PNG를 `logo-bg-remover` 입력으로, 그 출력을 다시 `logo-to-svg` 입력으로 넘기면 세 모듈이 파일로만 이어지는 파이프라인이 됩니다 (코드 의존성 없음).
