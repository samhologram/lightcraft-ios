//! Read-only views of the session: photos, albums, develop controls.

use crate::{AlbumInfo, ControlInfo, PhotoInfo};
use lightcraft_catalog::{ColorLabel, Flag, PhotoId};
use lightcraft_develop::{CONTROLS, Track, controls};
use lightcraft_engine::Session;

pub(crate) fn photo_info(s: &Session, id: u64) -> Option<PhotoInfo> {
    let p = s.catalog.photo(PhotoId(id))?;
    Some(PhotoInfo {
        id,
        file_name: p.file_name.clone(),
        format: p.format.clone(),
        width: p.width,
        height: p.height,
        rating: u32::from(p.rating),
        flag: match p.flag {
            Flag::Pick => "pick",
            Flag::Reject => "reject",
            Flag::None => "none",
        }
        .to_string(),
        color_label: p.label.map(label_name).unwrap_or_default().to_string(),
        edited: p.is_edited(),
        captured: p.captured.clone(),
        camera: p.meta.camera.clone(),
        lens: p.meta.lens.clone(),
        title: p.meta.title.clone(),
    })
}

fn label_name(l: ColorLabel) -> &'static str {
    match l {
        ColorLabel::Red => "red",
        ColorLabel::Yellow => "yellow",
        ColorLabel::Green => "green",
        ColorLabel::Blue => "blue",
        ColorLabel::Purple => "purple",
    }
}

const MAX_DEPTH: u32 = 32;

/// Albums, smart albums and album folders, depth-first in the sidebar's order.
pub(crate) fn albums(s: &Session) -> Vec<AlbumInfo> {
    fn walk(s: &Session, parent: Option<lightcraft_catalog::AlbumId>, depth: u32, out: &mut Vec<AlbumInfo>) {
        for a in s.catalog.album_children(parent) {
            let kind = if a.folder {
                "folder"
            } else if a.smart.is_some() {
                "smart"
            } else {
                "album"
            };
            out.push(AlbumInfo {
                id: a.id.0,
                name: a.name.clone(),
                kind: kind.to_string(),
                parent: a.parent.map(|p| p.0),
                depth,
                count: if a.folder { 0 } else { s.catalog.album_count(a.id) as u64 },
            });
            if a.folder && depth < MAX_DEPTH {
                walk(s, Some(a.id), depth + 1, out);
            }
        }
    }
    let mut out = Vec::new();
    walk(s, None, 0, &mut out);
    out
}

pub(crate) fn develop_controls() -> Vec<ControlInfo> {
    CONTROLS
        .iter()
        .map(|c| {
            let (track, gradient) = match c.track {
                Track::Plain => ("plain", Vec::new()),
                Track::Centered => ("centered", Vec::new()),
                Track::Temp => ("temp", Vec::new()),
                Track::Tint => ("tint", Vec::new()),
                Track::Gradient { from, to } => ("gradient", vec![from.to_string(), to.to_string()]),
                Track::Hue { .. } => ("hue", Vec::new()),
                Track::Sat { .. } => ("sat", Vec::new()),
                Track::Lum { .. } => ("lum", Vec::new()),
                Track::Rainbow => ("rainbow", Vec::new()),
            };
            let section_id = serde_json::to_value(c.section).ok().and_then(|v| v.as_str().map(str::to_string)).unwrap_or_default();
            ControlInfo {
                id: c.id.to_string(),
                label: c.label.to_string(),
                section: c.section.label().to_string(),
                section_id,
                min: c.min,
                max: c.max,
                default_value: c.default,
                step: c.step,
                decimals: u32::from(c.decimals),
                track: track.to_string(),
                gradient,
            }
        })
        .collect()
}

/// `{controlId: value}` for every control of the photo's settings.
pub(crate) fn develop_values(s: &Session, id: u64) -> Option<String> {
    let d = s.develop_of(PhotoId(id))?;
    let mut m = serde_json::Map::new();
    for c in CONTROLS {
        let v = controls::get(&d, c.id).unwrap_or(c.default);
        m.insert(c.id.to_string(), serde_json::Number::from_f64(v).map_or(serde_json::Value::Null, serde_json::Value::Number));
    }
    serde_json::to_string(&m).ok()
}
