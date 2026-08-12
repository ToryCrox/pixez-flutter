use std::{
    collections::HashSet,
    fs,
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
};

use anyhow::{Context, Result, anyhow, bail};
use image::{DynamicImage, GenericImageView, ImageBuffer, Rgb, imageops::FilterType};
use ort::{
    inputs,
    session::{Session, builder::GraphOptimizationLevel},
    value::TensorRef,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

const PROTOCOL_VERSION: u32 = 1;
const CTD_INPUT: u32 = 1024;
const BABERU_INPUT: u32 = 224;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Request {
    protocol_version: u32,
    request_id: String,
    #[serde(alias = "command")]
    method: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
struct NormalizedRect {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
}

impl NormalizedRect {
    fn width(self) -> f32 {
        (self.right - self.left).max(0.0)
    }
    fn height(self) -> f32 {
        (self.bottom - self.top).max(0.0)
    }
    fn area(self) -> f32 {
        self.width() * self.height()
    }
    fn clamp(self) -> Self {
        Self {
            left: self.left.clamp(0.0, 1.0),
            top: self.top.clamp(0.0, 1.0),
            right: self.right.clamp(0.0, 1.0),
            bottom: self.bottom.clamp(0.0, 1.0),
        }
    }
    fn inflate(self, fraction: f32) -> Self {
        let dx = self.width() * fraction;
        let dy = self.height() * fraction;
        Self {
            left: self.left - dx,
            top: self.top - dy,
            right: self.right + dx,
            bottom: self.bottom + dy,
        }
        .clamp()
    }
    fn iou(self, other: Self) -> f32 {
        let w = (self.right.min(other.right) - self.left.max(other.left)).max(0.0);
        let h = (self.bottom.min(other.bottom) - self.top.max(other.top)).max(0.0);
        let intersection = w * h;
        let union = self.area() + other.area() - intersection;
        if union <= 0.0 {
            0.0
        } else {
            intersection / union
        }
    }
    fn union(self, other: Self) -> Self {
        Self {
            left: self.left.min(other.left),
            top: self.top.min(other.top),
            right: self.right.max(other.right),
            bottom: self.bottom.max(other.bottom),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TextBlock {
    id: String,
    bounds: NormalizedRect,
    source_text: String,
    translated_text: String,
    language: String,
    direction: String,
    detection_confidence: f32,
    recognition_confidence: f32,
    order: usize,
    used_high_resolution_retry: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    warning: Option<String>,
}

struct LoadedModels {
    detector: Session,
    vision: Session,
    prefill: Session,
    step: Session,
    vocab: Vocab,
}

struct Vocab {
    id_to_char: Vec<String>,
    content_ids: HashSet<i64>,
}

impl Vocab {
    fn load(path: &Path) -> Result<Self> {
        let charset: Vec<String> = serde_json::from_slice(&fs::read(path)?)?;
        let mut id_to_char = vec![String::new(); 4];
        id_to_char.extend(charset);
        let content_ids = id_to_char
            .iter()
            .enumerate()
            .filter_map(|(id, value)| {
                let mut chars = value.chars();
                let ch = chars.next()?;
                if chars.next().is_none()
                    && ch.is_alphanumeric()
                    && !matches!(ch, 'ー' | 'ｰ' | '〜' | '~')
                {
                    Some(id as i64)
                } else {
                    None
                }
            })
            .collect();
        Ok(Self {
            id_to_char,
            content_ids,
        })
    }
    fn decode(&self, tokens: &[i64]) -> String {
        tokens
            .iter()
            .filter_map(|id| self.id_to_char.get(*id as usize))
            .cloned()
            .collect()
    }
}

#[derive(Clone)]
struct Tile {
    bounds: NormalizedRect,
    image: DynamicImage,
}

#[derive(Clone, Copy)]
struct TileSpec {
    bounds: NormalizedRect,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
}

#[derive(Clone, Copy)]
struct Detection {
    bounds: NormalizedRect,
    confidence: f32,
    class_id: usize,
}

fn main() -> Result<()> {
    let models: Arc<Mutex<Option<LoadedModels>>> = Arc::new(Mutex::new(None));
    let cancelled = Arc::new(AtomicBool::new(false));
    let current_request = Arc::new(Mutex::new(None::<String>));
    let stdout = Arc::new(Mutex::new(io::stdout()));

    for line in io::stdin().lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        let request: Request = match serde_json::from_str(&line) {
            Ok(value) => value,
            Err(error) => {
                emit(
                    &stdout,
                    json!({"protocolVersion": PROTOCOL_VERSION, "requestId": "", "ok": false, "error": format!("无效 JSON：{error}")}),
                );
                continue;
            }
        };
        if request.protocol_version != PROTOCOL_VERSION {
            emit_error(&stdout, &request.request_id, "协议版本不匹配");
            continue;
        }
        match request.method.as_str() {
            "capabilities" => emit_ok(
                &stdout,
                &request.request_id,
                json!({
                    "protocolVersion": PROTOCOL_VERSION,
                    "methods": ["capabilities", "loadModels", "analyzePage", "cancel", "shutdown"],
                    "detectors": ["ctd_onnx"],
                    "recognizers": ["baberu_ocr_int4"],
                    "maxConcurrentPages": 1
                }),
            ),
            "loadModels" => {
                let result = load_models(&request.payload);
                match result {
                    Ok(loaded) => {
                        *models.lock().unwrap() = Some(loaded);
                        emit_ok(&stdout, &request.request_id, json!({"loaded": true}));
                    }
                    Err(error) => emit_error(
                        &stdout,
                        &request.request_id,
                        &format!("加载模型失败：{error:#}"),
                    ),
                }
            }
            "analyzePage" => {
                if current_request.lock().unwrap().is_some() {
                    emit_error(&stdout, &request.request_id, "已有页面正在处理");
                    continue;
                }
                *current_request.lock().unwrap() = Some(request.request_id.clone());
                cancelled.store(false, Ordering::Relaxed);
                let models = Arc::clone(&models);
                let stdout = Arc::clone(&stdout);
                let cancelled = Arc::clone(&cancelled);
                let current_request = Arc::clone(&current_request);
                thread::spawn(move || {
                    let result = {
                        let mut guard = models.lock().unwrap();
                        match guard.as_mut() {
                            Some(models) => analyze_page(models, &request, &stdout, &cancelled),
                            None => Err(anyhow!("模型尚未加载")),
                        }
                    };
                    match result {
                        Ok(value) => emit_ok(&stdout, &request.request_id, value),
                        Err(error) => {
                            emit_error(&stdout, &request.request_id, &format!("{error:#}"))
                        }
                    }
                    *current_request.lock().unwrap() = None;
                });
            }
            "cancel" => {
                let target = request
                    .payload
                    .get("targetRequestId")
                    .and_then(Value::as_str)
                    .unwrap_or_default();
                if current_request.lock().unwrap().as_deref() == Some(target) || target.is_empty() {
                    cancelled.store(true, Ordering::Relaxed);
                }
                emit_ok(&stdout, &request.request_id, json!({"cancelled": true}));
            }
            "shutdown" => {
                cancelled.store(true, Ordering::Relaxed);
                emit_ok(&stdout, &request.request_id, json!({"shutdown": true}));
                break;
            }
            _ => emit_error(&stdout, &request.request_id, "不支持的命令"),
        }
    }
    Ok(())
}

fn load_models(payload: &Value) -> Result<LoadedModels> {
    let root = PathBuf::from(required_str(payload, "modelDirectory")?);
    let detector_id = payload
        .pointer("/detector/engineId")
        .and_then(Value::as_str)
        .unwrap_or("ctd_onnx");
    let recognizer_id = payload
        .pointer("/recognizer/engineId")
        .and_then(Value::as_str)
        .unwrap_or("baberu_ocr_int4");
    let detector_path = root.join(detector_id).join("comictextdetector.pt.onnx");
    let recognizer_dir = root.join(recognizer_id);
    let build = |path: &Path| -> Result<Session> {
        let builder = Session::builder().map_err(|error| anyhow!(error.to_string()))?;
        let mut builder = builder
            .with_optimization_level(GraphOptimizationLevel::Level3)
            .map_err(|error| anyhow!(error.to_string()))?;
        builder
            .commit_from_file(path)
            .map_err(|error| anyhow!("无法打开 {}：{}", path.display(), error))
    };
    Ok(LoadedModels {
        detector: build(&detector_path)?,
        vision: build(&recognizer_dir.join("vision_int4.onnx"))?,
        prefill: build(&recognizer_dir.join("decoder_prefill_int8.onnx"))?,
        step: build(&recognizer_dir.join("decoder_step_int8.onnx"))?,
        vocab: Vocab::load(&recognizer_dir.join("vocab.json"))?,
    })
}

fn analyze_page(
    models: &mut LoadedModels,
    request: &Request,
    stdout: &Arc<Mutex<io::Stdout>>,
    cancelled: &AtomicBool,
) -> Result<Value> {
    let image_path = PathBuf::from(required_str(&request.payload, "imagePath")?);
    progress(stdout, &request.request_id, "preparing", 0, 1, "解码图片");
    let original =
        image::open(&image_path).with_context(|| format!("无法读取 {}", image_path.display()))?;
    let (width, height) = original.dimensions();
    check_cancel(cancelled)?;
    let pre = request
        .payload
        .get("preprocessor")
        .cloned()
        .unwrap_or(Value::Null);
    let max_edge = pre
        .get("maxWorkingEdge")
        .and_then(Value::as_u64)
        .unwrap_or(2048) as u32;
    let long_ratio = pre
        .get("longPageAspectRatio")
        .and_then(Value::as_f64)
        .unwrap_or(3.0) as f32;
    let overlap = pre
        .get("tileOverlap")
        .and_then(Value::as_f64)
        .unwrap_or(0.10) as f32;
    let padding = pre
        .get("cropPadding")
        .and_then(Value::as_f64)
        .unwrap_or(0.12) as f32;
    let low_confidence = pre
        .get("lowConfidenceThreshold")
        .and_then(Value::as_f64)
        .unwrap_or(0.45) as f32;
    let duplicate_iou = pre
        .get("duplicateIouThreshold")
        .and_then(Value::as_f64)
        .unwrap_or(0.55) as f32;

    let tiles = make_tile_specs(width, height, max_edge, long_ratio, overlap);
    progress(
        stdout,
        &request.request_id,
        "tiling",
        tiles.len(),
        tiles.len(),
        if tiles.len() > 1 {
            "长图分块完成"
        } else {
            "工作图完成"
        },
    );
    let mut detections = Vec::new();
    for (index, tile_spec) in tiles.iter().enumerate() {
        check_cancel(cancelled)?;
        progress(
            stdout,
            &request.request_id,
            "detecting",
            index,
            tiles.len(),
            "检测文字区域",
        );
        // 一次只保留一个工作分块，检测完成后立即释放。
        let tile = materialize_tile(&original, *tile_spec, max_edge);
        detections.extend(detect_tile(&mut models.detector, &tile)?);
    }
    detections = merge_detections(detections, duplicate_iou);
    progress(
        stdout,
        &request.request_id,
        "detecting",
        detections.len(),
        detections.len(),
        "文字区域检测完成",
    );

    let mut blocks = Vec::new();
    for (index, detection) in detections.iter().enumerate() {
        check_cancel(cancelled)?;
        progress(
            stdout,
            &request.request_id,
            "recognizing",
            index,
            detections.len(),
            "识别文字",
        );
        let padded = detection.bounds.inflate(padding);
        let crop = crop_normalized(&original, padded);
        let (mut text, mut confidence) = recognize(
            &mut models.vision,
            &mut models.prefill,
            &mut models.step,
            &models.vocab,
            &crop,
            cancelled,
        )?;
        let mut retried = false;
        if text.trim().is_empty() || confidence < low_confidence {
            retried = true;
            // 重试仍只解码同一局部；上限由 224px 模型输入约束，避免保留多份高清裁剪。
            let retry_crop = crop_normalized(&original, padded.inflate(padding * 0.25));
            let retry = recognize(
                &mut models.vision,
                &mut models.prefill,
                &mut models.step,
                &models.vocab,
                &retry_crop,
                cancelled,
            )?;
            if retry.1 >= confidence {
                text = retry.0;
                confidence = retry.1;
            }
        }
        let direction = if detection.class_id == 0 {
            "horizontal"
        } else if detection.bounds.height() > detection.bounds.width() * 1.2 {
            "vertical"
        } else {
            "horizontal"
        };
        let language = detect_language(&text, detection.class_id);
        let id = block_id(&request.payload, detection.bounds);
        blocks.push(TextBlock {
            id,
            bounds: detection.bounds,
            source_text: text.clone(),
            translated_text: String::new(),
            language,
            direction: direction.to_owned(),
            detection_confidence: detection.confidence,
            recognition_confidence: confidence,
            order: index,
            used_high_resolution_retry: retried,
            warning: if text.trim().is_empty() || confidence < low_confidence {
                Some("识别失败/低置信度".to_owned())
            } else {
                None
            },
        });
    }
    progress(
        stdout,
        &request.request_id,
        "recognizing",
        blocks.len(),
        blocks.len(),
        "识别完成",
    );
    Ok(json!({
        "imageWidth": width,
        "imageHeight": height,
        "blocks": blocks,
        "peakMemoryBytes": peak_memory_bytes()
    }))
}

#[cfg(unix)]
fn peak_memory_bytes() -> u64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } != 0 {
        return 0;
    }
    let value = unsafe { usage.assume_init() }.ru_maxrss.max(0) as u64;
    if cfg!(target_os = "macos") {
        value
    } else {
        value * 1024
    }
}

#[cfg(not(unix))]
fn peak_memory_bytes() -> u64 {
    0
}

fn make_tile_specs(
    width: u32,
    height: u32,
    max_edge: u32,
    long_ratio: f32,
    overlap: f32,
) -> Vec<TileSpec> {
    let aspect = (width.max(height) as f32) / (width.min(height).max(1) as f32);
    if aspect <= long_ratio {
        return vec![TileSpec {
            bounds: NormalizedRect {
                left: 0.0,
                top: 0.0,
                right: 1.0,
                bottom: 1.0,
            },
            x: 0,
            y: 0,
            width,
            height,
        }];
    }
    let vertical = height >= width;
    let short = if vertical { width } else { height };
    let long = if vertical { height } else { width };
    let scale = (max_edge as f32 / short as f32).min(1.0);
    let tile_long = (max_edge as f32 / scale).max(short as f32).min(long as f32);
    let step = (tile_long * (1.0 - overlap.clamp(0.0, 0.9))).max(1.0);
    let mut result = Vec::new();
    let mut start = 0.0;
    while start < long as f32 {
        let end = (start + tile_long).min(long as f32);
        let (x, y, crop_width, crop_height) = if vertical {
            (0, start.floor() as u32, width, (end - start).ceil() as u32)
        } else {
            (start.floor() as u32, 0, (end - start).ceil() as u32, height)
        };
        result.push(TileSpec {
            bounds: if vertical {
                NormalizedRect {
                    left: 0.0,
                    top: start / long as f32,
                    right: 1.0,
                    bottom: end / long as f32,
                }
            } else {
                NormalizedRect {
                    left: start / long as f32,
                    top: 0.0,
                    right: end / long as f32,
                    bottom: 1.0,
                }
            },
            x,
            y,
            width: crop_width.min(width - x),
            height: crop_height.min(height - y),
        });
        if end >= long as f32 {
            break;
        }
        start += step;
    }
    result
}

fn materialize_tile(original: &DynamicImage, spec: TileSpec, max_edge: u32) -> Tile {
    let crop = original.crop_imm(spec.x, spec.y, spec.width, spec.height);
    let scale = (max_edge as f32 / spec.width.max(spec.height) as f32).min(1.0);
    Tile {
        bounds: spec.bounds,
        image: crop.resize(
            (spec.width as f32 * scale).round().max(1.0) as u32,
            (spec.height as f32 * scale).round().max(1.0) as u32,
            FilterType::CatmullRom,
        ),
    }
}

fn detect_tile(session: &mut Session, tile: &Tile) -> Result<Vec<Detection>> {
    let (width, height) = tile.image.dimensions();
    let ratio = (CTD_INPUT as f32 / width.max(height) as f32).min(1.0);
    let resized_width = ((width as f32 * ratio).round() as u32).max(1);
    let resized_height = ((height as f32 * ratio).round() as u32).max(1);
    let resized = tile
        .image
        .resize_exact(resized_width, resized_height, FilterType::Triangle)
        .to_rgb8();
    let mut input = vec![0.0f32; (3 * CTD_INPUT * CTD_INPUT) as usize];
    let plane = (CTD_INPUT * CTD_INPUT) as usize;
    for (x, y, pixel) in resized.enumerate_pixels() {
        let offset = y as usize * CTD_INPUT as usize + x as usize;
        // CTD upstream preprocess ultimately supplies BGR channel order.
        input[offset] = pixel[2] as f32 / 255.0;
        input[plane + offset] = pixel[1] as f32 / 255.0;
        input[2 * plane + offset] = pixel[0] as f32 / 255.0;
    }
    let outputs = session.run(inputs![TensorRef::from_array_view((
        vec![1, 3, CTD_INPUT as i64, CTD_INPUT as i64],
        input.as_slice()
    ))?])?;
    let (shape, raw) = outputs[0].try_extract_tensor::<f32>()?;
    if shape.len() != 3 || shape[0] != 1 {
        bail!("CTD 输出形状异常：{shape:?}");
    }
    let rows = shape[1] as usize;
    let columns = shape[2] as usize;
    if columns < 6 {
        bail!("CTD 输出列数异常：{columns}");
    }
    if std::env::var_os("MANGA_OCR_DEBUG").is_some() {
        let max_objectness = (0..rows)
            .map(|row| raw[row * columns + 4])
            .fold(f32::NEG_INFINITY, f32::max);
        eprintln!("CTD output={shape:?}, max_objectness={max_objectness}");
    }
    let mut candidates = Vec::new();
    for row in 0..rows {
        let values = &raw[row * columns..(row + 1) * columns];
        if values[4] <= 0.4 {
            continue;
        }
        let (class_id, class_score) = values[5..]
            .iter()
            .copied()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(&b.1))
            .unwrap();
        let confidence = values[4] * class_score;
        if confidence <= 0.4 {
            continue;
        }
        let x1 = (values[0] - values[2] / 2.0).clamp(0.0, resized_width as f32);
        let y1 = (values[1] - values[3] / 2.0).clamp(0.0, resized_height as f32);
        let x2 = (values[0] + values[2] / 2.0).clamp(0.0, resized_width as f32);
        let y2 = (values[1] + values[3] / 2.0).clamp(0.0, resized_height as f32);
        let local = NormalizedRect {
            left: x1 / resized_width as f32,
            top: y1 / resized_height as f32,
            right: x2 / resized_width as f32,
            bottom: y2 / resized_height as f32,
        };
        let page = NormalizedRect {
            left: tile.bounds.left + local.left * tile.bounds.width(),
            top: tile.bounds.top + local.top * tile.bounds.height(),
            right: tile.bounds.left + local.right * tile.bounds.width(),
            bottom: tile.bounds.top + local.bottom * tile.bounds.height(),
        }
        .clamp();
        if page.area() > 0.0 {
            candidates.push(Detection {
                bounds: page,
                confidence,
                class_id,
            });
        }
    }
    candidates.sort_by(|a, b| b.confidence.total_cmp(&a.confidence));
    let mut result: Vec<Detection> = Vec::new();
    for candidate in candidates {
        if result.iter().all(|existing| {
            existing.class_id != candidate.class_id || existing.bounds.iou(candidate.bounds) < 0.35
        }) {
            result.push(candidate);
        }
        if result.len() >= 300 {
            break;
        }
    }
    Ok(result)
}

fn merge_detections(mut values: Vec<Detection>, threshold: f32) -> Vec<Detection> {
    values.sort_by(|a, b| b.confidence.total_cmp(&a.confidence));
    let mut result: Vec<Detection> = Vec::new();
    for value in values {
        if let Some(existing) = result.iter_mut().find(|existing| {
            existing.class_id == value.class_id && existing.bounds.iou(value.bounds) >= threshold
        }) {
            existing.bounds = existing.bounds.union(value.bounds);
            existing.confidence = existing.confidence.max(value.confidence);
        } else {
            result.push(value);
        }
    }
    result
}

fn crop_normalized(image: &DynamicImage, rect: NormalizedRect) -> DynamicImage {
    let (width, height) = image.dimensions();
    let x1 = (rect.left * width as f32)
        .floor()
        .clamp(0.0, width.saturating_sub(1) as f32) as u32;
    let y1 = (rect.top * height as f32)
        .floor()
        .clamp(0.0, height.saturating_sub(1) as f32) as u32;
    let x2 = (rect.right * width as f32)
        .ceil()
        .clamp((x1 + 1) as f32, width as f32) as u32;
    let y2 = (rect.bottom * height as f32)
        .ceil()
        .clamp((y1 + 1) as f32, height as f32) as u32;
    image.crop_imm(x1, y1, x2 - x1, y2 - y1)
}

fn baberu_pixels(image: &DynamicImage) -> Vec<f32> {
    let rgb = image.to_rgb8();
    let (width, height) = rgb.dimensions();
    let scale = (BABERU_INPUT as f32 / width.max(height) as f32).min(1.0);
    let target_width = ((width as f32 * scale).round() as u32).max(1);
    let target_height = ((height as f32 * scale).round() as u32).max(1);
    let resized =
        image::imageops::resize(&rgb, target_width, target_height, FilterType::CatmullRom);
    let mut canvas =
        ImageBuffer::from_pixel(BABERU_INPUT, BABERU_INPUT, Rgb([255u8, 255u8, 255u8]));
    let offset_x = (BABERU_INPUT - target_width) / 2;
    let offset_y = (BABERU_INPUT - target_height) / 2;
    image::imageops::replace(&mut canvas, &resized, offset_x as i64, offset_y as i64);
    let mean = [0.485f32, 0.456, 0.406];
    let std = [0.229f32, 0.224, 0.225];
    let plane = (BABERU_INPUT * BABERU_INPUT) as usize;
    let mut result = vec![0.0; plane * 3];
    for (x, y, pixel) in canvas.enumerate_pixels() {
        let offset = y as usize * BABERU_INPUT as usize + x as usize;
        for channel in 0..3 {
            result[channel * plane + offset] =
                (pixel[channel] as f32 / 255.0 - mean[channel]) / std[channel];
        }
    }
    result
}

fn recognize(
    vision: &mut Session,
    prefill: &mut Session,
    step: &mut Session,
    vocab: &Vocab,
    image: &DynamicImage,
    cancelled: &AtomicBool,
) -> Result<(String, f32)> {
    let pixels = baberu_pixels(image);
    let vision_outputs = vision.run(inputs!["pixel_values" => TensorRef::from_array_view((vec![1, 3, BABERU_INPUT as i64, BABERU_INPUT as i64], pixels.as_slice()))?])?;
    let (vision_shape, vision_data) =
        vision_outputs["vision_embeds"].try_extract_tensor::<f32>()?;
    let vision_shape: Vec<i64> = vision_shape.iter().copied().collect();
    let vision_data = vision_data.to_vec();
    drop(vision_outputs);
    let bos = [1i64];
    let prefill_outputs = prefill.run(inputs![
        "vision_embeds" => TensorRef::from_array_view((vision_shape.clone(), vision_data.as_slice()))?,
        "input_ids" => TensorRef::from_array_view((vec![1, 1], bos.as_slice()))?
    ])?;
    let mut logits = last_logits(&prefill_outputs[0])?;
    let mut past = extract_past(&prefill_outputs)?;
    drop(prefill_outputs);
    let mut sequence = vec![1i64];
    let mut tokens = Vec::new();
    let mut token_confidences = Vec::new();
    let mut position = vision_shape.get(1).copied().unwrap_or(256) + 1;
    for _ in 0..128 {
        check_cancel(cancelled)?;
        apply_repetition_penalty(&mut logits, &sequence, 1.2);
        if let Some(&last) = tokens.last() {
            if vocab.content_ids.contains(&last)
                && tokens
                    .iter()
                    .rev()
                    .take_while(|&&token| token == last)
                    .count()
                    >= 12
            {
                if let Some(value) = logits.get_mut(last as usize) {
                    *value = f32::NEG_INFINITY;
                }
            }
        }
        let next = logits
            .iter()
            .copied()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(&b.1))
            .map(|(index, _)| index as i64)
            .unwrap_or(2);
        token_confidences.push(softmax_probability(&logits, next as usize));
        if next == 2 {
            break;
        }
        tokens.push(next);
        sequence.push(next);
        if tokens.len() >= 128 {
            break;
        }
        let input_ids = [next];
        let position_ids = [position];
        let outputs = step.run(inputs![
            TensorRef::from_array_view((vec![1, 1], input_ids.as_slice()))?,
            TensorRef::from_array_view((vec![1, 1], position_ids.as_slice()))?,
            TensorRef::from_array_view((past[0].0.clone(), past[0].1.as_slice()))?,
            TensorRef::from_array_view((past[1].0.clone(), past[1].1.as_slice()))?,
            TensorRef::from_array_view((past[2].0.clone(), past[2].1.as_slice()))?,
            TensorRef::from_array_view((past[3].0.clone(), past[3].1.as_slice()))?,
            TensorRef::from_array_view((past[4].0.clone(), past[4].1.as_slice()))?,
            TensorRef::from_array_view((past[5].0.clone(), past[5].1.as_slice()))?,
            TensorRef::from_array_view((past[6].0.clone(), past[6].1.as_slice()))?,
            TensorRef::from_array_view((past[7].0.clone(), past[7].1.as_slice()))?,
            TensorRef::from_array_view((past[8].0.clone(), past[8].1.as_slice()))?,
            TensorRef::from_array_view((past[9].0.clone(), past[9].1.as_slice()))?,
            TensorRef::from_array_view((past[10].0.clone(), past[10].1.as_slice()))?,
            TensorRef::from_array_view((past[11].0.clone(), past[11].1.as_slice()))?
        ])?;
        logits = last_logits(&outputs[0])?;
        past = extract_past(&outputs)?;
        position += 1;
    }
    let confidence = if token_confidences.is_empty() {
        0.0
    } else {
        token_confidences.iter().sum::<f32>() / token_confidences.len() as f32
    };
    Ok((vocab.decode(&tokens), confidence))
}

