// The tray port of TramBar for Windows and Linux. The tray shows the next
// departure (as title where the desktop supports it, always as tooltip); a left
// click opens the panel next to it. Data fetching and the panel live in ../ui.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WindowEvent,
};
use tauri_plugin_positioner::{Position, WindowExt};

const TRAY: &str = "main";

fn settings_path(app: &AppHandle) -> std::path::PathBuf {
    let dir = app.path().app_config_dir().expect("no config dir");
    let _ = fs::create_dir_all(&dir);
    dir.join("settings.json")
}

/// Same settings.json format as the macOS app, so a copied file just works.
#[tauri::command]
fn load_settings(app: AppHandle) -> String {
    fs::read_to_string(settings_path(&app)).unwrap_or_else(|_| "{}".into())
}

#[tauri::command]
fn save_settings(app: AppHandle, json: String) -> Result<(), String> {
    let path = settings_path(&app);
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, json).and_then(|_| fs::rename(&tmp, &path)).map_err(|e| e.to_string())
}

/// "2 · 4 min". Windows trays have no text, so it also goes in the tooltip.
#[tauri::command]
fn set_tray(app: AppHandle, title: Option<String>) {
    if let Some(tray) = app.tray_by_id(TRAY) {
        let _ = tray.set_tooltip(Some(title.clone().map_or("TramBar".into(), |t| format!("TramBar · {t}"))));
        #[cfg(not(target_os = "windows"))]
        let _ = tray.set_title(title);
    }
}

#[tauri::command]
fn quit(app: AppHandle) {
    app.exit(0);
}

fn toggle_panel(app: &AppHandle) {
    let Some(win) = app.get_webview_window("panel") else { return };
    if win.is_visible().unwrap_or(false) {
        let _ = win.hide();
    } else {
        // Linux trays often report no position; fall back to the top right corner.
        if win.move_window(Position::TrayCenter).is_err() {
            let _ = win.move_window(Position::TopRight);
        }
        let _ = win.show();
        let _ = win.set_focus();
        let _ = win.eval("window.onPanelShown && window.onPanelShown()");
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .invoke_handler(tauri::generate_handler![load_settings, save_settings, set_tray, quit])
        .setup(|app| {
            let open = MenuItem::with_id(app, "open", "Show departures", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit TramBar", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &quit])?;
            TrayIconBuilder::with_id(TRAY)
                .icon(tauri::include_image!("icons/tray.png"))
                .tooltip("TramBar")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "open" => toggle_panel(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, e| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &e);
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                        toggle_panel(tray.app_handle());
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|win, e| {
            // Behave like a tray popover: clicking elsewhere closes it.
            if let WindowEvent::Focused(false) = e {
                let _ = win.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running TramBar");
}
