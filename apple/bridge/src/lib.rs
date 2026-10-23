//! UniFFI bridge between the LightCraft engine and the Swift app (iOS / iPadOS).
//!
//! The API is specified in `apple/docs/CONTRACT.md` section 3; names and types here match it.
//! Never panics on input: engine calls run under `catch_unwind` as a last-resort guard.
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Arc, Mutex, PoisonError};

use lightcraft_catalog::PhotoId;
use lightcraft_engine::Session;
use serde_json::{Value, json};

mod info;
mod runtime;
pub mod menus_src;
pub mod params_doc;
mod render;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BridgeError {
    #[error("{message}")]
    Failed { message: String },
}

pub(crate) fn fail(message: impl Into<String>) -> BridgeError {
    BridgeError::Failed { message: message.into() }
}

#[derive(uniffi::Record)]
pub struct CommandInfo {
    pub id: String,
    pub label: String,
    /// e.g. ["Photo", "Set Rating"]; empty = not in menus.
    pub menu: Vec<String>,
    /// egui notation, "Cmd+Shift+R".
    pub shortcut: Option<String>,
    /// Human/agent-readable params doc.
    pub params: String,
    /// `journal == false`.
    pub is_query: bool,
}

/// UI-only desktop commands, parsed from `crates/ui-egui/src/menus.rs`.
#[derive(uniffi::Record)]
pub struct UiCommandInfo {
    pub id: String,
    pub label: String,
    pub shortcut: Option<String>,
    /// "Window>Tools" -> ["Window", "Tools"]; empty = not in menus.
    pub menu: Vec<String>,
}

/// Desktop menu bar order. Items: command ids, "---" separators, "@Submenu" placeholders.
#[derive(uniffi::Record)]
pub struct MenuSection {
    pub title: String,
    pub items: Vec<String>,
}

/// Structured view of a params doc; best effort.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ParamField {
    /// "" = free-form extra params (`doc` = raw fragment).
    pub key: String,
    /// "number", "integer", "bool", "choice", "string", "ids", "json".
    pub kind: String,
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub default_json: Option<String>,
    pub choices: Vec<String>,
    pub label: String,
    pub is_optional: bool,
    pub doc: String,
}

#[derive(uniffi::Record)]
pub struct ControlInfo {
    pub id: String,
    pub label: String,
    pub section: String,
    pub section_id: String,
    pub min: f64,
    pub max: f64,
    pub default_value: f64,
    pub step: f64,
    pub decimals: u32,
    /// "plain","centered","temp","tint","gradient","hue","sat","lum","rainbow".
    pub track: String,
    pub gradient: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct LibraryState {
    pub photo_count: u64,
    pub visible_count: u64,
    pub active: Option<u64>,
    pub selected: Vec<u64>,
    pub can_undo: bool,
    pub can_redo: bool,
    pub undo_label: Option<String>,
    pub redo_label: Option<String>,
    /// Bumps on every call that may change anything.
    pub revision: u64,
    /// Changes when an undo step is recorded, undone or redone.
    pub history_id: u64,
    /// JSON of the current library source.
    pub source: String,
    pub active_mask: Option<u32>,
    pub unsaved: Option<String>,
}

#[derive(uniffi::Record)]
pub struct PhotoInfo {
    pub id: u64,
    pub file_name: String,
    pub format: String,
    pub width: u32,
    pub height: u32,
    pub rating: u32,
    /// "pick", "reject", "none".
    pub flag: String,
    /// "" or "red","yellow","green","blue","purple".
    pub color_label: String,
    pub edited: bool,
    pub captured: Option<String>,
    pub camera: String,
    pub lens: String,
    pub title: String,
}

#[derive(uniffi::Record)]
pub struct AlbumInfo {
    pub id: u64,
    pub name: String,
    /// "album", "smart", "folder".
    pub kind: String,
    pub parent: Option<u64>,
    pub depth: u32,
    pub count: u64,
}

#[derive(uniffi::Record)]
pub struct RenderedImage {
    pub width: u32,
    pub height: u32,
    /// RGBA8 sRGB, premultiplied, stride = width * 4.
    pub rgba: Vec<u8>,
}

/// What the engine's caches hold (for the `-LightCraftMemLog` diagnostics).
#[derive(Default, uniffi::Record)]
pub struct MemoryStats {
    pub budget: u64,
    pub cache_budget: u64,
    pub cache_bytes: u64,
    pub rendered_entries: u64,
    pub rendered_bytes: u64,
    pub thumb_source_bytes: u64,
    pub preview_source_bytes: u64,
    pub full_source_bytes: u64,
    pub work_bytes: u64,
    pub work_limit: u64,
    pub gpu_allocated: u64,
    pub gpu_pooled: u64,
}

struct Inner {
    session: Session,
    revision: u64,
    history_id: u64,
    /// (commits, undo length, redo length) when `history_id` was last bumped.
    history_sig: (u64, usize, usize),
}

impl Inner {
    fn new(session: Session) -> Self {
        let sig = Self::sig(&session);
        Inner { session, revision: 1, history_id: 1, history_sig: sig }
    }