fn last_logits(value: &ort::value::DynValue) -> Result<Vec<f32>> {
    let (shape, values) = value.try_extract_tensor::<f32>()?;
    let vocab = *shape.last().ok_or_else(|| anyhow!("logits 无维度"))? as usize;
    if values.len() < vocab {
        bail!("logits 数据不足");
    }
    Ok(values[values.len() - vocab..].to_vec())
}

fn extract_past(outputs: &ort::session::SessionOutputs<'_>) -> Result<Vec<(Vec<i64>, Vec<f32>)>> {
    if outputs.len() < 13 {
        bail!("Baberu decoder 输出不足：{}", outputs.len());
    }
    (1..13)
        .map(|index| {
            let (shape, values) = outputs[index].try_extract_tensor::<f32>()?;
            Ok((shape.iter().copied().collect(), values.to_vec()))
        })
        .collect()
}

fn apply_repetition_penalty(logits: &mut [f32], sequence: &[i64], penalty: f32) {
    let unique: HashSet<i64> = sequence.iter().copied().collect();
    for token in unique {
        if let Some(value) = logits.get_mut(token as usize) {
            *value = if *value < 0.0 {
                *value * penalty
            } else {
                *value / penalty
            };
        }
    }
}

fn softmax_probability(logits: &[f32], selected: usize) -> f32 {
    let max = logits.iter().copied().fold(f32::NEG_INFINITY, f32::max);
    let denominator: f32 = logits.iter().map(|value| (*value - max).exp()).sum();
    if denominator <= 0.0 {
        0.0
    } else {
        (logits[selected] - max).exp() / denominator
    }
}

