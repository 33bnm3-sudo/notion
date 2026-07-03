use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine;
use hmac::{Hmac, Mac};
use serde_json::Value;
use sha1::Sha1;

type HmacSha1 = Hmac<Sha1>;

#[derive(Debug, Clone, Default)]
pub struct IdConfig {
    pub audd_token: Option<String>,
    pub acrcloud: Option<AcrCloudConfig>,
    pub acoustid_api_key: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AcrCloudConfig {
    pub host: String, // 예: "identify-eu-west-1.acrcloud.com"
    pub access_key: String,
    pub access_secret: String,
}

#[derive(Debug, Clone)]
pub struct SongMatch {
    pub title: String,
    pub artist: String,
    pub score: Option<f32>,
}

#[derive(Debug)]
pub struct ProviderResult {
    pub provider: &'static str,
    pub result: Result<Option<SongMatch>, String>,
}

/// 영상에서 오디오만 뽑아낸다. 인식 API는 몇 초 분량이면 충분해서 앞부분
/// `max_seconds`초만 잘라 업로드 용량/시간을 줄인다.
pub fn extract_audio(video_path: &Path, output_path: &Path, max_seconds: u32) -> Result<(), String> {
    let status = Command::new("ffmpeg")
        .args([
            "-y",
            "-i", video_path.to_str().ok_or("경로에 잘못된 문자가 있습니다")?,
            "-t", &max_seconds.to_string(),
            "-vn",
            "-acodec", "libmp3lame",
            "-ar", "44100",
            "-ac", "2",
            output_path.to_str().ok_or("경로에 잘못된 문자가 있습니다")?,
        ])
        .status()
        .map_err(|e| format!("ffmpeg 실행 실패: {e}"))?;

    if !status.success() {
        return Err("ffmpeg 오디오 추출 실패".to_string());
    }
    Ok(())
}

/// `IdConfig`에 키가 설정된 서비스들만 전부 돌려서 결과를 모은다. 서비스마다
/// 인식 데이터베이스 커버리지가 달라서(특히 쇼츠/릴스에서 흔한 속도조절·리믹스
/// 트렌드 사운드), 하나만 쓰기보다 여러 개를 같이 돌리는 쪽이 성공률이 높다.
/// 한 서비스가 실패해도 나머지 결과는 그대로 반환한다.
pub fn identify_song_all(audio_path: &Path, config: &IdConfig) -> Vec<ProviderResult> {
    let mut results = Vec::new();

    if let Some(token) = &config.audd_token {
        results.push(ProviderResult {
            provider: "AudD",
            result: identify_with_audd(audio_path, token),
        });
    }

    if let Some(acr) = &config.acrcloud {
        results.push(ProviderResult {
            provider: "ACRCloud",
            result: identify_with_acrcloud(audio_path, acr),
        });
    }

    if let Some(key) = &config.acoustid_api_key {
        results.push(ProviderResult {
            provider: "AcoustID",
            result: identify_with_acoustid(audio_path, key),
        });
    }

    results
}

fn build_multipart(
    fields: &[(&str, &str)],
    file_field: &str,
    file_name: &str,
    file_bytes: &[u8],
) -> (String, Vec<u8>) {
    let boundary = format!(
        "----songid{}",
        SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()
    );
    let mut body = Vec::new();

    for (name, value) in fields {
        body.extend_from_slice(
            format!("--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n")
                .as_bytes(),
        );
    }

    body.extend_from_slice(
        format!(
            "--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{file_name}\"\r\nContent-Type: application/octet-stream\r\n\r\n"
        )
        .as_bytes(),
    );
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());

    (boundary, body)
}

/// https://docs.audd.io/ — 무료 티어 지원, 상업 트렌드 음원 커버리지가 좋다.
fn identify_with_audd(audio_path: &Path, token: &str) -> Result<Option<SongMatch>, String> {
    let bytes = fs::read(audio_path).map_err(|e| format!("오디오 파일 읽기 실패: {e}"))?;
    let file_name = audio_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("audio.mp3");

    let (boundary, body) = build_multipart(
        &[("api_token", token), ("return", "spotify,apple_music")],
        "file",
        file_name,
        &bytes,
    );

    let mut response = ureq::post("https://api.audd.io/")
        .content_type(format!("multipart/form-data; boundary={boundary}"))
        .config()
        .http_status_as_error(false)
        .build()
        .send(&body[..])
        .map_err(|e| format!("AudD 요청 실패: {e}"))?;

    let parsed: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("AudD 응답 파싱 실패: {e}"))?;

    let result = &parsed["result"];
    if result.is_null() {
        return Ok(None);
    }

    Ok(Some(SongMatch {
        title: result["title"].as_str().unwrap_or_default().to_string(),
        artist: result["artist"].as_str().unwrap_or_default().to_string(),
        score: None,
    }))
}

