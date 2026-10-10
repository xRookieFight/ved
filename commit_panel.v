module main

import gg
import os
import time

// The left side panel switches between the project tree and the commit tool
// window, the same way IntelliJ's left tool window stripe does.
enum LeftPanel {
	project
	commit
}

// Hit is a clickable area remembered from the last frame.
struct Hit {
	kind string
	idx  int
	x    int
	y    int
	w    int
	h    int
}

fn (h Hit) contains(x int, y int) bool {
	return x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h
}

const commit_msg_lines = 5

fn (ved &Ved) git_color(kind GitKind) gg.Color {
	return match kind {
		.modified, .renamed { ved.cfg.git_modified_color }
		.added { ved.cfg.git_added_color }
		.untracked { ved.cfg.git_untracked_color }
		.deleted { ved.cfg.line_nr_color }
		.conflict { gg.rgb(220, 80, 80) }
		.none { ved.cfg.text_color }
	}
}

fn (ved &Ved) git_text_cfg(kind GitKind) gg.TextCfg {
	if kind == .none {
		return ved.cfg.txt_cfg
	}
	return gg.TextCfg{
		...ved.cfg.txt_cfg
		color: ved.git_color(kind)
	}
}

// draw_left_panel draws the panel background and its Project / Commit header tabs.
fn (mut ved Ved) draw_left_panel() {
	w := ved.tree_width()
	top := ved.content_top()
	header_h := ved.tab_bar_height()
	bottom := ved.win_height - ved.status_bar_height()
	ved.gg.draw_rect_filled(0, top, w, bottom - top, ved.cfg.panel_color)
	ved.gg.draw_line(w, top, w, bottom, ved.cfg.split_color)
	ved.panel_hits.clear()
	cw := ved.cfg.char_width
	mut x := 8
	text_y := top + (header_h - ved.cfg.line_height) / 2
	n := ved.git.files.len
	titles := ['Project', if n > 0 { 'Commit ${n}' } else { 'Commit' }]
	for i, title in titles {
		tw := title.len * cw + 16
		active := int(ved.left_panel) == i
		if active {
			ved.gg.draw_rounded_rect_filled(x, top + 5, tw, header_h - 10, 4, ved.cfg.hover_color)
		}
		ved.gg.draw_text(x + 8, text_y, title, if active {
			ved.cfg.txt_cfg
		} else {
			ved.cfg.dim_cfg
		})
		ved.panel_hits << Hit{'panel_tab', i, x, top, tw, header_h}
		x += tw + 4
	}
	ved.gg.draw_line(0, top + header_h, w, top + header_h, ved.cfg.split_color)
	if ved.left_panel == .project {
		ved.tree.draw(mut ved)
	} else {
		ved.draw_commit_panel()
	}
}

fn (mut ved Ved) draw_checkbox(x int, y int, checked bool) {
	s := 12
	if checked {
		ved.gg.draw_rounded_rect_filled(x, y, s, s, 3, ved.cfg.accent_color)
		ved.gg.draw_line(x + 3, y + 6, x + 5, y + 9, gg.white)
		ved.gg.draw_line(x + 5, y + 9, x + 10, y + 3, gg.white)
	} else {
		ved.gg.draw_rounded_rect_filled(x, y, s, s, 3, ved.cfg.dim_cfg.color)
		ved.gg.draw_rounded_rect_filled(x + 1, y + 1, s - 2, s - 2, 2, ved.cfg.panel_color)
	}
}

// draw_button draws a rounded button, `primary` is the filled blue one.
fn (mut ved Ved) draw_button(x int, y int, label string, primary bool) int {
	w := label.len * ved.cfg.char_width + 24
	h := ved.cfg.line_height + 8
	if primary {
		ved.gg.draw_rounded_rect_filled(x, y, w, h, 5, ved.cfg.accent_color)
		ved.gg.draw_text(x + 12, y + 4, label, gg.TextCfg{
			...ved.cfg.txt_cfg
			color: gg.white
		})
	} else {
		ved.gg.draw_rounded_rect_filled(x, y, w, h, 5, ved.cfg.split_color)
		ved.gg.draw_rounded_rect_filled(x + 1, y + 1, w - 2, h - 2, 4, ved.cfg.panel_color)
		ved.gg.draw_text(x + 12, y + 4, label, ved.cfg.txt_cfg)
	}
	return w
}

