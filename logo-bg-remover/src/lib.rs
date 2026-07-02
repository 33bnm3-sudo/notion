use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use image::{imageops::FilterType, GenericImageView, ImageBuffer, Rgba};
use ort::session::builder::GraphOptimizationLevel;
use ort::session::Session;
use ort::value::Tensor;

const MODEL_URL: &str =
    "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx";
const MODEL_INPUT_SIZE: u32 = 1024;

/// 모델 파일이 저장/조회될 로컬 캐시 경로.
pub fn model_cache_path() -> Result<PathBuf, String> {
    let cache_dir = dirs::cache_dir()
        .ok_or("캐시 디렉토리를 찾을 수 없습니다")?
        .join("logo-bg-remover");
    fs::create_dir_all(&cache_dir).map_err(|e| format!("캐시 디렉토리 생성 실패: {e}"))?;
    Ok(cache_dir.join("isnet-general-use.onnx"))
}

/// 모델이 로컬에 없으면 다운로드한다. 이미 있으면 아무것도 하지 않는다.
pub fn ensure_model_downloaded() -> Result<PathBuf, String> {
    let path = model_cache_path()?;
    if path.exists() {
        return Ok(path);
    }

    let response = ureq::get(MODEL_URL)
        .call()
        .map_err(|e| format!("모델 다운로드 요청 실패: {e}"))?;

    let tmp_path = path.with_extension("onnx.part");
    let mut file =
        fs::File::create(&tmp_path).map_err(|e| format!("임시 파일 생성 실패: {e}"))?;
    std::io::copy(&mut response.into_body().into_reader(), &mut file)
        .map_err(|e| format!("모델 저장 실패: {e}"))?;
    file.flush().map_err(|e| format!("모델 저장 실패: {e}"))?;
    fs::rename(&tmp_path, &path).map_err(|e| format!("모델 파일 이동 실패: {e}"))?;

    Ok(path)
}

/// 이미지 배경을 제거해서 알파 채널이 있는 PNG로 저장한다.
/// 깔끔한 단색 배경이든 복잡한 배경이든 동일한 세그멘테이션 모델로 처리한다.
pub fn remove_background(model_path: &Path, input: &Path, output: &Path) -> Result<(), String> {
    let mut session = Session::builder()
        .map_err(|e| format!("ONNX 세션 빌더 생성 실패: {e}"))?
        .with_optimization_level(GraphOptimizationLevel::Level3)
        .map_err(|e| format!("최적화 레벨 설정 실패: {e}"))?
        .commit_from_file(model_path)
        .map_err(|e| format!("모델 로드 실패: {e}"))?;

    let original = image::open(input).map_err(|e| format!("이미지 로드 실패: {e}"))?;
    let (orig_w, orig_h) = original.dimensions();

    let resized = original.resize_exact(
        MODEL_INPUT_SIZE,
        MODEL_INPUT_SIZE,
        FilterType::Triangle,
    );

    // isnet 전처리: RGB, 0~1 정규화 후 평균 0.5 / 표준편차 1.0 기준으로 이동, CHW 배치
    let mut input_data = vec![0f32; (3 * MODEL_INPUT_SIZE * MODEL_INPUT_SIZE) as usize];
    let plane = (MODEL_INPUT_SIZE * MODEL_INPUT_SIZE) as usize;
    for (x, y, pixel) in resized.to_rgb8().enumerate_pixels() {
        let idx = (y * MODEL_INPUT_SIZE + x) as usize;
        for c in 0..3 {
            input_data[c * plane + idx] = (pixel[c] as f32 / 255.0 - 0.5) / 1.0;
        }
    }

    let input_tensor = Tensor::from_array((
        [1usize, 3, MODEL_INPUT_SIZE as usize, MODEL_INPUT_SIZE as usize],
        input_data,
    ))
    .map_err(|e| format!("입력 텐서 생성 실패: {e}"))?;

    let outputs = session
        .run(ort::inputs![input_tensor])
        .map_err(|e| format!("추론 실행 실패: {e}"))?;

    let (mask_shape, mask_data) = outputs[0]
        .try_extract_tensor::<f32>()
        .map_err(|e| format!("출력 텐서 추출 실패: {e}"))?;

    let mask_h = mask_shape[2] as u32;
    let mask_w = mask_shape[3] as u32;

    let mut min_v = f32::MAX;
    let mut max_v = f32::MIN;
    for &v in mask_data {
        min_v = min_v.min(v);
        max_v = max_v.max(v);
    }
    let range = (max_v - min_v).max(1e-6);

    let mask_image = ImageBuffer::from_fn(mask_w, mask_h, |x, y| {
        let v = mask_data[(y * mask_w + x) as usize];
        let normalized = ((v - min_v) / range * 255.0).clamp(0.0, 255.0) as u8;
        image::Luma([normalized])
    });

    let mask_resized = image::DynamicImage::ImageLuma8(mask_image).resize_exact(
        orig_w,
        orig_h,
        FilterType::Triangle,
    );
    let mask_resized = mask_resized.to_luma8();

    let rgba_original = original.to_rgba8();
    let mut out_image = ImageBuffer::<Rgba<u8>, Vec<u8>>::new(orig_w, orig_h);
    for (x, y, pixel) in out_image.enumerate_pixels_mut() {
        let src = rgba_original.get_pixel(x, y);
        let alpha = mask_resized.get_pixel(x, y)[0];
        *pixel = Rgba([src[0], src[1], src[2], alpha]);
    }

    out_image
        .save(output)
        .map_err(|e| format!("결과 저장 실패: {e}"))?;

    Ok(())
}
