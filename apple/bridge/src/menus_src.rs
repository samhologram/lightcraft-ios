//! Parsers for the desktop UI's command table and menu layout, read from upstream source text
//! (`crates/ui-egui/src/menus.rs` and `menubar.rs`) embedded with `include_str!`. No egui dependency.
//! Robust by construction: every access is bounds-checked and malformed input yields fewer entries.

use crate::{MenuSection, UiCommandInfo};

const MENUS_RS: &str = include_str!("../../../crates/ui-egui/src/menus.rs");
const MENUBAR_RS: &str = include_str!("../../../crates/ui-egui/src/menubar.rs");

#[derive(Debug, PartialEq)]
enum Tok {
    Str(String),
    Sym(char),
    Word(String),
}

/// Tokenize Rust source: string literals (with simple escapes), single punctuation chars and words.
/// Comments (`//`, `/* */`) are dropped; char literals and lifetimes are treated as punctuation.
fn tokenize(src: &str) -> Vec<Tok> {
    let c: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while let Some(&ch) = c.get(i) {
        if ch == '/' && c.get(i + 1) == Some(&'/') {
            while c.get(i).is_some_and(|x| *x != '\n') {
                i += 1;
            }
        } else if ch == '/' && c.get(i + 1) == Some(&'*') {
            i += 2;
            while i < c.len() && !(c.get(i) == Some(&'*') && c.get(i + 1) == Some(&'/')) {
                i += 1;
            }
            i += 2;
        } else if ch == '"' {
            let mut s = String::new();
            i += 1;
            while let Some(&x) = c.get(i) {
                if x == '"' {
                    break;
                }
                if x == '\\' {
                    i += 1;
                    match c.get(i) {
                        Some('n') => s.push('\n'),
                        Some('t') => s.push('\t'),
                        Some(&o) => s.push(o),
                        None => break,
                    }
                } else {
                    s.push(x);
                }
                i += 1;
            }
            i += 1;
            out.push(Tok::Str(s));
        } else if ch.is_alphanumeric() || ch == '_' {
            let mut w = String::new();
            while let Some(&x) = c.get(i) {
                if x.is_alphanumeric() || x == '_' {
                    w.push(x);
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(Tok::Word(w));
        } else {
            if !ch.is_whitespace() {
                out.push(Tok::Sym(ch));
            }
            i += 1;
        }
    }
    out
}

/// Index just past the `=` that follows `name` in a `const NAME ... = ` declaration.
fn after_decl(toks: &[Tok], name: &str) -> Option<usize> {
    let at = toks.iter().position(|t| matches!(t, Tok::Word(w) if w == name))?;
    // must be a declaration: preceded by `const`
    if !matches!(at.checked_sub(1).and_then(|p| toks.get(p)), Some(Tok::Word(w)) if w == "const") {
        // keep searching for a later occurrence
        let rest = toks.get(at + 1..)?;
        return after_decl(rest, name).map(|p| p + at + 1);
    }
    let eq = toks.get(at..)?.iter().position(|t| matches!(t, Tok::Sym('=')))?;
    Some(at + eq + 1)
}

/// Every UI command declared in `UI_COMMANDS` (LANGUAGE_COMMANDS are skipped; entries whose label is
/// not a string literal are skipped).
pub fn parse_ui_commands(src: &str) -> Vec<UiCommandInfo> {
    let toks = tokenize(src);
    let Some(start) = after_decl(&toks, "UI_COMMANDS") else { return Vec::new() };
    let mut out = Vec::new();
    let mut depth = 0usize; // bracket depth relative to the outer `&[`
    let mut i = start;
    // entry tuples: `(` Str `,` Str `,` (None | Some `(` Str `)`) `,` Str `)`
    while let Some(t) = toks.get(i) {
        match t {
            Tok::Sym('[') => depth += 1,
            Tok::Sym(']') => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    break;
                }
            }
            Tok::Sym(';') if depth == 0 => break,
            Tok::Sym('(') if depth == 1 => {
                if let Some((cmd, next)) = parse_entry(&toks, i) {
                    out.push(cmd);
                    i = next;
                    continue;
                }
            }
            _ => {}
        }
        i += 1;
    }
    out
}

fn parse_entry(toks: &[Tok], open: usize) -> Option<(UiCommandInfo, usize)> {
    let get = |k: usize| toks.get(open + k);
    let Some(Tok::Str(id)) = get(1) else { return None };
    let Some(Tok::Sym(',')) = get(2) else { return None };
    let Some(Tok::Str(label)) = get(3) else { return None };
    let Some(Tok::Sym(',')) = get(4) else { return None };
    let (shortcut, k) = match get(5) {
        Some(Tok::Word(w)) if w == "None" => (None, 6),
        Some(Tok::Word(w)) if w == "Some" => match (get(6), get(7), get(8)) {
            (Some(Tok::Sym('(')), Some(Tok::Str(s)), Some(Tok::Sym(')'))) => (Some(s.clone()), 9),
            _ => return None,
        },
        _ => return None,
    };
    let Some(Tok::Sym(',')) = get(k) else { return None };
    let Some(Tok::Str(menu)) = get(k + 1) else { return None };
    let Some(Tok::Sym(')')) = get(k + 2) else { return None };
    let menu: Vec<String> = menu.split('>').map(str::trim).filter(|s| !s.is_empty()).map(str::to_string).collect();
    Some((UiCommandInfo { id: id.clone(), label: label.clone(), shortcut, menu }, open + k + 3))
}

