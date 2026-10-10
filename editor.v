module main

import gg
import os
import time

const max_undo_steps = 300

// UndoState is a full copy of the line array. Strings are immutable, so the copy
// only duplicates the string headers, not the text itself.
struct UndoState {
	lines []string
	x     int
	y     int
}

// EditKind lets consecutive keystrokes of the same kind share one undo step,
// so undo removes a typed word instead of a single character.
enum EditKind {
	none
	typing
	deleting
	other
}

// Buffer holds the unsaved state of a file that was switched away from in its split.
struct Buffer {
	lines      []string
	x          int
	y          int
	from       int
	undo_stack []UndoState
	redo_stack []UndoState
}

fn (mut ved Ved) stash_view(view &View) {
	ved.stash[view.path] = Buffer{
		lines:      view.lines
		x:          view.x
		y:          view.y
		from:       view.from
		undo_stack: view.undo_stack
		redo_stack: view.redo_stack
	}
}

// is_modified reports unsaved changes for a path, whether it's on screen or stashed.
fn (ved &Ved) is_modified(path string) bool {
	if path in ved.stash {
		return true
	}
	from, to := ved.get_splits_from_to()
	for i := from; i < to && i < ved.views.len; i++ {
		if ved.views[i].path == path && ved.views[i].changed {
			return true
		}
	}
	return false
}

// save_all saves the current file and every stashed buffer (Ctrl+S).
fn (mut ved Ved) save_all() {
	ved.view.save_file()
	for path, buf in ved.stash {
		save := if ved.cfg.atomic_save { write_lines_atomic } else { write_lines }
		save(path, buf.lines) or {
			ved.error_line = 'cannot save ${path}: ${err.msg()}'
			continue
		}
		ved.stash.delete(path)
	}
}

fn (view &View) snapshot() UndoState {
	mut lines := []string{len: view.lines.len}
	copy(mut lines, view.lines)
	return UndoState{
		lines: lines
		x:     view.x
		y:     view.y
	}
}

// push_undo must be called right before the buffer is modified.
fn (mut view View) push_undo(kind EditKind) {
	view.edit_seq++
	view.last_edit_ms = time.ticks()
	if kind != .other && kind == view.last_edit && view.undo_stack.len > 0 {
		return
	}
	view.undo_stack << view.snapshot()
	if view.undo_stack.len > max_undo_steps {
		view.undo_stack.delete(0)
	}
	view.redo_stack.clear()
	view.last_edit = kind
}

fn (mut view View) restore(state UndoState) {
	view.edit_seq++
	view.last_edit_ms = time.ticks()
	view.lines = state.lines
	view.y = state.y
	view.x = state.x
	view.sel_y = -1
	view.last_edit = .none
	view.changed = true
	view.clamp_cursor()
}

fn (mut view View) undo() {
	if view.undo_stack.len == 0 {
		return
	}
	view.redo_stack << view.snapshot()
	view.restore(view.undo_stack.pop())
}

fn (mut view View) redo() {
	if view.redo_stack.len == 0 {
		return
	}
	view.undo_stack << view.snapshot()
	view.restore(view.redo_stack.pop())
}

// clamp_cursor keeps y inside the buffer and x inside the current line.
fn (mut view View) clamp_cursor() {
	if view.lines.len == 0 {
		view.lines << ''
	}
	if view.y >= view.lines.len {
		view.y = view.lines.len - 1
	}
	if view.y < 0 {
		view.y = 0
	}
	len := view.uline().len
	if view.x > len {
		view.x = len
	}
	if view.x < 0 {
		view.x = 0
	}
}

// ensure_visible scrolls just enough to keep the cursor on screen.
fn (mut view View) ensure_visible() {
	if view.page_height <= 0 {
		return
	}
	if view.y < view.from {
		view.from = view.y
	} else if view.y >= view.from + view.page_height {
		view.from = view.y - view.page_height + 1
	}
	if view.from < 0 {
		view.from = 0
	}
}

