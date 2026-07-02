# 로고 PNG → SVG 벡터화 (백엔드 로직)

배경이 이미 투명한 로고 PNG(예: `logo-bg-remover` 결과물)를 색상 벡터 SVG로 변환하는 핵심 로직입니다. 단독 프로그램이 아니라 나중에 Tauri 앱에 붙여 넣을 Rust 모듈(`src/lib.rs`)이고, `logo-bg-remover`와는 직접 코드로 엮지 않은 독립 모듈입니다.

## 왜 vtracer인가

Inkscape의 Trace Bitmap이 쓰는 **potrace**는 흑백 비트맵만 다룰 수 있어서, 컬러 로고는 색상별로 나눠 여러 번 돌려야 합니다. **vtracer**는:

- 순수 Rust 라이브러리라 Tauri에 바로 링크해서 쓸 수 있음 (외부 프로그램 설치/호출 불필요)
- 컬러 이미지를 색상별로 자동 클러스터링해서 한 번에 처리 (potrace의 상위호환)
- **투명 배경을 자동으로 감지해서 트레이싱에서 제외**함 — 배경이 지워진 PNG를 그냥 넣으면 알파가 0인 영역은 자동으로 빠지고, 남은 색상 영역들만 경계선을 따라 벡터화됨. 흑백 이진화 같은 전처리가 따로 필요 없음
- 기본 모드가 곡선(Spline, 베지어) 트레이싱이라 각진 다각형이 아니라 부드러운 곡선으로 나옴 — 3D 프로그램에 가져가서 쓰기 좋음

- [vtracer GitHub](https://github.com/visioncortex/vtracer)
- [Potrace vs VTracer 비교](https://www.aisvg.app/blog/image-to-svg-converter-guide)

## 검증

실제로 빨간 원 + 파란 사각형을 투명 배경 PNG로 만들어서 돌려봤습니다. 결과:
- 투명 영역은 SVG에 아예 안 나타남 (도형 2개만 출력됨)
- 색상 정확히 보존 (`#DC1E1E`, `#145AC8`)
- 모든 경로가 `C`(3차 베지어) 명령으로만 구성됨 — `<polygon>`/`<polyline>` 없음

## 사용 예

```rust
let opts = logo_to_svg::SvgOptions::default();
logo_to_svg::convert_to_svg(
    Path::new("logo-transparent.png"),
    Path::new("logo.svg"),
    &opts,
)?;
```

## 옵션 (`SvgOptions`)

| 필드 | 설명 | 기본값 |
|---|---|---|
| `color_precision` | 색상을 몇 단계로 단순화할지 (1~8). 낮을수록 색상 수가 줄고 도형이 단순해짐 | `6` |
| `filter_speckle` | 이 픽셀 넓이보다 작은 잡티는 무시 | `4` |
| `corner_threshold` | 이 각도(도)보다 뾰족한 지점만 코너로 취급, 나머지는 곡선으로 이어붙임 | `60` |

## Tauri 앱에 합칠 때

```rust
#[tauri::command]
async fn convert_logo_to_svg(input: String, output: String) -> Result<(), String> {
    let opts = logo_to_svg::SvgOptions::default();
    logo_to_svg::convert_to_svg(
        std::path::Path::new(&input),
        std::path::Path::new(&output),
        &opts,
    )
}
```

`logo-bg-remover`의 출력(투명 PNG)을 그대로 이 함수의 입력으로 넘기면 두 모듈이 파이프라인처럼 이어집니다 (코드 의존성은 없고, 파일만 주고받는 구조).
