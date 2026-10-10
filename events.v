module main

import gg
import time
import sokol.sapp

// gg passes the user data first for on_event, event_fn takes it last.
// Using on_event with the wrong signature made `e` point at the Ved struct.
fn ved_event(e &gg.Event, data voidptr) {
	mut ved := unsafe { &Ved(data) }
	ved.on_event(e)
}

const double_click_ms = 400

// sync_window_size reads the window size in drawing units. The resize event carries
// real pixels, which are bigger on HiDPI screens and pushed the right side of the UI
// (branch widget, status bar) out of the window.
fn (mut ved Ved) sync_window_size() {
	size := gg.window_size()
	if size.width > 0 && size.height > 0 {
		ved.win_width = size.width
		ved.win_height = size.height
	}
}

fn (mut ved Ved) on_event(e &gg.Event) {
	// println('on_event ${ved.win_width}')
	ved.refresh = true
	if e.typ == .resized {
		ved.sync_window_size()
	}
	if ved.cfg.disable_mouse {
		return
	}
	mx := int(e.mouse_x)
	my := int(e.mouse_y)
	if e.typ in [.mouse_move, .mouse_down, .mouse_up, .mouse_scroll] {
		ved.mouse_x = mx
		ved.mouse_y = my
	}
	match e.typ {
		.mouse_scroll {
			lines := if e.scroll_y < -0.2 {
				3
			} else if e.scroll_y > 0.2 {
				-3
			} else {
				0
			}
			if ved.menu_open >= 0 {
				return
			}
			if mx < ved.tree_width() {
				if ved.left_panel == .project {
					ved.tree.scroll_by(lines, ved.tree_rows())
				} else {
					ved.commit_scroll = int_max(ved.commit_scroll + lines, 0)
				}
			} else {
				ved.focus_split_at(mx)
				mut view := ved.view
				view.from += lines
				if view.from > view.lines.len - 1 {
					view.from = view.lines.len - 1
				}
				if view.from < 0 {
					view.from = 0
				}
			}
		}
		.mouse_down {
			if ved.menu_mouse_down(mx, my) {
				return
			}
			if ved.mode in [.query, .autocomplete] {
				ved.mode = .edit
			}
			ved.on_mouse_down(mx, my, e.mouse_button, unsafe { gg.Modifier(e.modifiers) })
		}
		.mouse_move {
			in_text := mx >= ved.tree_width() && my >= ved.text_top()
				&& my < ved.win_height - ved.status_bar_height()
			sapp.set_mouse_cursor(if in_text { .ibeam } else { .default })
			ved.tree_hover_at(mx, my)
			ved.menu_mouse_move(mx, my)
			if ved.dragging {
				ved.move_cursor_to(mx, my)
			}
		}
		.mouse_up {
			ved.dragging = false
		}
		.mouse_leave {
			ved.tree.hover = -1
		}
		else {}
	}
}

fn (mut ved Ved) on_mouse_down(mx int, my int, button gg.MouseButton, mod gg.Modifier) {
	if mx < ved.tree_width() {
		if button == .left {
			ved.panel_click(mx, my)
		}
		return
	}
	ved.commit_focus = false
	if my < ved.tab_bar_bottom() {
		ved.tab_click(mx, button)
		return
	}
	if my >= ved.win_height - ved.status_bar_height() || button != .left {
		return
	}
	ved.focus_split_at(mx)
	mut view := ved.view
	shift := mod.has(.shift)
	if shift {
		view.start_sel()
	} else {
		view.clear_sel()
	}
	ved.move_cursor_to(mx, my)
	now := time.ticks()
	if !shift && now - ved.last_click_ms < double_click_ms && ved.last_click_x == view.x
		&& ved.last_click_y == view.y {
		view.select_word()
		ved.last_click_ms = 0
		return
	}
	ved.last_click_ms = now
	ved.last_click_x = view.x
	ved.last_click_y = view.y
	if mod.has(.ctrl) || mod.has(.super) {
		ved.go_to_def()
		return
	}
	if !shift {
		view.start_sel() // anchor for dragging, an empty selection is not drawn
	}
	ved.dragging = true
}

// focus_split_at makes the split under the given x position the current one.
fn (mut ved Ved) focus_split_at(mx int) {
	from, to := ved.get_splits_from_to()
	sw := ved.split_width()
	for i := from; i < to; i++ {
		x := ved.split_x(i - from)
		if mx >= x && mx < x + sw && ved.cur_split != i {
			ved.cur_split = i
			ved.update_view()
			ved.update_cur_fn_name()
			break
		}
	}
}

// move_cursor_to puts the cursor at the character under a screen position.
fn (mut ved Ved) move_cursor_to(mx int, my int) {
	mut view := ved.view
	if view.lines.len == 0 {
		return
	}
	from, _ := ved.get_splits_from_to()
	mut y := view.from + (my - ved.text_top()) / ved.cfg.line_height
	if my < ved.text_top() {
		y = view.from - 1
	}
	if y >= view.lines.len {
		y = view.lines.len - 1
	}
	if y < 0 {
		y = 0
	}
	view.set_y(y)
	line_x := ved.split_x(ved.cur_split - from) + view.padding_left + 10
	col := (mx - line_x + ved.cfg.char_width / 2) / ved.cfg.char_width
	view.x = if col <= 0 { 0 } else { x_for_col(view.line(), col, ved.cfg.tab_size) }
	view.want_col = -1
	view.last_edit = .none
	view.ensure_visible()
}

fn key_down(key gg.KeyCode, mod gg.Modifier, mut ved Ved) {
	if ved.menu_open >= 0 {
		ved.key_menu(key)
		ved.gg.refresh_ui()
		return
	}
	if ved.commit_focus && ved.mode == .edit && ved.key_commit_msg(key, mod) {
		ved.gg.refresh_ui()
		return
	}
	if key == .escape && ved.mode != .edit {
		ved.mode = .edit
		ved.gg.refresh_ui()
		return
	}
	// Reset error line
	ved.view.error_y = -1
	ved.error_line = ''
	match ved.mode {
		.edit, .autocomplete, .debugger { ved.key_edit(key, mod) }
		.query { ved.key_query(key, mod.has(.super) || mod.has(.ctrl)) }
		.timer { ved.timer.key_down(key, mod.has(.super)) }
	}
	ved.gg.refresh_ui()
}

@[manualfree]
fn on_char(code u32, mut ved Ved) {
	if ved.just_switched {
		ved.just_switched = false
		return
	}
	// Shortcuts are handled in key_down. Ctrl+Alt is let through, that's AltGr on Windows.
	mods := ved.gg.key_modifiers
	ctrl := mods.has(.ctrl)
	alt := mods.has(.alt)
	if mods.has(.super) || ctrl != alt {
		return
	}
	// control chars, X11 also sends backspace/tab/enter/delete as chars
	if code < 32 || code == 127 {
		return
	}
	mut buf := [5]u8{}
	s := unsafe { utf32_to_str_no_malloc(code, mut &buf[0]) }
	if ved.menu_open >= 0 {
		return
	}
	match ved.mode {
		.edit, .autocomplete, .debugger {
			if ved.commit_focus {
				ved.commit_msg += s
			} else {
				ved.type_text(s)
			}
		}
		.query {
			ved.gg_pos = -1
			ved.char_query(s)
		}
		else {}
	}
}