// visual_col converts a rune index into a screen column. Only leading tabs are
// expanded, that's how draw_split renders them.
fn visual_col(line string, x int, tab_size int) int {
	mut col := 0
	mut leading := true
	for i, r in line.runes() {
		if i >= x {
			break
		}
		if r == `\t` && leading {
			col += tab_size
		} else {
			leading = false
			col++
		}
	}
	return col
}

// x_for_col is the reverse of visual_col, it picks the rune index closest to a screen column.
fn x_for_col(line string, col int, tab_size int) int {
	mut cur := 0
	mut leading := true
	runes := line.runes()
	for i, r in runes {
		w := if r == `\t` && leading { tab_size } else { 1 }
		if r != `\t` {
			leading = false
		}
		if col < cur + (w + 1) / 2 {
			return i
		}
		cur += w
	}
	return runes.len
}

// Selection

fn (view &View) has_sel() bool {
	return view.sel_y >= 0 && !(view.sel_y == view.y && view.sel_x == view.x)
}

fn (mut view View) start_sel() {
	if view.sel_y < 0 {
		view.sel_y = view.y
		view.sel_x = view.x
	}
}

fn (mut view View) clear_sel() {
	view.sel_y = -1
}

// sel_bounds returns the selection ordered from top to bottom: y1, x1, y2, x2.
fn (view &View) sel_bounds() (int, int, int, int) {
	if view.sel_y < view.y || (view.sel_y == view.y && view.sel_x < view.x) {
		return view.sel_y, view.sel_x, view.y, view.x
	}
	return view.y, view.x, view.sel_y, view.sel_x
}

// sel_line_range returns the lines touched by the selection, or just the current line.
// A selection ending at column 0 doesn't include that last line, same as in IntelliJ.
fn (view &View) sel_line_range() (int, int) {
	if !view.has_sel() {
		return view.y, view.y
	}
	y1, _, y2, x2 := view.sel_bounds()
	if x2 == 0 && y2 > y1 {
		return y1, y2 - 1
	}
	return y1, y2
}

fn (view &View) selected_text() string {
	if !view.has_sel() {
		return ''
	}
	y1, x1, y2, x2 := view.sel_bounds()
	if y1 == y2 {
		return view.lines[y1].runes()[x1..x2].string()
	}
	mut parts := []string{cap: y2 - y1 + 1}
	parts << view.lines[y1].runes()[x1..].string()
	for i := y1 + 1; i < y2; i++ {
		parts << view.lines[i]
	}
	parts << view.lines[y2].runes()[..x2].string()
	return parts.join('\n')
}

fn (mut view View) delete_sel() {
	if !view.has_sel() {
		view.clear_sel()
		return
	}
	y1, x1, y2, x2 := view.sel_bounds()
	first := view.lines[y1].runes()[..x1].string()
	last := view.lines[y2].runes()[x2..].string()
	view.lines[y1] = first + last
	if y2 > y1 {
		view.lines.delete_many(y1 + 1, y2 - y1)
	}
	view.y = y1
	view.x = x1
	view.clear_sel()
	view.changed = true
	view.ved.update_cur_fn_name()
}

fn (mut view View) select_all() {
	view.sel_y = 0
	view.sel_x = 0
	view.y = view.lines.len - 1
	view.x = view.uline().len
}

// select_word selects the identifier under the cursor (double click).
fn (mut view View) select_word() {
	runes := view.uline()
	mut start := if view.x > runes.len { runes.len } else { view.x }
	mut end := start
	for start > 0 && is_alpha_underscore(int(runes[start - 1])) {
		start--
	}
	for end < runes.len && is_alpha_underscore(int(runes[end])) {
		end++
	}
	if start == end {
		return
	}
	view.sel_y = view.y
	view.sel_x = start
	view.x = end
}