fn (mut ved Ved) draw_commit_panel() {
	w := ved.tree_width()
	lh := ved.cfg.line_height
	cw := ved.cfg.char_width
	row_h := ved.tree_row_height()
	bottom := ved.win_height - ved.status_bar_height()
	mut y := ved.tab_bar_bottom() + 4
	if !ved.git.ok {
		ved.gg.draw_text(12, y + 8, 'Not a git repository', ved.cfg.dim_cfg)
		return
	}
	// bottom part: message box, amend, buttons
	btn_h := lh + 8
	msg_h := commit_msg_lines * lh + 12
	btn_y := bottom - btn_h - 10
	amend_y := btn_y - row_h - 4
	msg_y := amend_y - msg_h - 6
	list_bottom := msg_y - 8

	// "Changes" group row with a checkbox for everything
	files := ved.git.files
	nr_checked := files.filter(it.path !in ved.commit_excluded).len
	ved.draw_checkbox(12, y + (row_h - 12) / 2, nr_checked == files.len && files.len > 0)
	ved.panel_hits << Hit{'check_all', 0, 0, y, 30, row_h}
	ved.gg.draw_text(32, y + (row_h - lh) / 2, 'Changes', ved.cfg.txt_cfg)
	count := '${files.len} file' + if files.len == 1 { '' } else { 's' }
	ved.gg.draw_text(32 + 8 * cw + 8, y + (row_h - lh) / 2, count, ved.cfg.dim_cfg)
	y += row_h
	max_rows := (list_bottom - y) / row_h
	if ved.commit_scroll > files.len - max_rows {
		ved.commit_scroll = int_max(files.len - max_rows, 0)
	}
	for r := 0; r < max_rows && ved.commit_scroll + r < files.len; r++ {
		i := ved.commit_scroll + r
		f := files[i]
		ry := y + r * row_h
		if f.path == ved.view.path {
			ved.gg.draw_rect_filled(0, ry, w, row_h, ved.cfg.active_color)
		} else if ved.mouse_x < w && ved.mouse_y >= ry && ved.mouse_y < ry + row_h {
			ved.gg.draw_rect_filled(0, ry, w, row_h, ved.cfg.hover_color)
		}
		ved.draw_checkbox(28, ry + (row_h - 12) / 2, f.path !in ved.commit_excluded)
		ved.panel_hits << Hit{'check', i, 20, ry, 26, row_h}
		ved.draw_file_icon(48, ry + (row_h - tree_icon_size) / 2, f.rel)
		name := os.base(f.rel)
		tx := 66
		max_chars := (w - tx - 8) / cw
		if max_chars > 0 {
			shown := if name.runes().len > max_chars {
				name.runes()[..max_chars].string()
			} else {
				name
			}
			ved.gg.draw_text(tx, ry + (row_h - lh) / 2, shown, ved.git_text_cfg(f.kind))
			dir := os.dir(f.rel)
			rest := max_chars - name.runes().len - 2
			if dir != '.' && rest > 3 {
				d := if dir.runes().len > rest {
					dir.runes()[..rest - 1].string() + '…'
				} else {
					dir
				}
				ved.gg.draw_text(tx + (name.runes().len + 2) * cw, ry + (row_h - lh) / 2, d,
					ved.cfg.dim_cfg)
			}
		}
		ved.panel_hits << Hit{'file', i, 46, ry, w - 46, row_h}
	}
	if files.len == 0 {
		ved.gg.draw_text(32, y + 6, 'No changes', ved.cfg.dim_cfg)
	}

	// message box
	box_x := 8
	box_w := w - 16
	border := if ved.commit_focus { ved.cfg.accent_color } else { ved.cfg.split_color }
	ved.gg.draw_rounded_rect_filled(box_x - 1, msg_y - 1, box_w + 2, msg_h + 2, 5, border)
	ved.gg.draw_rounded_rect_filled(box_x, msg_y, box_w, msg_h, 4, ved.cfg.bgcolor)
	ved.panel_hits << Hit{'msg', 0, box_x, msg_y, box_w, msg_h}
	max_chars := (box_w - 16) / cw
	if ved.commit_msg == '' && !ved.commit_focus {
		ved.gg.draw_text(box_x + 8, msg_y + 6, 'Commit Message', ved.cfg.dim_cfg)
	} else {
		lines := ved.commit_msg.split('\n')
		// keep the end of the message visible, that's where typing happens
		first := int_max(lines.len - commit_msg_lines, 0)
		for j := first; j < lines.len; j++ {
			mut l := lines[j]
			if l.runes().len > max_chars {
				l = '…' + l.runes()[l.runes().len - max_chars + 1..].string()
			}
			ved.gg.draw_text(box_x + 8, msg_y + 6 + (j - first) * lh, l, ved.cfg.txt_cfg)
		}
		if ved.commit_focus {
			last := lines.last()
			cx := box_x + 8 + int_min(last.runes().len, max_chars) * cw
			cy := msg_y + 6 + (lines.len - 1 - first) * lh
			ved.gg.draw_rect_filled(cx, cy, 2, lh, ved.cfg.cursor_color)
		}
	}

	// amend checkbox
	ved.draw_checkbox(12, amend_y + (row_h - 12) / 2, ved.commit_amend)
	ved.gg.draw_text(32, amend_y + (row_h - lh) / 2, 'Amend', ved.cfg.txt_cfg)
	ved.panel_hits << Hit{'amend', 0, 8, amend_y, 8 * cw + 30, row_h}

	// buttons
	bw := ved.draw_button(8, btn_y, 'Commit', true)
	ved.panel_hits << Hit{'commit', 0, 8, btn_y, bw, btn_h}
	if 8 + bw + 8 + 18 * cw < w {
		pw := ved.draw_button(8 + bw + 8, btn_y, 'Commit and Push', false)
		ved.panel_hits << Hit{'commit_push', 0, 8 + bw + 8, btn_y, pw, btn_h}
	}
}

