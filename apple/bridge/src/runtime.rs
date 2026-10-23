//! Device-level runtime settings: engine memory budget, face-models folder, point mapping.

use std::path::PathBuf;
use std::sync::{Mutex, PoisonError};

use lightcraft_catalog::PhotoId;
use lightcraft_engine::Session;

use crate::MemoryStats;

const MIB: u64 = 1 << 20;
const FACE_MODEL_ID: &str = "yunet-2023mar";

#[derive(Clone)]
struct Config {
    budget: usize,
    face_models: Option<PathBuf>,
}

static CONFIG: Mutex<Option<Config>> = Mutex::new(None);

/// A tenth of the device's RAM, within 192..640 MiB. The engine splits it: half for caches, a quarter for
/// decodes in flight, an eighth for GPU buffers. (Its own default assumes 1.5 GiB on iOS, which jetsam kills.)
pub(crate) fn budget_for(physical_memory: u64) -> usize {
    let b = (physical_memory / 10).clamp(192 * MIB, 640 * MIB);
    usize::try_from(b).unwrap_or(640 << 20)
}

pub(crate) fn configure(physical_memory: u64, support_dir: &str) {
    let budget = budget_for(physical_memory);
    let face_models = (!support_dir.trim().is_empty()).then(|| PathBuf::from(support_dir).join("LightCraft").join("FaceModels"));
    if let Some(dir) = &face_models {
        // best effort: a failure shows up as the command's own "can't write" error later
        let _ = std::fs::create_dir_all(dir);
    }
    lightcraft_engine::memory::set_budget(budget);
    *CONFIG.lock().unwrap_or_else(PoisonError::into_inner) = Some(Config { budget, face_models });
}

/// Apply the configured budget and folders to a new session.
pub(crate) fn apply(session: &mut Session) {
    let cfg = CONFIG.lock().unwrap_or_else(PoisonError::into_inner).clone();
    let Some(cfg) = cfg else { return };
    session.set_memory_budget(cfg.budget);
    if session.face_models_dir.is_none() {
        session.face_models_dir = cfg.face_models;
    }
}

/// Why a command that needs the face detector can't run yet (`None` = fine or unrelated).
pub(crate) fn model_reason(session: &Session, id: &str) -> Option<String> {
    if id != "spot.findBlemishes" {
        return None;
    }
    let dir = session.face_models_dir.as_deref()?;
    let home = dir.join(FACE_MODEL_ID);
    if home.join("model.onnx").is_file() && home.join("face-model.json").is_file() {
        None
    } else {
        Some("The face detection model is not installed. Download it first (Faces settings, or the faces.models.download command).".to_string())
    }
}

pub(crate) fn stats(session: &Session) -> MemoryStats {
    let r = session.memory_report();
    let u = |n: usize| n as u64;
    MemoryStats {
        budget: u(r.budget),
        cache_budget: u(r.cache_budget),
        cache_bytes: u(r.engine_bytes),
        rendered_entries: u(r.rendered.count),
        rendered_bytes: u(r.rendered.bytes),
        thumb_source_bytes: u(r.thumb_sources.bytes),
        preview_source_bytes: u(r.preview_sources.bytes),
        full_source_bytes: u(r.full_source.bytes),
        work_bytes: u(r.work_bytes),
        work_limit: u(r.work_limit),
        gpu_allocated: r.gpu.allocated,
        gpu_pooled: r.gpu.pooled,
    }
}

pub(crate) fn trim(session: &mut Session) {
    let keep = session.media.budget();
    session.media.set_budget(0);
    session.media.set_budget(keep);
    lightcraft_engine::memory::release();
}

/// Map `[x, y, ...]` pairs; the input comes back unchanged when the photo or settings are missing.
pub(crate) fn map_points(session: &Session, id: u64, points: &[f64], to_display: bool) -> Vec<f64> {
    let id = PhotoId(id);
    let (Some(photo), Some(d)) = (session.catalog.photo(id), session.develop_of(id)) else { return points.to_vec() };
    let frame = lightcraft_pipeline::geometry::Frame::with_lens(
        photo.width.max(1) as usize,
        photo.height.max(1) as usize,
        &d,
        true,
        photo.embedded_lens.as_ref(),
    );
    let mut out = Vec::with_capacity(points.len());
    for pair in points.chunks(2) {
        let [x, y] = pair else {
            out.extend_from_slice(pair);
            continue;
        };
        let p = lightcraft_geom::Point::new(*x, *y);
        let q = if to_display { frame.corrected_to_transformed(p) } else { frame.transformed_to_corrected(p) };
        if q.x.is_finite() && q.y.is_finite() {
            out.extend_from_slice(&[q.x, q.y]);
        } else {
            out.extend_from_slice(pair);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_is_sized_for_the_device() {
        assert_eq!(budget_for(1 << 30), 192 << 20);
        assert_eq!(budget_for(6 << 30), (6u64 << 30) as usize / 10);
        assert_eq!(budget_for(64 << 30), 640 << 20);
    }
}