// insert_multiline inserts text that may contain newlines, used for pasting.
fn (mut view View) insert_multiline(text string) {
	parts := text.replace('\r\n', '\n').split('\n')
	if parts.len == 1 {
		view.insert_text(parts[0])
		return
	}
	runes := view.uline()
	pos := if view.x > runes.len { runes.len } else { view.x }
	left := runes[..pos].string()
	right := runes[pos..].string()
	view.lines[view.y] = left + parts[0]
	for i := 1; i < parts.len; i++ {
		view.lines.insert(view.y + i, parts[i])
	}
	view.y += parts.len - 1
	view.x = parts.last().runes().len
	view.lines[view.y] += right
	view.changed = true
	view.ved.update_cur_fn_name()
}

// Cursor movement

fn (mut view View) move_vert(delta int) {
	if view.want_col < 0 {
		view.want_col = visual_col(view.line(), view.x, view.ved.cfg.tab_size)
	}
	mut y := view.y + delta
	if y < 0 {
		y = 0
	}
	if y >= view.lines.len {
		y = view.lines.len - 1
	}
	view.set_y(y)
	view.x = x_for_col(view.line(), view.want_col, view.ved.cfg.tab_size)
}

fn (mut view View) move_left() {
	if view.x > 0 {
		view.x--
	} else if view.y > 0 {
		view.set_y(view.y - 1)
		view.x = view.uline().len
	}
}

fn (mut view View) move_right() {
	if view.x < view.uline().len {
		view.x++
	} else if view.y < view.lines.len - 1 {
		view.set_y(view.y + 1)
		view.x = 0
	}
}

// word_left and word_right jump over a run of identifier chars or a run of
// punctuation, skipping whitespace first. At a line edge they wrap.
fn (mut view View) word_left() {
	if view.x == 0 {
		view.move_left()
		return
	}
	runes := view.uline()
	mut x := if view.x > runes.len { runes.len } else { view.x }
	for x > 0 && is_whitespace(u8(runes[x - 1])) {
		x--
	}
	if x > 0 {
		word := is_alpha_underscore(int(runes[x - 1]))
		for x > 0 && !is_whitespace(u8(runes[x - 1]))
			&& is_alpha_underscore(int(runes[x - 1])) == word {
			x--
		}
	}
	view.x = x
}

fn (mut view View) word_right() {
	runes := view.uline()
	if view.x >= runes.len {
		view.move_right()
		return
	}
	mut x := view.x
	word := is_alpha_underscore(int(runes[x]))
	if !is_whitespace(u8(runes[x])) {
		for x < runes.len && !is_whitespace(u8(runes[x]))
			&& is_alpha_underscore(int(runes[x])) == word {
			x++
		}
	}
	for x < runes.len && is_whitespace(u8(runes[x])) {
		x++
	}
	view.x = x
}

// smart_home goes to the first non whitespace char, or to column 0 if already there.
fn (mut view View) smart_home() {
	runes := view.uline()
	mut first := 0
	for first < runes.len && is_whitespace(u8(runes[first])) {
		first++
	}
	view.x = if view.x == first { 0 } else { first }
}

fn (mut view View) line_end() {
	view.x = view.uline().len
}

// Editing commands

fn (mut view View) duplicate() {
	if view.has_sel() {
		text := view.selected_text()
		_, _, y2, x2 := view.sel_bounds()
		view.clear_sel()
		view.y = y2
		view.x = x2
		view.insert_multiline(text)
		return
	}
	view.lines.insert(view.y + 1, view.line())
	view.set_y(view.y + 1)
	view.changed = true
}

fn line_comment_prefix(path string) string {
	return match os.file_ext(path) {
		'.py', '.sh', '.rb', '.toml', '.yaml', '.yml', '.pl', '.r', '.nim', '.cmake' { '#' }
		'.sql', '.lua', '.hs' { '--' }
		else { '//' }
	}
}