/// https://docs.acrcloud.com/reference/identification-api — 요청마다 HMAC-SHA1
/// 서명이 필요하다. 무료 체험 크레딧 제공, 이후 사용량 기반 유료.
fn identify_with_acrcloud(audio_path: &Path, config: &AcrCloudConfig) -> Result<Option<SongMatch>, String> {
    let bytes = fs::read(audio_path).map_err(|e| format!("오디오 파일 읽기 실패: {e}"))?;
    let sample_bytes = bytes.len().to_string();
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_secs()
        .to_string();

    let string_to_sign = format!(
        "POST\n/v1/identify\n{}\naudio\n1\n{}",
        config.access_key, timestamp
    );

    let mut mac = HmacSha1::new_from_slice(config.access_secret.as_bytes())
        .map_err(|e| format!("서명 생성 실패: {e}"))?;
    mac.update(string_to_sign.as_bytes());
    let signature = base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes());

    let (boundary, body) = build_multipart(
        &[
            ("access_key", &config.access_key),
            ("data_type", "audio"),
            ("signature_version", "1"),
            ("signature", &signature),
            ("sample_bytes", &sample_bytes),
            ("timestamp", &timestamp),
        ],
        "sample",
        "sample.mp3",
        &bytes,
    );

    let url = format!("https://{}/v1/identify", config.host);
    let mut response = ureq::post(&url)
        .content_type(format!("multipart/form-data; boundary={boundary}"))
        .config()
        .http_status_as_error(false)
        .build()
        .send(&body[..])
        .map_err(|e| format!("ACRCloud 요청 실패: {e}"))?;

    let parsed: Value = response
        .body_mut()
        .read_json()
        .map_err(|e| format!("ACRCloud 응답 파싱 실패: {e}"))?;

    let music = &parsed["metadata"]["music"][0];
    if music.is_null() {
        return Ok(None);
    }

    Ok(Some(SongMatch {
        title: music["title"].as_str().unwrap_or_default().to_string(),
        artist: music["artists"][0]["name"].as_str().unwrap_or_default().to_string(),
        score: music["score"].as_f64().map(|s| s as f32),
    }))
}

/// https://acoustid.org/webservice — 완전 무료(가입만 하면 됨). 로컬에 Chromaprint의
/// `fpcalc` 실행 파일이 PATH에 있어야 한다. 정식 발매 음원 위주라 쇼츠/릴스용으로
/// 속도조절·리믹스된 트렌드 사운드는 인식이 안 될 수 있다 (AudD/ACRCloud로 보완).
fn identify_with_acoustid(audio_path: &Path, api_key: &str) -> Result<Option<SongMatch>, String> {
    let output = Command::new("fpcalc")
        .args(["-json", audio_path.to_str().ok_or("경로에 잘못된 문자가 있습니다")?])
        .output()
        .map_err(|e| format!("fpcalc 실행 실패 (Chromaprint 설치 필요): {e}"))?;

    if !output.status.success() {
        return Err("fpcalc 지문 추출 실패".to_string());
    }

    let fp_json: Value = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("fpcalc 출력 파싱 실패: {e}"))?;
    let duration = fp_json["duration"].as_f64().ok_or("fpcalc 출력에 duration 없음")?;
    let fingerprint = fp_json["fingerprint"]
        .as_str()
        .ok_or("fpcalc 출력에 fingerprint 없음")?;

    let url = format!(
        "https://api.acoustid.org/v2/lookup?client={}&meta=recordings&duration={}&fingerprint={}",
        urlencoding::encode(api_key),
        duration as u32,
        urlencoding::encode(fingerprint)
    );

    let parsed: Value = ureq::get(&url)
        .call()
        .map_err(|e| format!("AcoustID 요청 실패: {e}"))?
        .body_mut()
        .read_json()
        .map_err(|e| format!("AcoustID 응답 파싱 실패: {e}"))?;

    let result = &parsed["results"][0];
    let recording = &result["recordings"][0];
    if recording.is_null() {
        return Ok(None);
    }

    Ok(Some(SongMatch {
        title: recording["title"].as_str().unwrap_or_default().to_string(),
        artist: recording["artists"][0]["name"].as_str().unwrap_or_default().to_string(),
        score: result["score"].as_f64().map(|s| s as f32),
    }))
}

/// API 키 없이 항상 되는 기본값 — 유튜브 검색 결과 페이지 링크.
pub fn youtube_search_url(title: &str, artist: &str) -> String {
    let query = format!("{artist} {title}");
    format!(
        "https://www.youtube.com/results?search_query={}",
        urlencoding::encode(&query)
    )
}

/// YouTube Data API 키가 있으면 검색 결과의 첫 영상으로 바로 연결되는 링크를 만든다.
/// 무료 할당량(하루 10,000 유닛, 검색 1회 100유닛)이면 하루 100번 정도 가능하다.
pub fn youtube_top_result_url(title: &str, artist: &str, api_key: &str) -> Result<Option<String>, String> {
    let query = format!("{artist} {title}");
    let url = format!(
        "https://www.googleapis.com/youtube/v3/search?part=id&type=video&maxResults=1&q={}&key={}",
        urlencoding::encode(&query),
        urlencoding::encode(api_key)
    );

    let parsed: Value = ureq::get(&url)
        .call()
        .map_err(|e| format!("YouTube 검색 요청 실패: {e}"))?
        .body_mut()
        .read_json()
        .map_err(|e| format!("YouTube 응답 파싱 실패: {e}"))?;

    let video_id = parsed["items"][0]["id"]["videoId"].as_str();
    Ok(video_id.map(|id| format!("https://www.youtube.com/watch?v={id}")))
}
