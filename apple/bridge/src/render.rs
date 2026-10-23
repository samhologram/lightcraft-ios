//! Rendering helpers: run an engine `RenderJob` and convert the result to RGBA bytes.

use crate::{BridgeError, RenderedImage, fail};
use lightcraft_engine::media::RenderResult;

/// The job's finished image as RGBA8 (opaque photos: alpha 255, so straight == premultiplied).
pub(crate) fn to_image(result: &RenderResult) -> Result<RenderedImage, BridgeError> {
    let r = result.rendered.as_ref().map_err(|e| fail(e.clone()))?;
    let img = &r.image;
    let (w, h) = (img.width, img.height);
    if w == 0 || h == 0 || img.data.len() < w.saturating_mul(h) {
        return Err(fail("the render produced an empty image"));
    }
    let mut rgba = Vec::with_capacity(w * h * 4);
    for p in img.data.iter().take(w * h) {
        let a = u32::from(p[3]);
        if a == 255 {
            rgba.extend_from_slice(p);
        } else {
            let m = |c: u8| ((u32::from(c) * a + 127) / 255) as u8;
            rgba.extend_from_slice(&[m(p[0]), m(p[1]), m(p[2]), p[3]]);
        }
    }
    Ok(RenderedImage { width: u32::try_from(w).unwrap_or(u32::MAX), height: u32::try_from(h).unwrap_or(u32::MAX), rgba })
}