// toggle_comment comments out the current or selected lines, or uncomments them
// when all of them are already comments (Ctrl+/).
fn (mut view View) toggle_comment() {
	prefix := line_comment_prefix(view.path)
	top, bot := view.sel_line_range()
	mut all_commented := true
	for i := top; i <= bot; i++ {
		t := view.lines[i].trim_left(' \t')
		if t != '' && !t.starts_with(prefix) {
			all_commented = false
			break
		}
	}
	for i := top; i <= bot; i++ {
		line := view.lines[i]
		indent_len := line.len - line.trim_left(' \t').len
		rest := line[indent_len..]
		if all_commented {
			if !rest.starts_with(prefix) {
				continue
			}
			mut uncommented := rest[prefix.len..]
			if uncommented.starts_with(' ') {
				uncommented = uncommented[1..]
			}
			view.lines[i] = line[..indent_len] + uncommented
		} else if rest != '' {
			view.lines[i] = line[..indent_len] + prefix + ' ' + rest
		}
	}
	view.changed = true
	view.clamp_cursor()
	if !view.has_sel() {
		view.move_vert(1)
		view.want_col = -1
	}
}

// type_text is called for every typed character in the editor.
fn (mut ved Ved) type_text(s string) {
	mut view := ved.view
	if view.has_sel() {
		view.push_undo(.other)
		view.delete_sel()
	} else {
		view.push_undo(.typing)
	}
	view.want_col = -1
	view.insert_text(s)
	view.ensure_visible()
}

fn (mut ved Ved) toggle_fullscreen() {
	if gg.is_fullscreen() {
		// Exit fullscreen to small window
		gg.toggle_fullscreen()
		ved.win_width = 770
		ved.win_height = 480
		ved.gg.resize(ved.win_width, ved.win_height)
	} else {
		// Enter fullscreen with current screen size
		width, height := get_screen_size()
		ved.win_width = width
		ved.win_height = height
		gg.toggle_fullscreen()
	}
}

fn (mut ved Ved) open_query(typ QueryType) {
	ved.mode = .query
	ved.query_type = typ
	ved.query = ''
	ved.gg_pos = -1
}

