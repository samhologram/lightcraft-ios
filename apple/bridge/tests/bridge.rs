#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
use lightcraft_apple::*;
use serde_json::{Value, json};

fn values(h: &LibraryHandle, id: u64) -> Value {
    serde_json::from_str(&h.develop_values(id).unwrap()).unwrap()
}

#[test]
fn demo_has_photos_and_state() {
    let h = LibraryHandle::in_memory_demo();
    let photos = h.visible_photos();
    assert!(!photos.is_empty());
    let st = h.state();
    assert_eq!(st.visible_count as usize, photos.len());
    assert!(st.photo_count >= st.visible_count);
    let info = h.photo_info(photos[0]).unwrap();
    assert!(info.width > 0 && info.height > 0);
    assert!(h.photo_info(u64::MAX).is_none());
    assert!(h.albums().iter().all(|a| ["album", "smart", "folder"].contains(&a.kind.as_str())));
}

#[test]
fn select_develop_undo_redo() {
    let h = LibraryHandle::in_memory_demo();
    let id = h.visible_photos()[0];
    h.execute("library.select".into(), json!({"ids": [id], "active": id}).to_string()).unwrap();
    assert_eq!(h.state().active, Some(id));
    let before = values(&h, id);
    let rev = h.state().revision;
    let hist = h.state().history_id;
    h.execute("develop.set".into(), json!({"values": {"light.exposure": 1.0}}).to_string()).unwrap();
    let after = values(&h, id);
    assert_ne!(before["light.exposure"], after["light.exposure"]);
    assert_eq!(after["light.exposure"], json!(1.0));
    let st = h.state();
    assert!(st.revision > rev);
    assert_ne!(st.history_id, hist);
    assert!(st.can_undo);
    assert!(h.photo_info(id).unwrap().edited);
    let h1 = st.history_id;
    h.undo().unwrap();
    let st = h.state();
    assert_ne!(st.history_id, h1);
    assert_eq!(values(&h, id)["light.exposure"], before["light.exposure"]);
    let h2 = st.history_id;
    h.redo().unwrap();
    assert_ne!(h.state().history_id, h2);
    assert_eq!(values(&h, id)["light.exposure"], json!(1.0));
}

#[test]
fn interaction_is_one_step() {
    let h = LibraryHandle::in_memory_demo();
    let id = h.visible_photos()[0];
    h.execute("library.select".into(), json!({"ids": [id]}).to_string()).unwrap();
    h.begin_interaction("Exposure".into()).unwrap();
    for v in [0.2, 0.5, 0.9] {
        h.execute("develop.set".into(), json!({"values": {"light.exposure": v}}).to_string()).unwrap();
    }
    h.end_interaction().unwrap();
    assert_eq!(h.state().undo_label.as_deref(), Some("Exposure"));
    h.undo().unwrap();
    assert_eq!(values(&h, id)["light.exposure"], json!(0.0));
}

#[test]
fn errors_are_errors() {
    let h = LibraryHandle::in_memory_demo();
    assert!(h.execute("no.such".into(), "{}".into()).is_err());
    assert!(h.execute("photo.rate".into(), "not json".into()).is_err());
    assert!(h.disabled_reason("no.such".into()).is_some());
    assert!(h.develop_values(u64::MAX).is_err());
    assert!(h.render(u64::MAX, 100, 100, false, false, true).is_err());
}

#[test]
fn render_and_thumbnail() {
    let h = LibraryHandle::in_memory_demo();
    let id = h.visible_photos()[0];
    let r = h.render(id, 320, 240, false, false, true).unwrap();
    assert!(r.width > 0 && r.height > 0 && r.width <= 320 && r.height <= 240);
    assert_eq!(r.rgba.len(), (r.width * r.height * 4) as usize);
    let d = h.render(id, 160, 120, true, true, false).unwrap();
    assert_eq!(d.rgba.len(), (d.width * d.height * 4) as usize);
    let t = h.thumbnail(id, 128).unwrap();
    assert_eq!(t.rgba.len(), (t.width * t.height * 4) as usize);
    let jpg = h.export_jpeg(id, 256, 80).unwrap();
    assert_eq!(&jpg[..2], &[0xFF, 0xD8]);
}

#[test]
fn catalogs() {
    let cmds = command_catalog();
    assert!(cmds.len() > 100);
    assert!(cmds.iter().any(|c| c.id == "photo.rate" && !c.is_query));
    assert!(cmds.iter().any(|c| c.id == "catalog.query" && c.is_query));
    let ui = ui_command_catalog();
    assert!(ui.iter().any(|c| c.id == "panel.edit"));
    assert_eq!(ui.iter().find(|c| c.id == "tool.brush").unwrap().menu, ["Window", "Tools"]);
    let menus = desktop_menu_layout();
    assert_eq!(menus[0].title, "File");
    assert!(menus[0].items.iter().any(|i| i == "---"));
    assert!(develop_controls().iter().any(|c| c.id == "light.exposure" && c.section_id == "light"));
    assert!(!engine_version().is_empty());
}

#[test]
fn params_and_platform_support() {
    let p = command_params("photo.rate".into());
    let rating = p.iter().find(|f| f.key == "rating").unwrap();
    assert_eq!((rating.kind.as_str(), rating.min, rating.max), ("integer", Some(0.0), Some(5.0)));
    assert!(!rating.is_optional);
    assert!(command_params("no.such".into()).is_empty());
    assert!(command_platform_support("app.showInFinder".into()).is_some());
    assert!(command_platform_support("photo.rate".into()).is_none());
}

#[test]
fn every_excluded_and_listed_id_exists() {
    let engine: std::collections::HashSet<String> = command_catalog().into_iter().map(|c| c.id).collect();
    let ui: std::collections::HashSet<String> = ui_command_catalog().into_iter().map(|c| c.id).collect();
    for line in include_str!("../ios-excluded-commands.txt").lines().filter(|l| !l.starts_with('#') && !l.trim().is_empty()) {
        let id = line.split('\t').next().unwrap();
        assert!(engine.contains(id) || ui.contains(id), "{id}");
    }
}

#[test]
fn open_persist_reopen_keeps_rating() {
    let dir = std::env::temp_dir().join(format!("lc-bridge-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let path = dir.to_string_lossy().to_string();
    let id;
    {
        let h = LibraryHandle::open(path.clone(), true).unwrap();
        assert!(h.state().photo_count > 0);
        id = h.visible_photos()[0];
        h.execute("library.select".into(), json!({"ids": [id]}).to_string()).unwrap();
        h.execute("photo.rate".into(), json!({"rating": 4}).to_string()).unwrap();
        h.persist().unwrap();
        h.close().unwrap();
    }
    {
        let h = LibraryHandle::open(path, false).unwrap();
        assert_eq!(h.photo_info(id).unwrap().rating, 4);
        h.close().unwrap();
    }
    let _ = std::fs::remove_dir_all(&dir);
}