fn detect_language(text: &str, class_id: usize) -> String {
    if text.chars().any(|ch| matches!(ch as u32, 0x3040..=0x30ff)) {
        return "ja".to_owned();
    }
    if text.chars().any(|ch| matches!(ch as u32, 0x3400..=0x9fff)) {
        return "zh".to_owned();
    }
    if text.chars().any(|ch| ch.is_ascii_alphabetic()) {
        return "en".to_owned();
    }
    match class_id {
        0 => "en",
        1 => "ja",
        _ => "unknown",
    }
    .to_owned()
}

fn block_id(payload: &Value, rect: NormalizedRect) -> String {
    let image_hash = payload
        .get("imageSha256")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let mut hash = Sha256::new();
    hash.update(format!(
        "{image_hash}|{:.6}|{:.6}|{:.6}|{:.6}",
        rect.left, rect.top, rect.right, rect.bottom
    ));
    format!("{:x}", hash.finalize())[..16].to_owned()
}

fn required_str<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("缺少字段 {key}"))
}

fn check_cancel(cancelled: &AtomicBool) -> Result<()> {
    if cancelled.load(Ordering::Relaxed) {
        bail!("任务已取消");
    }
    Ok(())
}

fn progress(
    stdout: &Arc<Mutex<io::Stdout>>,
    request_id: &str,
    stage: &str,
    completed: usize,
    total: usize,
    message: &str,
) {
    emit(
        stdout,
        json!({"protocolVersion": PROTOCOL_VERSION, "requestId": request_id, "type": "progress", "stage": stage, "completed": completed, "total": total, "message": message}),
    );
}

fn emit_ok(stdout: &Arc<Mutex<io::Stdout>>, request_id: &str, result: Value) {
    emit(
        stdout,
        json!({"protocolVersion": PROTOCOL_VERSION, "requestId": request_id, "ok": true, "result": result}),
    );
}

fn emit_error(stdout: &Arc<Mutex<io::Stdout>>, request_id: &str, error: &str) {
    emit(
        stdout,
        json!({"protocolVersion": PROTOCOL_VERSION, "requestId": request_id, "ok": false, "error": error}),
    );
}

fn emit(stdout: &Arc<Mutex<io::Stdout>>, value: Value) {
    let mut stdout = stdout.lock().unwrap();
    let _ = writeln!(stdout, "{}", value);
    let _ = stdout.flush();
}