// key_edit handles keys while the text area has focus. Bindings follow
// IntelliJ's default keymap, `ctrl` is cmd on macOS.
fn (mut ved Ved) key_edit(key gg.KeyCode, mod gg.Modifier) {
	ctrl := mod.has(.ctrl) || mod.has(.super)
	shift := mod.has(.shift)
	alt := mod.has(.alt)
	mut view := ved.view
	ved.refresh = true

	if key == .q && ctrl {
		ved.cq_in_a_row++
		if ved.cq_in_a_row == 2 {
			exit(0)
		}
		return
	}
	ved.cq_in_a_row = 0

	// Alt+letter opens a menu, like in IntelliJ
	if alt && !ctrl && !shift {
		for i, m in ved.menus {
			if int(key) == int(m.key) {
				ved.open_menu(i)
				return
			}
		}
	}

	// Cursor movement, shift extends the selection
	is_move := key in [.left, .right, .up, .down, .home, .end, .page_up, .page_down]
	if is_move && !(alt && key in [.left, .right]) {
		had_sel := view.has_sel()
		if shift {
			view.start_sel()
		} else if had_sel && !ctrl && key in [.left, .right] {
			// Plain left/right collapse the selection to its edge, like every IDE does
			y1, x1, y2, x2 := view.sel_bounds()
			view.clear_sel()
			if key == .left {
				view.set_y(y1)
				view.x = x1
			} else {
				view.set_y(y2)
				view.x = x2
			}
			view.want_col = -1
			view.ensure_visible()
			return
		} else {
			view.clear_sel()
		}
		if key !in [.up, .down, .page_up, .page_down] {
			view.want_col = -1
		}
		view.last_edit = .none
		match key {
			.left {
				if ctrl { view.word_left() } else { view.move_left() }
			}
			.right {
				if ctrl { view.word_right() } else { view.move_right() }
			}
			.up {
				if !ctrl {
					view.move_vert(-1)
				} else if view.from > 0 {
					view.from--
				}
			}
			.down {
				if !ctrl {
					view.move_vert(1)
				} else if view.from < view.lines.len - 1 {
					view.from++
				}
			}
			.home {
				if ctrl {
					view.gg()
					view.x = 0
				} else {
					view.smart_home()
				}
			}
			.end {
				if ctrl {
					view.shift_g()
				}
				view.line_end()
			}
			.page_up {
				view.move_vert(-view.page_height)
				view.from -= view.page_height
				if view.from < 0 {
					view.from = 0
				}
			}
			.page_down {
				view.move_vert(view.page_height)
				view.from += view.page_height
				if view.from > view.lines.len - 1 {
					view.from = view.lines.len - 1
				}
			}
			else {}
		}
		if !(ctrl && key in [.up, .down]) {
			view.ensure_visible()
		}
		return
	}

	match key {
		.escape {
			view.clear_sel()
		}
		.backspace {
			if view.has_sel() {
				view.push_undo(.other)
				view.delete_sel()
			} else if ctrl {
				view.push_undo(.other)
				view.start_sel()
				view.word_left()
				view.delete_sel()
			} else {
				view.push_undo(.deleting)
				view.backspace()
			}
			view.want_col = -1
		}
		.delete {
			if view.has_sel() {
				view.push_undo(.other)
				view.delete_sel()
			} else if ctrl {
				view.push_undo(.other)
				view.start_sel()
				view.word_right()
				view.delete_sel()
			} else if view.x < view.uline().len {
				view.push_undo(.deleting)
				view.delete_char()
			} else if view.y < view.lines.len - 1 {
				view.push_undo(.deleting)
				view.lines[view.y] += view.lines[view.y + 1]
				view.lines.delete(view.y + 1)
				view.changed = true
			}
			view.want_col = -1
		}
		.enter {
			if ctrl && alt {
				view.push_undo(.other)
				view.clear_sel()
				view.shift_o()
			} else if ctrl {
				ved.toggle_fullscreen()
			} else {
				view.push_undo(.other)
				if view.has_sel() {
					view.delete_sel()
				}
				view.clear_sel()
				if shift {
					view.o()
				} else {
					view.enter()
				}
			}
			view.want_col = -1
		}
		.tab {
			if ctrl {
				ved.next_tab(if shift { -1 } else { 1 })
			} else if shift {
				view.push_undo(.other)
				view.shift_left()
			} else if view.has_sel() && view.sel_y != view.y {
				view.push_undo(.other)
				view.shift_right()
			} else {
				ved.type_text('\t')
			}
		}
		.a {
			if ctrl {
				view.select_all()
			}
		}
		.b {
			if ctrl {
				view.clear_sel()
				ved.go_to_def()
			}
		}
		.c {
			if ctrl && shift {
				ved.cb.copy(view.path)
			} else if ctrl {
				ved.copy_selection()
			}
		}
		.d {
			if ctrl && shift {
				ved.git_show_diff(view.path)
			} else if ctrl && alt {
				ved.get_git_diff_full()
			} else if ctrl {
				view.push_undo(.other)
				view.duplicate()
			}
		}
		.e {
			if ctrl {
				view.tt()
			}
		}
		.f {
			if ctrl && shift {
				ved.search_query = ''
				ved.search_dir = ''
				ved.open_query(.grep)
			} else if ctrl && alt {
				ved.search_query = ''
				ved.search_dir = os.dir(view.path)
				ved.open_query(.search_in_folder)
			} else if ctrl {
				// start with the selected text, if it fits on one line
				ved.search_query = if view.has_sel() && view.sel_y == view.y {
					view.selected_text()
				} else {
					''
				}
				ved.search_dir = ''
				ved.open_query(.search)
			}
		}
		.g {
			if ctrl {
				ved.open_query(.goto_line)
			}
		}
		.j {
			if ctrl && shift {
				view.push_undo(.other)
				view.join()
			}
		}
		.k {
			if ctrl && shift {
				ved.git_push()
			} else if ctrl {
				ved.run_action(.git_commit, '')
			}
		}
		.m {
			if ctrl && shift {
				view.clear_sel()
				ved.pct()
			}
		}
		.n {
			if ctrl && shift {
				ved.open_query(.ctrlp)
				ved.load_git_tree()
			}
		}
		.o {
			if ctrl && shift {
				ved.open_query(.open_workspace)
			} else if ctrl {
				ved.open_query(.open)
			}
		}
		.p {
			if ctrl && shift {
				ved.git_pull_async()
			} else if ctrl {
				ved.open_query(.ctrlp)
				ved.load_git_tree() // TODO only run if files change
			}
		}
		.q {
			if alt && view.has_sel() {
				view.push_undo(.other)
				view.gq()
			}
		}
		.r {
			if ctrl && shift {
				ved.open_query(.run)
			} else if ctrl {
				view.reopen()
			}
		}
		.s {
			if ctrl {
				ved.save_all()
			}
		}
		.t {
			if ctrl {
				ved.timer.load_tasks()
				ved.mode = .timer
			}
		}
		.u {
			if ctrl && shift {
				ved.mode = .debugger
				ved.run_debugger(view.breakpoints)
			} else if ctrl {
				ved.key_u()
			}
		}
		.v {
			if ctrl {
				ved.paste()
			}
		}
		.w {
			if ctrl {
				ved.close_tab(view.path)
			}
		}
		.x {
			if ctrl {
				ved.cut_selection()
			}
		}
		.y {
			if ctrl {
				view.push_undo(.other)
				view.clear_sel()
				view.dd()
			}
		}
		.z {
			if ctrl && alt {
				ved.run_action(.git_rollback, '')
			} else if ctrl && shift {
				view.redo()
			} else if ctrl {
				view.undo()
			}
		}
		.slash {
			if ctrl {
				view.push_undo(.other)
				view.toggle_comment()
			}
		}
		.space {
			if ctrl {
				ved.ctrl_n()
			}
		}
		.minus {
			if ctrl && shift {
				ved.increase_font(-1)
			} else if ctrl {
				ved.get_git_diff_full()
			}
		}
		.equal {
			if ctrl && shift {
				ved.increase_font(1)
			}
		}
		._0 {
			if alt {
				ved.show_panel(.commit)
			} else if ctrl {
				// new task
				ved.open_query(.task)
			}
		}
		._1 {
			if alt {
				ved.show_panel(.project)
			}
		}
		._9 {
			if alt {
				ved.git_log()
			} else if ctrl {
				// new @task
				ved.open_query(.task)
				ved.query = '@'
			}
		}
		.left_bracket {
			if ctrl {
				ved.open_workspace(ved.workspace_idx - 1)
			}
		}
		.right_bracket {
			if ctrl {
				ved.open_workspace(ved.workspace_idx + 1)
			}
		}
		.f3 {
			if ctrl {
				ved.star()
			} else {
				ved.search(if shift { SearchType.backward } else { SearchType.forward })
			}
		}
		.f4 {
			if ctrl {
				ved.close_tab(view.path)
			}
		}
		.f5 {
			ved.run_file()
		}
		.f8 {
			if ved.mode == .debugger {
				ved.debugger.step_over()
			} else if ctrl {
				view.add_breakpoint(view.y)
			}
		}
		.f9 {
			if ctrl && shift {
				spawn ved.build_app2()
			} else if ctrl {
				ved.key_u()
			} else if shift {
				ved.mode = .debugger
				ved.run_debugger(view.breakpoints)
			}
		}
		.f10 {
			if shift {
				ved.run_file()
			}
		}
		.f11 {
			ved.toggle_fullscreen()
		}
		.f12 {
			if shift {
				ved.open_blog()
			} else if alt {
				ved.open_query(.run)
			}
		}
		else {}
	}
	// alt+left/right switch tabs, alt+shift+left/right switch splits
	if alt && key in [.left, .right] {
		if shift {
			if key == .left { ved.prev_split() } else { ved.next_split() }
		} else {
			ved.next_tab(if key == .left { -1 } else { 1 })
		}
	}
	ved.view.ensure_visible()
}