/// Strings between the first `[` after `name`'s `=` and its matching `]`.
fn string_list(toks: &[Tok], name: &str) -> Vec<String> {
    let Some(start) = after_decl(toks, name) else { return Vec::new() };
    let mut out = Vec::new();
    let mut depth = 0usize;
    for t in toks.get(start..).unwrap_or(&[]) {
        match t {
            Tok::Sym('[') => depth += 1,
            Tok::Sym(']') => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    break;
                }
            }
            Tok::Str(s) if depth == 1 => out.push(s.clone()),
            Tok::Sym(';') if depth == 0 => break,
            _ => {}
        }
    }
    out
}

/// The menu bar: `MENUS` order with each menu's `LAYOUT` items.
pub fn parse_menu_layout(src: &str) -> Vec<MenuSection> {
    let toks = tokenize(src);
    let titles = string_list(&toks, "MENUS");
    let mut layouts: Vec<(String, Vec<String>)> = Vec::new();
    if let Some(start) = after_decl(&toks, "LAYOUT") {
        let mut depth = 0usize;
        let mut title: Option<String> = None;
        let mut items: Vec<String> = Vec::new();
        for t in toks.get(start..).unwrap_or(&[]) {
            match t {
                Tok::Sym('[') => depth += 1,
                Tok::Sym(']') => {
                    depth = depth.saturating_sub(1);
                    if depth == 1
                        && let Some(tt) = title.take()
                    {
                        layouts.push((tt, std::mem::take(&mut items)));
                    }
                    if depth == 0 {
                        break;
                    }
                }
                Tok::Str(s) if depth == 1 && title.is_none() => title = Some(s.clone()),
                Tok::Str(s) if depth == 2 => items.push(s.clone()),
                Tok::Sym(';') if depth == 0 => break,
                _ => {}
            }
        }
    }
    titles
        .into_iter()
        .map(|title| {
            let items = layouts.iter().find(|(t, _)| *t == title).map(|(_, i)| i.clone()).unwrap_or_default();
            MenuSection { title, items }
        })
        .collect()
}

/// UI-only desktop commands, from the embedded upstream source.
pub fn ui_commands() -> Vec<UiCommandInfo> {
    parse_ui_commands(MENUS_RS)
}

/// The desktop menu bar, from the embedded upstream source.
pub fn menu_layout() -> Vec<MenuSection> {
    parse_menu_layout(MENUBAR_RS)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]
mod tests {
    use super::*;

    #[test]
    fn parses_ui_commands() {
        let src = r#"
pub const LANGUAGE_COMMANDS: &[UiCommand] = &[("app.language.x", crate::i18n::X, None, "Edit>Language")];
pub const UI_COMMANDS: &[UiCommand] = &[
    // comment ("fake", "x", None, "")
    ("view.a", "A \"q\"", Some("Cmd+A"), "Window>Tools"),
    ("view.b", crate::i18n::B, None, "View"),
    ("view.c", "C", None, ""),
];"#;
        let v = parse_ui_commands(src);
        let ids: Vec<&str> = v.iter().map(|c| c.id.as_str()).collect();
        assert_eq!(ids, ["view.a", "view.c"]);
        assert_eq!(v[0].menu, ["Window", "Tools"]);
        assert_eq!(v[0].shortcut.as_deref(), Some("Cmd+A"));
        assert_eq!(v[0].label, "A \"q\"");
        assert!(v[1].menu.is_empty());
    }

    #[test]
    fn parses_menu_layout() {
        let src = r#"
pub const MENUS: &[&str] = &["File", "Edit", "Nope"];
const LAYOUT: &[(&str, &[&str])] = &[
    ("File", &["a.b", "---", "@Sub"]),
    (
        "Edit",
        &[
            "c.d",
        ],
    ),
];"#;
        let v = parse_menu_layout(src);
        assert_eq!(v.len(), 3);
        assert_eq!(v[0].title, "File");
        assert_eq!(v[0].items, ["a.b", "---", "@Sub"]);
        assert_eq!(v[1].items, ["c.d"]);
        assert!(v[2].items.is_empty());
    }

    #[test]
    fn garbage_never_panics() {
        for s in ["", "\"", "/*", "const UI_COMMANDS = [(", "const LAYOUT = &[(\"a\", &[", "\\", "const MENUS = ["] {
            let _ = parse_ui_commands(s);
            let _ = parse_menu_layout(s);
        }
    }

    #[test]
    fn real_sources() {
        let ui = ui_commands();
        assert!(ui.len() > 100, "{}", ui.len());
        assert!(ui.iter().any(|c| c.id == "panel.edit"));
        let brush = ui.iter().find(|c| c.id == "tool.brush").unwrap();
        assert_eq!(brush.menu, ["Window", "Tools"]);
        let m = menu_layout();
        assert_eq!(m.first().map(|s| s.title.as_str()), Some("File"));
        assert!(m.iter().all(|s| !s.items.is_empty()));
    }
}
