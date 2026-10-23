//! Prints the command catalog and UI command table: `cargo run --example dump -- engine|ui|menus`.
//! Used by the scripts in `apple/scripts`.
fn main() {
    let what = std::env::args().nth(1).unwrap_or_default();
    match what.as_str() {
        "engine" => {
            for c in lightcraft_apple::command_catalog() {
                println!("{}\t{}\t{}\t{}", c.id, c.label, c.menu.join(">"), c.params.replace(['\n', '\t'], " "));
            }
        }
        "ui" => {
            for c in lightcraft_apple::ui_command_catalog() {
                println!("{}\t{}\t{}", c.id, c.label, c.menu.join(">"));
            }
        }
        "menus" => {
            for m in lightcraft_apple::desktop_menu_layout() {
                println!("{}\t{}", m.title, m.items.join(" "));
            }
        }
        _ => eprintln!("usage: dump engine|ui|menus"),
    }
}
