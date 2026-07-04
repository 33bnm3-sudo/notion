use std::path::Path;

use vtracer::{Config, Hierarchical};
use visioncortex::PathSimplifyMode;

pub use vtracer::ColorMode;

#[derive(Debug, Clone)]
pub struct SvgOptions {
    /// 색상을 몇 단계로 단순화할지 (1~8). 낮을수록 색상 수가 줄고 도형이 단순해짐.
    pub color_precision: i32,
    /// 이보다 작은 픽셀 넓이의 잡티(스펙클)는 무시.
    pub filter_speckle: usize,
    /// 이 각도(도)보다 뾰족한 지점만 코너로 취급하고, 나머지는 곡선으로 이어붙임.
    pub corner_threshold: i32,
}

impl Default for SvgOptions {
    fn default() -> Self {
        Self {
            color_precision: 6,
            filter_speckle: 4,
            corner_threshold: 60,
        }
    }
}

/// 배경이 이미 투명한 로고 PNG를 색상 벡터 SVG로 변환한다.
/// 투명 영역은 자동으로 감지되어 트레이싱에서 제외되고, 곡선(Spline) 경로로 출력되므로
/// 3D 프로그램에서 다각형(폴리곤)이 아닌 부드러운 형태로 바로 쓸 수 있다.
pub fn convert_to_svg(input: &Path, output: &Path, opts: &SvgOptions) -> Result<(), String> {
    let config = Config {
        color_mode: ColorMode::Color,
        hierarchical: Hierarchical::Stacked,
        mode: PathSimplifyMode::Spline,
        filter_speckle: opts.filter_speckle,
        color_precision: opts.color_precision,
        layer_difference: 16,
        corner_threshold: opts.corner_threshold,
        length_threshold: 4.0,
        splice_threshold: 45,
        max_iterations: 10,
        path_precision: Some(2),
    };

    vtracer::convert_image_to_svg(input, output, config)
}
