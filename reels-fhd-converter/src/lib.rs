use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Orientation {
    Vertical,   // 1080x1920 — 릴스/쇼츠 기본값
    Horizontal, // 1920x1080
}

impl Orientation {
    fn target_size(self) -> (u32, u32) {
        match self {
            Orientation::Vertical => (1080, 1920),
            Orientation::Horizontal => (1920, 1080),
        }
    }

    /// 원본 해상도를 보고 세로/가로를 자동으로 판단한다. 정사각형이면 세로(릴스 기본) 취급.
    fn from_resolution(width: u32, height: u32) -> Self {
        if width > height {
            Orientation::Horizontal
        } else {
            Orientation::Vertical
        }
    }
}

#[derive(Debug, Clone)]
pub struct ConvertOptions {
    /// x265 CRF. 낮을수록 고화질/큰 용량. 18~28 권장 범위.
    pub crf: u8,
    /// x265 preset. 압축 효율 우선이면 "slow"~"veryslow" (인코딩 시간은 늘어남).
    pub preset: String,
}

impl Default for ConvertOptions {
    fn default() -> Self {
        Self {
            crf: 26,
            preset: "slow".to_string(),
        }
    }
}

pub fn probe_resolution(input: &Path) -> Result<(u32, u32), String> {
    let output = Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=s=x:p=0",
        ])
        .arg(input)
        .output()
        .map_err(|e| format!("ffprobe 실행 실패: {e}"))?;

    if !output.status.success() {
        return Err(format!(
            "ffprobe 오류: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let (w, h) = text
        .trim()
        .split_once('x')
        .ok_or_else(|| format!("해상도 파싱 실패: {text}"))?;

    let width: u32 = w.parse().map_err(|_| "너비 파싱 실패".to_string())?;
    let height: u32 = h.parse().map_err(|_| "높이 파싱 실패".to_string())?;
    Ok((width, height))
}

/// 4K(또는 그 이상) 원본을 FHD로 다운스케일하면서 화질을 개선한다.
/// 처리 순서: 디노이즈 → Lanczos 강제 스트레치 리사이즈 → 언샵.
/// 목표 해상도(세로/가로)는 원본의 종횡비를 보고 자동으로 정한다.
/// 원본이 목표 해상도보다 작으면 업스케일을 방지하기 위해 에러를 반환한다.
pub fn convert_to_fhd(
    input: &Path,
    output: &Path,
    opts: &ConvertOptions,
) -> Result<(), String> {
    let (src_w, src_h) = probe_resolution(input)?;
    let (target_w, target_h) = Orientation::from_resolution(src_w, src_h).target_size();

    if src_w < target_w || src_h < target_h {
        return Err(format!(
            "원본 해상도({src_w}x{src_h})가 목표({target_w}x{target_h})보다 작아 업스케일이 필요합니다. 지원하지 않는 작업입니다."
        ));
    }

    let vf = format!(
        "hqdn3d=4:3:6:4.5,scale={target_w}:{target_h}:flags=lanczos,unsharp=5:5:0.8:5:5:0.0"
    );

    let status = Command::new("ffmpeg")
        .arg("-y")
        .arg("-i")
        .arg(input)
        .args(["-vf", &vf])
        .args(["-c:v", "libx265"])
        .args(["-crf", &opts.crf.to_string()])
        .args(["-preset", &opts.preset])
        .args(["-tag:v", "hvc1"]) // Instagram/QuickTime 호환용 태그
        .args(["-c:a", "copy"])
        .arg(output)
        .status()
        .map_err(|e| format!("ffmpeg 실행 실패: {e}"))?;

    if !status.success() {
        return Err(format!("ffmpeg 종료 코드 오류: {status}"));
    }

    Ok(())
}
