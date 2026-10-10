module main

import os
import gg

// TabRect is where a tab ended up on screen during the last frame.
struct TabRect {
	path    string
	x       int
	w       int
	close_x int // left edge of the close button
}

const tab_padding = 12
const tab_close_size = 8

fn (ved &Ved) tabs() []string {
	if ved.workspace_idx >= ved.open_paths.len {
		return []string{}
	}
	return ved.open_paths[ved.workspace_idx]
}

fn (mut ved Ved) draw_tab_bar() {
	x0 := ved.tree_width()
	top := ved.content_top()
	h := ved.tab_bar_height()
	ved.gg.draw_rect_filled(x0, top, ved.win_width - x0, h, ved.cfg.panel_color)
	ved.gg.draw_line(x0, top + h, ved.win_width, top + h, ved.cfg.split_color)
	ved.tab_rects.clear()
	tabs := ved.tabs()
	if tabs.len == 0 {
		return
	}
	cw := ved.cfg.char_width
	mut widths := []int{cap: tabs.len}
	mut active := -1
	for i, path in tabs {
		label_len := os.base(path).runes().len + 2 // "* " marker space
		widths << tab_padding * 3 + label_len * cw + tab_close_size + tree_icon_size + 6
		if path == ved.view.path {
			active = i
		}
	}
	// Too many tabs to fit? Start from a later one so the active tab stays visible
	avail := ved.win_width - x0
	mut first := 0
	if active > 0 {
		mut total := 0
		for i := active; i >= 0; i-- {
			total += widths[i]
			if total > avail {
				first = i + 1
				break
			}
		}
	}
	text_y := top + (h - ved.cfg.line_height) / 2
	mut x := x0
	for i := first; i < tabs.len; i++ {
		if x >= ved.win_width {
			break
		}
		path := tabs[i]
		w := widths[i]
		if i == active {
			ved.gg.draw_rect_filled(x, top, w, h, ved.cfg.bgcolor)
			ved.gg.draw_rect_filled(x, top + h - 3, w, 3, ved.cfg.accent_color)
		}
		label := if ved.is_modified(path) { '*' + os.base(path) } else { os.base(path) }
		kind := ved.git_kind_of(path)
		cfg := if kind != .none {
			ved.git_text_cfg(kind)
		} else if i == active {
			ved.cfg.txt_cfg
		} else {
			ved.cfg.dim_cfg
		}
		ved.draw_file_icon(x + tab_padding, top + (h - tree_icon_size) / 2, path)
		ved.gg.draw_text(x + tab_padding + tree_icon_size + 6, text_y, label, cfg)
		// close button, a small x
		cx := x + w - tab_padding - tab_close_size
		cy := top + (h - tab_close_size) / 2
		ved.gg.draw_line(cx, cy, cx + tab_close_size, cy + tab_close_size, ved.cfg.dim_cfg.color)
		ved.gg.draw_line(cx, cy + tab_close_size, cx + tab_close_size, cy, ved.cfg.dim_cfg.color)
		ved.gg.draw_line(x + w, top + 4, x + w, top + h - 4, ved.cfg.split_color)
		ved.tab_rects << TabRect{
			path:    path
			x:       x
			w:       w
			close_x: cx - 4
		}
		x += w
	}
}

fn (mut ved Ved) tab_click(mx int, button gg.MouseButton) {
	for r in ved.tab_rects {
		if mx < r.x || mx >= r.x + r.w {
			continue
		}
		if button == .middle || (button == .left && mx >= r.close_x) {
			ved.close_tab(r.path)
		} else if button == .left {
			ved.open_tab(r.path)
		}
		return
	}
}

fn (mut ved Ved) open_tab(path string) {
	if path == ved.view.path {
		return
	}
	ved.view.open_file(path, 0)
	ved.view.ensure_visible()
}

// next_tab moves to the tab `delta` places away from the current one, wrapping around.
fn (mut ved Ved) next_tab(delta int) {
	tabs := ved.tabs()
	if tabs.len == 0 {
		return
	}
	cur := tabs.index(ved.view.path)
	mut i := (cur + delta) % tabs.len
	if i < 0 {
		i += tabs.len
	}
	ved.open_tab(tabs[i])
}

// close_tab removes a tab. Unsaved edits are written to disk first, nothing gets lost
// by closing a tab, same as IntelliJ.
fn (mut ved Ved) close_tab(path string) {
	if path == '' {
		return
	}
	mut tabs := ved.open_paths[ved.workspace_idx]
	idx := tabs.index(path)
	if buf := ved.stash[path] {
		save := if ved.cfg.atomic_save { write_lines_atomic } else { write_lines }
		save(path, buf.lines) or {
			ved.error_line = 'cannot save ${path}: ${err.msg()}'
			return
		}
		ved.stash.delete(path)
	}
	if path == ved.view.path {
		if ved.view.changed {
			ved.view.save_file()
			if ved.error_line != '' {
				return
			}
		}
		// the neighbour on the right takes its place, or the one on the left at the end
		mut next := ''
		if idx >= 0 && tabs.len > 1 {
			next = if idx + 1 < tabs.len { tabs[idx + 1] } else { tabs[idx - 1] }
		}
		if next != '' {
			ved.view.open_file(next, 0)
		} else {
			mut view := ved.view
			view.file_y_pos_save()
			view.path = ''
			view.short_path = ''
			view.lines = ['']
			view.x = 0
			view.y = 0
			view.from = 0
			view.sel_y = -1
			view.changed = false
			view.undo_stack = []
			view.redo_stack = []
		}
	}
	// open_file may have added tabs, look the index up again
	tabs = ved.open_paths[ved.workspace_idx]
	i := tabs.index(path)
	if i >= 0 {
		ved.open_paths[ved.workspace_idx].delete(i)
	}
	ved.save_session()
}

fn (mut view View) file_y_pos_save() {
	if view.path != '' {
		view.ved.file_y_pos[view.path] = view.y
	}
}