    fn sig(s: &Session) -> (u64, usize, usize) {
        (s.commits(), s.undo.len(), s.redo.len())
    }

    /// Bump `history_id` when the undo/redo stacks moved since the last look.
    fn sync_history(&mut self) {
        let sig = Self::sig(&self.session);
        if sig != self.history_sig {
            self.history_sig = sig;
            self.history_id += 1;
        }
    }

    fn touch(&mut self) {
        self.revision += 1;
        self.sync_history();
    }
}

#[derive(uniffi::Object)]
pub struct LibraryHandle {
    inner: Mutex<Inner>,
}

fn panic_message(payload: &(dyn std::any::Any + Send)) -> String {
    let text = payload.downcast_ref::<&str>().map(|s| (*s).to_string()).or_else(|| payload.downcast_ref::<String>().cloned());
    format!("internal error: {}", text.unwrap_or_else(|| "the engine panicked".into()))
}

fn demo_session() -> Session {
    Session::with_demo().with_fs().with_system_clock()
}

fn parse_params(params_json: &str) -> Result<Value, BridgeError> {
    if params_json.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(params_json).map_err(|e| fail(format!("params_json is not valid JSON: {e}")))
}

impl LibraryHandle {
    fn wrap(mut session: Session) -> Arc<Self> {
        runtime::apply(&mut session);
        Arc::new(Self { inner: Mutex::new(Inner::new(session)) })
    }

    /// Run `f` with the session locked, turning a panic into an error.
    fn guarded<T>(&self, f: impl FnOnce(&mut Inner) -> Result<T, BridgeError>) -> Result<T, BridgeError> {
        let mut guard = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
        match catch_unwind(AssertUnwindSafe(|| f(&mut guard))) {
            Ok(r) => r,
            Err(payload) => Err(fail(panic_message(payload.as_ref()))),
        }
    }

    /// Like [`Self::guarded`] for calls that cannot report an error.
    fn guarded_or<T>(&self, fallback: T, f: impl FnOnce(&mut Inner) -> T) -> T {
        let mut guard = self.inner.lock().unwrap_or_else(PoisonError::into_inner);
        catch_unwind(AssertUnwindSafe(|| f(&mut guard))).unwrap_or(fallback)
    }

    /// Build a job under the lock, run it outside, hand the loaded source back to the cache.
    fn run_job(
        &self,
        build: impl FnOnce(&mut Session) -> Option<lightcraft_engine::media::RenderJob>,
    ) -> Result<RenderedImage, BridgeError> {
        let job = self.guarded(|i| build(&mut i.session).ok_or_else(|| fail("no such photo")))?;
        let result = catch_unwind(AssertUnwindSafe(|| job.run())).map_err(|p| fail(panic_message(p.as_ref())))?;
        let image = render::to_image(&result);
        self.guarded(|i| {
            i.session.accept(&result);
            Ok(())
        })?;
        image
    }
}

#[uniffi::export]
impl LibraryHandle {
    /// Open (creating it if missing) the library folder `dir`.
    #[uniffi::constructor]
    pub fn open(dir: String, seed_demo: bool) -> Result<Arc<Self>, BridgeError> {
        let handle = Self::wrap(Session::new().with_fs().with_system_clock());
        handle.guarded(|i| {
            std::fs::create_dir_all(&dir).map_err(|e| fail(format!("can't create {dir}: {e}")))?;
            i.session.open_library(&dir, seed_demo).map_err(|e| fail(e.to_string()))?;
            i.touch();
            Ok(())
        })?;
        Ok(handle)
    }

    /// The procedural demo library, in memory (nothing is saved).
    #[uniffi::constructor]
    pub fn in_memory_demo() -> Arc<Self> {
        Self::wrap(demo_session())
    }

    /// Flush the journal and preferences.
    pub fn persist(&self) -> Result<(), BridgeError> {
        self.guarded(|i| {
            i.session.persist().map_err(|e| fail(e.to_string()))?;
            i.session.save_view();
            // preferences are written by the engine's own prefs path; ignore a library-less session
            let _ = i.session.save_prefs();
            i.touch();
            Ok(())
        })
    }

    /// Persist and release the library lock.
    pub fn close(&self) -> Result<(), BridgeError> {
        self.guarded(|i| {
            i.session.close_library().map_err(|e| fail(e.to_string()))?;
            i.session.library = None;
            i.touch();
            Ok(())
        })
    }