// panel_click handles clicks on the left panel, project tree or commit window.
fn (mut ved Ved) panel_click(mx int, my int) {
	mut hit := Hit{}
	for h in ved.panel_hits {
		if h.contains(mx, my) {
			hit = h
			break
		}
	}
	if hit.kind == 'panel_tab' {
		ved.left_panel = unsafe { LeftPanel(hit.idx) }
		ved.commit_focus = false
		return
	}
	if ved.left_panel == .project {
		ved.commit_focus = false
		ved.tree_click(my)
		return
	}
	ved.commit_focus = hit.kind == 'msg'
	files := ved.git.files
	match hit.kind {
		'check_all' {
			if files.filter(it.path !in ved.commit_excluded).len == files.len {
				for f in files {
					ved.commit_excluded[f.path] = true
				}
			} else {
				ved.commit_excluded.clear()
			}
		}
		'check' {
			path := files[hit.idx].path
			if path in ved.commit_excluded {
				ved.commit_excluded.delete(path)
			} else {
				ved.commit_excluded[path] = true
			}
		}
		'file' {
			f := files[hit.idx]
			now := time.ticks()
			// double click shows the diff, single click opens the file
			if now - ved.last_panel_click < double_click_ms && ved.last_panel_idx == hit.idx {
				ved.git_show_diff(f.path)
				ved.last_panel_click = 0
			} else {
				ved.last_panel_click = now
				ved.last_panel_idx = hit.idx
				if f.kind != .deleted {
					ved.open_tab(f.path)
				}
			}
		}
		'amend' {
			ved.commit_amend = !ved.commit_amend
			if ved.commit_amend && ved.commit_msg == '' {
				// IntelliJ fills in the last message when amending
				res := git_exec(ved.git.root, ['log', '-1', '--pretty=%B'])
				if res.exit_code == 0 {
					ved.commit_msg = res.output.trim_space()
				}
			}
		}
		'commit' {
			ved.git_commit_selected(false)
		}
		'commit_push' {
			ved.git_commit_selected(true)
		}
		else {}
	}
}

// key_commit_msg edits the commit message. Returns false for keys it doesn't use,
// so global shortcuts like Ctrl+S keep working while typing a message.
fn (mut ved Ved) key_commit_msg(key gg.KeyCode, mod gg.Modifier) bool {
	ctrl := mod.has(.ctrl) || mod.has(.super)
	match key {
		.escape, .tab {
			ved.commit_focus = false
		}
		.enter {
			if ctrl {
				ved.git_commit_selected(mod.has(.alt))
			} else {
				ved.commit_msg += '\n'
			}
		}
		.k {
			if !ctrl {
				return false
			}
			ved.git_commit_selected(mod.has(.shift))
		}
		.backspace {
			mut r := ved.commit_msg.runes()
			if ctrl {
				for r.len > 0 && r.last() == ` ` {
					r.delete_last()
				}
				for r.len > 0 && r.last() != ` ` && r.last() != `\n` {
					r.delete_last()
				}
			} else if r.len > 0 {
				r.delete_last()
			}
			ved.commit_msg = r.string()
		}
		.v {
			if !ctrl {
				return false
			}
			ved.commit_msg += ved.cb.paste().replace('\r\n', '\n')
		}
		else {
			return !ctrl && !mod.has(.alt)
		}
	}
	return true
}
