use std::fs;
use std::path::Path;

use base64::Engine;
use serde_json::{json, Value};

const API_BASE: &str = "https://generativelanguage.googleapis.com/v1beta/models";

#[derive(Debug, Clone)]
pub struct ImageOptions {
    /// 사용할 모델. Imagen은 2026-08-17 서비스 종료 예정이라 Nano Banana 계열을 기본으로 둔다.
    pub model: String,
    /// "1:1", "16:9", "9:16" 등.
    pub aspect_ratio: String,
    /// "1K", "2K", "4K".
    pub image_size: String,
}

impl Default for ImageOptions {
    fn default() -> Self {
        Self {
            model: "gemini-3.1-flash-image".to_string(),
            aspect_ratio: "1:1".to_string(),
            image_size: "2K".to_string(),
        }
    }
}

/// 프롬프트로 이미지를 생성해서 파일로 저장한다. 프롬프트 내용/의도는 호출하는 쪽 책임이다.
/// `reference_images`가 비어있지 않으면 텍스트 프롬프트 앞에 함께 실어 보내서, 웹 UI에서
/// "이 이미지 참고해서/이걸 수정해서 만들어줘" 하는 것과 같은 이미지 편집/참조 생성을 할 수 있다.
pub fn generate_image(
    api_key: &str,
    prompt: &str,
    reference_images: &[&Path],
    options: &ImageOptions,
    output_path: &Path,
) -> Result<(), String> {
    let url = format!("{API_BASE}/{}:generateContent", options.model);

    let mut parts = Vec::with_capacity(reference_images.len() + 1);
    for image_path in reference_images {
        let bytes = fs::read(image_path)
            .map_err(|e| format!("참고 이미지 읽기 실패({}): {e}", image_path.display()))?;
        let mime_type = guess_mime_type(image_path)?;
        let encoded = base64::engine::general_purpose::STANDARD.encode(&bytes);
        parts.push(json!({ "inlineData": { "mimeType": mime_type, "data": encoded } }));
    }
    parts.push(json!({ "text": prompt }));

    let body = json!({
        "contents": [{ "parts": parts }],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {
                "aspectRatio": options.aspect_ratio,
                "imageSize": options.image_size
            }
        }
    });

    let mut response = ureq::post(&url)
        .header("x-goog-api-key", api_key)
        .config()
        .http_status_as_error(false)
        .build()
        .send_json(&body)
        .map_err(|e| format!("Gemini API 요청 실패: {e}"))?;

    let status = response.status().as_u16();
    let parsed: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("응답 JSON 파싱 실패: {e}"))?;

    let image_bytes = extract_image_bytes(status, &parsed)?;
    fs::write(output_path, image_bytes).map_err(|e| format!("이미지 저장 실패: {e}"))?;

    Ok(())
}

fn guess_mime_type(path: &Path) -> Result<&'static str, String> {
    match path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_lowercase())
        .as_deref()
    {
        Some("png") => Ok("image/png"),
        Some("jpg") | Some("jpeg") => Ok("image/jpeg"),
        Some("webp") => Ok("image/webp"),
        _ => Err(format!(
            "지원하지 않는 참고 이미지 확장자: {}",
            path.display()
        )),
    }
}

/// generateContent 응답 JSON에서 이미지 바이트를 뽑아낸다. HTTP 상태와 파싱된 바디를 받아
/// API 에러/안전필터 차단/이미지 누락을 각각 구분해서 에러 메시지를 낸다.
fn extract_image_bytes(status: u16, parsed: &Value) -> Result<Vec<u8>, String> {
    if status != 200 {
        let message = parsed
            .get("error")
            .and_then(|e| e.get("message"))
            .and_then(|m| m.as_str())
            .unwrap_or("(상세 메시지 없음)");
        return Err(format!("Gemini API 오류 (HTTP {status}): {message}"));
    }

    if let Some(block_reason) = parsed
        .get("promptFeedback")
        .and_then(|f| f.get("blockReason"))
        .and_then(|r| r.as_str())
    {
        return Err(format!("프롬프트가 안전 필터에 막혔습니다: {block_reason}"));
    }

    let image_data_base64 = parsed
        .get("candidates")
        .and_then(|c| c.get(0))
        .and_then(|c| c.get("content"))
        .and_then(|c| c.get("parts"))
        .and_then(|parts| parts.as_array())
        .and_then(|parts| {
            parts
                .iter()
                .find_map(|p| p.get("inlineData").and_then(|d| d.get("data")))
        })
        .and_then(|d| d.as_str());

    let image_data_base64 = match image_data_base64 {
        Some(data) => data,
        None => {
            let finish_reason = parsed
                .get("candidates")
                .and_then(|c| c.get(0))
                .and_then(|c| c.get("finishReason"))
                .and_then(|r| r.as_str())
                .unwrap_or("알 수 없음");
            return Err(format!(
                "응답에 이미지 데이터가 없습니다 (finishReason: {finish_reason})"
            ));
        }
    };

    base64::engine::general_purpose::STANDARD
        .decode(image_data_base64)
        .map_err(|e| format!("이미지 base64 디코딩 실패: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_image_bytes_from_valid_response() {
        let png_bytes = vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        let encoded = base64::engine::general_purpose::STANDARD.encode(&png_bytes);
        let response = json!({
            "candidates": [{
                "content": {
                    "parts": [
                        { "text": "Here is the logo." },
                        { "inlineData": { "mimeType": "image/png", "data": encoded } }
                    ]
                },
                "finishReason": "STOP"
            }]
        });

        let result = extract_image_bytes(200, &response).unwrap();
        assert_eq!(result, png_bytes);
    }

    #[test]
    fn reports_http_error_with_message() {
        let response = json!({
            "error": { "code": 429, "message": "Resource exhausted", "status": "RESOURCE_EXHAUSTED" }
        });

        let err = extract_image_bytes(429, &response).unwrap_err();
        assert!(err.contains("429"));
        assert!(err.contains("Resource exhausted"));
    }

    #[test]
    fn reports_safety_block_reason() {
        let response = json!({
            "promptFeedback": { "blockReason": "SAFETY" },
            "candidates": []
        });

        let err = extract_image_bytes(200, &response).unwrap_err();
        assert!(err.contains("SAFETY"));
    }

    #[test]
    fn reports_missing_image_with_finish_reason() {
        let response = json!({
            "candidates": [{
                "content": { "parts": [{ "text": "I can't generate that." }] },
                "finishReason": "PROHIBITED_CONTENT"
            }]
        });

        let err = extract_image_bytes(200, &response).unwrap_err();
        assert!(err.contains("PROHIBITED_CONTENT"));
    }

    #[test]
    fn guesses_mime_type_from_extension() {
        assert_eq!(guess_mime_type(Path::new("logo.PNG")).unwrap(), "image/png");
        assert_eq!(guess_mime_type(Path::new("shirt.jpg")).unwrap(), "image/jpeg");
        assert_eq!(guess_mime_type(Path::new("shirt.jpeg")).unwrap(), "image/jpeg");
        assert_eq!(guess_mime_type(Path::new("photo.webp")).unwrap(), "image/webp");
        assert!(guess_mime_type(Path::new("scan.tiff")).is_err());
    }
}