    /// Run a command by id with JSON params; returns the result JSON.
    pub fn execute(&self, id: String, params_json: String) -> Result<String, BridgeError> {
        let params = parse_params(&params_json)?;
        self.guarded(|i| {
            let mutates = lightcraft_engine::cmd::find_command(&id).is_none_or(|c| c.journal);
            let r = i.session.execute(&id, &params);
            if mutates {
                i.touch();
            } else {
                i.sync_history();
            }
            r.map(|v| v.to_string()).map_err(|e| fail(e.to_string()))
        })
    }

    /// `None` = enabled. Unknown ids are reported as disabled.
    pub fn disabled_reason(&self, id: String) -> Option<String> {
        self.guarded_or(Some("internal error".to_string()), |i| match lightcraft_engine::cmd::find_command(&id) {
            None => Some(format!("unknown command `{id}`")),
            Some(spec) => (spec.enabled)(&i.session).err().or_else(|| runtime::model_reason(&i.session, &id)),
        })
    }

    /// Engine cache sizes and the memory budget (diagnostics).
    pub fn memory_stats(&self) -> MemoryStats {
        self.guarded_or(MemoryStats::default(), |i| runtime::stats(&i.session))
    }

    /// Drop the engine's cached decodes and renders (memory warning); the budget is restored after.
    pub fn trim_memory(&self) {
        self.guarded_or((), |i| runtime::trim(&mut i.session));
    }

    /// Map normalized points `[x0, y0, x1, y1, ...]` of the stored, lens-corrected frame to the displayed
    /// (transformed) frame of photo `id`'s current settings. Returns the input unchanged on any error.
    pub fn map_points_to_display(&self, id: u64, points: Vec<f64>) -> Vec<f64> {
        let fallback = points.clone();
        self.guarded_or(fallback, |i| runtime::map_points(&i.session, id, &points, true))
    }

    /// Inverse of `map_points_to_display`: displayed (transformed) frame to the lens-corrected frame.
    pub fn map_points_from_display(&self, id: u64, points: Vec<f64>) -> Vec<f64> {
        let fallback = points.clone();
        self.guarded_or(fallback, |i| runtime::map_points(&i.session, id, &points, false))
    }

    pub fn undo(&self) -> Result<String, BridgeError> {
        self.guarded(|i| {
            let r = i.session.undo_step();
            i.session.persist_if_dirty();
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn redo(&self) -> Result<String, BridgeError> {
        self.guarded(|i| {
            let r = i.session.redo_step();
            i.session.persist_if_dirty();
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    /// Start a continuous edit (slider drag): everything until `end_interaction` is one undo step.
    pub fn begin_interaction(&self, label: String) -> Result<(), BridgeError> {
        self.guarded(|i| {
            let r = i.session.begin_interaction(&label);
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn end_interaction(&self) -> Result<(), BridgeError> {
        self.guarded(|i| {
            let r = i.session.end_interaction();
            i.session.persist_if_dirty();
            i.touch();
            r.map_err(|e| fail(e.to_string()))
        })
    }

    pub fn state(&self) -> LibraryState {
        self.guarded_or(
            LibraryState {
                photo_count: 0,
                visible_count: 0,
                active: None,
                selected: Vec::new(),
                can_undo: false,
                can_redo: false,
                undo_label: None,
                redo_label: None,
                revision: 0,
                history_id: 0,
                source: "null".into(),
                active_mask: None,
                unsaved: Some("internal error".into()),
            },
            |i| {
                i.sync_history();
                let s = &mut i.session;
                let visible_count = s.visible_cloned().len() as u64;
                LibraryState {
                    photo_count: s.catalog.len() as u64,
                    visible_count,
                    active: s.active().map(|p| p.0),
                    selected: s.selected().into_iter().map(|p| p.0).collect(),
                    can_undo: !s.undo.is_empty(),
                    can_redo: !s.redo.is_empty(),
                    undo_label: s.undo.last().map(|e| e.label.clone()),
                    redo_label: s.redo.last().map(|e| e.label.clone()),
                    revision: i.revision,
                    history_id: i.history_id,
                    source: serde_json::to_string(&s.source).unwrap_or_else(|_| format!("{:?}", s.source)),
                    active_mask: s.active_mask,
                    unsaved: s.unsaved().map(|(n, why)| format!("{n} change(s) not saved: {why}")),
                }
            },
        )
    }

    pub fn visible_photos(&self) -> Vec<u64> {
        self.guarded_or(Vec::new(), |i| i.session.visible_cloned().into_iter().map(|p| p.0).collect())
    }

    pub fn photo_info(&self, id: u64) -> Option<PhotoInfo> {
        self.guarded_or(None, |i| info::photo_info(&i.session, id))
    }

    pub fn albums(&self) -> Vec<AlbumInfo> {
        self.guarded_or(Vec::new(), |i| info::albums(&i.session))
    }

    /// JSON `{controlId: value}` for every develop control of the photo.
    pub fn develop_values(&self, id: u64) -> Result<String, BridgeError> {
        self.guarded(|i| info::develop_values(&i.session, id).ok_or_else(|| fail(format!("no such photo {id}"))))
    }

    /// The photo's full develop settings as JSON.
    pub fn develop_json(&self, id: u64) -> Result<String, BridgeError> {
        self.guarded(|i| {
            let d = i.session.develop_of(PhotoId(id)).ok_or_else(|| fail(format!("no such photo {id}")))?;
            serde_json::to_string(&*d).map_err(|e| fail(e.to_string()))
        })
    }

    /// Render fitting `max_w` x `max_h`. Thread-safe: the render itself runs outside the lock.
    pub fn render(&self, id: u64, max_w: u32, max_h: u32, before: bool, draft: bool, apply_crop: bool) -> Result<RenderedImage, BridgeError> {
        self.run_job(|s| {
            let job = s.render_job(PhotoId(id), max_w.max(1) as usize, max_h.max(1) as usize, before, apply_crop)?;
            Some(if draft { job.draft() } else { job })
        })
    }

    pub fn thumbnail(&self, id: u64, edge: u32) -> Result<RenderedImage, BridgeError> {
        self.run_job(|s| s.thumb_job(PhotoId(id), edge.max(1) as usize))
    }

    /// Full-quality JPEG of the photo with `long_edge` (0 = full size) and `quality` 1..100.
    pub fn export_jpeg(&self, id: u64, long_edge: u32, quality: u32) -> Result<Vec<u8>, BridgeError> {
        let opts = lightcraft_engine::export::ExportOptions::from_json(&json!({
            "format": "jpeg",
            "quality": quality.clamp(1, 100),
            "longEdge": long_edge,
            "dontEnlarge": true,
        }));
        let prepared = self.guarded(|i| lightcraft_engine::export::prepare_export(&mut i.session, PhotoId(id), &opts, 1).map_err(fail))?;
        let exported = catch_unwind(AssertUnwindSafe(|| prepared.run())).map_err(|p| fail(panic_message(p.as_ref())))?.map_err(fail)?;
        Ok(exported.bytes)
    }
}

impl Drop for LibraryHandle {
    fn drop(&mut self) {
        // Best effort: flush and release the library lock if the app never called `close`.
        let inner = self.inner.get_mut().unwrap_or_else(PoisonError::into_inner);
        let _ = catch_unwind(AssertUnwindSafe(|| {
            if inner.session.library.is_some() {
                let _ = inner.session.close_library();
            }
        }));
    }
}

/// Every engine command with its menu placement, shortcut and params doc.
#[uniffi::export]
pub fn command_catalog() -> Vec<CommandInfo> {
    lightcraft_engine::cmd::command_specs()
        .iter()
        .map(|c| CommandInfo {
            id: c.id.to_string(),
            label: c.label.to_string(),
            menu: c.menu.iter().map(|m| (*m).to_string()).collect(),
            shortcut: c.shortcut.map(str::to_string),
            params: c.params.to_string(),
            is_query: !c.journal,
        })
        .collect()
}

/// UI-only desktop commands (views, panels, tools, dialogs).
#[uniffi::export]
pub fn ui_command_catalog() -> Vec<UiCommandInfo> {
    menus_src::ui_commands()
}

/// The desktop menu bar layout.
#[uniffi::export]
pub fn desktop_menu_layout() -> Vec<MenuSection> {
    menus_src::menu_layout()
}

/// Parsed parameters of a command (empty for unknown ids and commands without params).
#[uniffi::export]
pub fn command_params(id: String) -> Vec<ParamField> {
    catch_unwind(|| params_doc::fields_for(&id)).unwrap_or_default()
}

/// `None` = supported on iOS; `Some(reason)` from `ios-excluded-commands.txt`.
#[uniffi::export]
pub fn command_platform_support(id: String) -> Option<String> {
    params_doc::excluded_commands().into_iter().find(|(e, _)| *e == id).map(|(_, reason)| reason)
}

/// Every develop slider spec.
#[uniffi::export]
pub fn develop_controls() -> Vec<ControlInfo> {
    info::develop_controls()
}

#[uniffi::export]
pub fn engine_version() -> String {
    format!("lightcraft-apple {}", env!("CARGO_PKG_VERSION"))
}

/// Call once at launch, before opening a library: `physical_memory` is `ProcessInfo.physicalMemory`
/// (sizes the engine's memory budget for this device), `support_dir` the Application Support folder
/// (face models live in `<support_dir>/LightCraft/FaceModels`). Applies to sessions opened afterwards.
#[uniffi::export]
pub fn configure_runtime(physical_memory: u64, support_dir: String) {
    runtime::configure(physical_memory, &support_dir);
}
