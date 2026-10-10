// Copyright (c) 2019-2025 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license
// that can be found in the LICENSE file.
module main

import os
import strings

// View represents a single editor pane or "view", holding the state for an open file buffer.
// This includes the file path, content (lines), cursor position (x, y),
// scroll position (from), and other view-specific settings.
struct View {
mut:
	padding_left int
	from         int
	x            int
	y            int
	prev_x       int
	path         string
	short_path   string
	prev_path    string // for tt
	lines        []string
	page_height  int
	sel_x        int // selection anchor, the other end of the selection is the cursor
	sel_y        int = -1 // -1 means nothing is selected
	want_col     int = -1 // visual column kept while moving up and down through shorter lines
	undo_stack   []UndoState
	redo_stack   []UndoState
	last_edit    EditKind
	edit_seq     int // bumped on every change, the git gutter recomputes when it moves
	git_req_seq  int = -1 // edit_seq the last gutter job was started for
	last_edit_ms i64
	git_marks    map[int]u8 // line => `a`dded, `m`odified, `d`eleted, compared to HEAD
	changed      bool
	error_y      int
	ved          &Ved = unsafe { nil }
	prev_y       int
	hash_comment bool
	hl_on        bool
	breakpoints  []int // line numbers with breakpoints
}

// new_view creates and initializes a new `View` instance.
fn (ved &Ved) new_view() View {
	res := View{
		padding_left: 0
		path:         ''
		from:         0
		y:            0
		x:            0
		prev_x:       0
		page_height:  ved.page_height
		sel_y:        -1
		want_col:     -1
		git_req_seq:  -1
		ved:          ved
		error_y:      -1
		prev_y:       -1
	}
	return res
}

// `mut res := word.clone()` ==>
// ['mut' 'res' 'word' 'clone']
// get_clean_words extracts a list of words from a line.
// A "word" is considered a contiguous sequence of alphanumeric characters and underscores.
fn get_clean_words(line string) []string {
	mut res := []string{}
	mut i := 0
	for i < line.len {
		// Skip bad first
		for i < line.len && !is_alpha_underscore(int(line[i])) {
			i++
		}
		// Read all good
		start2 := i
		for i < line.len && is_alpha_underscore(int(line[i])) {
			i++
		}
		// End of word, save it
		word := line[start2..i]
		res << word
		i++
	}
	return res
}

// open_file opens a file at the given `path`, loads its contents into the view's buffer,
// and optionally moves the cursor to `line_nr`. It also updates the editor's state,
// such as the list of open files and syntax highlighting settings.
fn (mut view View) open_file(path string, line_nr int) {
	println('open file "${path}"')
	if path == '' {
		return
	}
	// Switching away from a file with unsaved edits keeps them in memory, like IDE tabs do
	if path != view.path && view.path != '' && view.changed {
		view.ved.stash_view(view)
	}
	stashed := view.ved.stash[path] or { Buffer{} }
	from_stash := path in view.ved.stash
	lines := if from_stash {
		stashed.lines
	} else {
		load_lines(path) or {
			view.ved.error_line = 'cannot open ${path}: ${err.msg()}'
			return
		}
	}
	// This path is in current workspace? Trim it. /code/v/file.v => file.v
	if path.starts_with(view.ved.workspace + '/') {
		view.short_path = path[view.ved.workspace.len..]
		if view.short_path.starts_with('/') {
			view.short_path = view.short_path[1..]
		}
	} else {
		// Optimize space, replace /Users/username with ~
		if path.starts_with(home_dir) {
			view.short_path = path.replace(home_dir, '~')
		} else {
			view.short_path = path
		}
	}
	mut ved := view.ved
	ved.set_current_syntax_idx(os.file_ext(path))
	// Track file open count for ctrl+p prioritization
	ved.file_open_count[path] = ved.file_open_count[path] + 1
	// if os.exists(view.short_path) &&
	if view.short_path !in ['out', ''] && path !in ved.open_paths[ved.workspace_idx] {
		if ved.open_paths[ved.workspace_idx].len == 0 {
			ved.open_paths[ved.workspace_idx] = []string{cap: ved.nr_splits}
		}
		ved.open_paths[ved.workspace_idx] << path
	}
	if path != view.path {
		// Save cursor pos (Y)
		view.ved.file_y_pos[view.path] = view.y
		view.prev_path = view.path
	}
	view.lines = lines
	// get words map
	if view.lines.len < 1000 {
		println('getting words')
		// ticks := glfw.get_time()
		for line in view.lines {
			// words := line.split(' ')
			words := get_clean_words(line)
			for word in words {
				// clean_word := get_clean_word(word)
				// if clean_word == '' {
				// continue
				// }
				if word !in ved.words {
					ved.words << word
				}
			}
		}
		// took := glfw.get_time() - ticks
	}
	// Empty file, handle it
	if view.lines.len == 0 {
		view.lines << ''
	}
	switched := path != view.path
	if switched {
		view.x = 0
		view.y = 0
		view.from = 0
		view.sel_y = -1
		view.want_col = -1
		view.undo_stack = []
		view.redo_stack = []
		view.last_edit = .none
	}
	view.path = path
	// view.short_path = path.replace(view.ved.workspace, '')
	// Calc padding_left
	nr_lines := view.lines.len
	s := '${nr_lines}'
	view.padding_left = s.len * ved.cfg.char_width + 8
	view.ved.save_session()
	view.edit_seq++
	if switched {
		view.git_marks = map[int]u8{}
	}
	// Go to old y for this file
	mut y := view.ved.file_y_pos[view.path]
	// The file may have shrunk since the position was saved.
	if y >= view.lines.len {
		y = view.lines.len - 1
	}
	if y > 0 {
		view.set_y(y)
		if switched {
			view.zz()
		}
	}
	// Call zz() if it's out of bounds
	if view.from > view.y || view.from + view.ved.page_height < view.y {
		// view.zz()
	}

	if line_nr != 0 {
		view.move_to_line(line_nr)
	}

	view.clamp_cursor() // so that cursor pos doesn't point to no longer existing text

	view.hash_comment = !view.path.ends_with('.v')
	view.hl_on = !view.path.ends_with('.md') && !view.path.ends_with('.txt')
		&& view.path.contains('.')
	view.changed = false
	if from_stash {
		view.ved.stash.delete(path)
		view.x = stashed.x
		view.y = stashed.y
		view.from = stashed.from
		view.undo_stack = stashed.undo_stack
		view.redo_stack = stashed.redo_stack
		view.changed = true
		view.clamp_cursor()
	}
	view.ved.gg.refresh_ui()
	// go view.ved.write_changes_in_file_every_5s()
}

// reopen reloads the content of the file currently associated with the view from disk.
// This is useful for discarding changes or updating the view after external modifications.
fn (mut view View) reopen() {
	// open_file clears `changed` only when the file could be read, so unsaved edits stay marked.
	view.open_file(view.path, 0)
}

// save_file saves the current content of the view's buffer to its associated file on disk.
// It then triggers an asynchronous file formatting process.
fn (mut view View) save_file() {
	if view.path == '' {
		return
	}
	path := view.path
	view.ved.file_y_pos[view.path] = view.y
	println('saving file "${path}"')
	println('lines.len=${view.lines.len}')
	// line0 := view.lines[0]
	// println('line[0].len=$line0.len')
	// On failure, keep the buffer untouched: the reopen below would replace
	// the unsaved edits with whatever is on disk.
	save := if view.ved.cfg.atomic_save { write_lines_atomic } else { write_lines }
	save(path, view.lines) or {
		view.ved.error_line = 'cannot save ${path}: ${err.msg()}'
		return
	}
	spawn view.format_file(path)
	view.ved.refresh_git()
	// If another split has the same file open, update it
	for mut v in view.ved.views {
		if v.path == view.path {
			v.reopen()
		}
	}
}

// format_file asynchronously runs an external formatting command (like `v fmt`, `goimports`, `prettier`)
// on the view's file. After formatting, it reloads the file to reflect the changes.
fn (mut view View) format_file(path string) {
	view.ved.load_config2()
	if view.ved.cfg.disable_fmt {
		return
	}
	// Run formatters
	fmt_cmd := view.ved.syntaxes[view.ved.current_syntax_idx].fmt_cmd.fields().map(it.replace('<PATH>',
		path))
	if path.ends_with('.go') {
		println('running goimports')
		os.system_args(['goimports', '-w', path])
	} else if path.ends_with('.scss') {
		css := path.replace('.scss', '.css')
		res := os.exec(['sassc', path])
		if res.exit_code == 0 {
			os.write_file(css, res.output) or {}
		}
	} else if path.ends_with('.js') {
		os.system_args(['prettier', '--use-tabs', '-w', path])
	} else if fmt_cmd.len > 0 {
		os.system_args(fmt_cmd)
	}
	// The view may show another file by now (tab switched right after saving)
	if view.path != path {
		return
	}
	view.reopen()
	// update git diff
	view.ved.get_git_diff()
	view.changed = false
	// println('end of save file()')
	// println('_lines.len=$view.lines.len')
	// line0_ := view.lines[0]
	// println('_line[0].len=$line0_.len')
}

// line returns the content of the current line (at cursor position `y`) as a string.
fn (view &View) line() string {
	if view.y < 0 || view.y >= view.lines.len {
		return ''
	}
	return view.lines[view.y]
}

// uline returns the content of the current line as a slice of runes, suitable for multi-byte character manipulation.
fn (view &View) uline() []rune {
	return view.line().runes()
}

// char returns the character (as an integer rune) at the current cursor position (`x`).
fn (view &View) char() int {
	line := view.line()
	if line.len > 0 && view.x < line.len {
		return int(line[view.x])
	}
	return 0
}

// set_line replaces the content of the current line with `newline`.
fn (mut view View) set_line(newline string) {
	if view.y < 0 { // Basic sanity check
		return
	}
	if view.y < view.lines.len { // Check if index is within current bounds
		view.lines[view.y] = newline
	} else if view.y == view.lines.len { // Check if index is exactly one past the end
		view.lines << newline
	} else { // Index is too large
		// Optionally, append anyway or just return to prevent further issues
		view.lines << newline // Append as a fallback? Or just return? Append seems safer for paste.
	}
	view.changed = true
}

// set_y sets the vertical position (line number) of the cursor.
fn (mut view View) set_y(new_y int) {
	view.y = new_y
	view.ved.update_cur_fn_name()
}

// l moves the cursor one character to the right.
fn (mut view View) l() {
	line := view.line()
	if view.x < line.len {
		view.x++
	}
}

// h moves the cursor one character to the left.
fn (mut view View) h() {
	if view.x > 0 {
		view.x--
	}
	line := view.line()
	// Cursor is outside the line, move it to the end of it
	if view.x > line.len {
		view.x = line.len
	}
}

// shift_g moves the cursor to the last line of the file (Ctrl+End).
fn (mut view View) shift_g() {
	view.set_y(view.lines.len - 1)
	view.from = view.y - view.page_height + 1
	if view.from < 0 {
		view.from = 0
	}
}

// gg moves the cursor to the first line of the file (Ctrl+Home).
fn (mut view View) gg() {
	view.from = 0
	view.set_y(0)
}

// shift_f scrolls the view down by one page (Page Down).
fn (mut view View) shift_f() {
	view.from += view.page_height
	if view.from >= view.lines.len {
		view.from = view.lines.len - 1
	}
	view.set_y(view.from)
}

// shift_b scrolls the view up by one page (Page Up).
fn (mut view View) shift_b() {
	view.from -= view.page_height
	if view.from < 0 {
		view.from = 0
	}
	view.set_y(view.from)
}

// dd deletes the current line (Ctrl+Y).
fn (mut view View) dd() {
	if view.lines.len == 0 {
		return
	}
	if view.lines.len == 1 {
		// never leave the buffer without lines, the rest of the code assumes there's one
		view.lines[0] = ''
	} else {
		view.lines.delete(view.y)
	}
	if view.y >= view.lines.len {
		view.y = view.lines.len - 1
	}
	view.clamp_cursor()
	view.changed = true
}

// shift_right indents the current line or the selected lines by one level (Tab).
fn (mut view View) shift_right() {
	top, bot := view.sel_line_range()
	for i := top; i <= bot; i++ {
		view.lines[i] = '\t${view.lines[i]}'
	}
	view.x++
	if view.has_sel() {
		view.sel_x++
	}
	view.changed = true
}

// shift_left un-indents the current line or the selected lines by one level (Shift+Tab).
fn (mut view View) shift_left() {
	top, bot := view.sel_line_range()
	for i := top; i <= bot; i++ {
		line := view.lines[i]
		if !line.starts_with('\t') {
			continue
		}
		view.lines[i] = line[1..]
		if i == view.y && view.x > 0 {
			view.x--
		}
		if i == view.sel_y && view.sel_x > 0 {
			view.sel_x--
		}
		view.changed = true
	}
}

// delete_char deletes the character right after the cursor (Delete).
fn (mut v View) delete_char() {
	u := v.uline()
	if u.len < 1 || v.x >= u.len {
		return
	}
	mut new_line := unsafe { u[..v.x] }
	right := u[v.x + 1..]
	new_line << right
	v.set_line(new_line.string())
}

// insert_text inserts the given string `s` at the current cursor position.
fn (mut view View) insert_text(s string) {
	line := view.line()
	if line.len == 0 {
		view.set_line(s)
	} else {
		if view.x > line.len {
			view.x = line.len
		}
		uline := line.runes()
		if view.x > uline.len {
			return
		}
		left := uline[..view.x].string()
		right := uline[view.x..uline.len].string()
		// Insert char in the middle
		res := '${left}${s}${right}'
		view.set_line(res)
	}
	view.x += s.runes().len
	view.changed = true
	// Show autocomplete window on `.`
	if s == '.' {
		println('DOOOT, SHOW WINDOW')
		view.ved.mode = .autocomplete
		view.ved.refresh = true
		view.ved.gg.refresh_ui()
		go view.ved.get_line_info()
	}
}

// backspace deletes the character before the cursor, or joins the line with
// the previous one when the cursor is at the start of it.
fn (mut view View) backspace() {
	if view.x == 0 {
		if view.y > 0 {
			view.y--
			view.x = view.uline().len
			view.lines[view.y] += view.lines[view.y + 1]
			view.lines.delete(view.y + 1)
			view.changed = true
		}
		return
	}
	// line := view.line()
	uline := view.uline()
	// println('line="$line" uline="$uline.string()"')
	left := uline[..view.x - 1].string()
	mut right := ''
	if view.x < uline.len {
		right = uline[view.x..].string()
	}
	view.set_line('${left}${right}')
	view.x--
}

// shift_o opens a new, indented line above the current line (Ctrl+Alt+Enter).
fn (mut view View) shift_o() {
	view.o_generic(0)
}

// o opens a new, indented line below the current line (Shift+Enter).
fn (mut view View) o() {
	view.o_generic(1)
}

fn (mut view View) o_generic(delta int) {
	// Take the indentation from the line the cursor was on
	prev_line := view.line()
	view.y += delta
	nr_spaces, nr_tabs := nr_spaces_and_tabs_in_line(prev_line)
	mut new_line := strings.repeat(`\t`, nr_tabs) + strings.repeat(` `, nr_spaces)
	if delta == 1 && prev_line.trim_right(' ').ends_with('{') {
		new_line += '\t'
	}
	view.x = new_line.len
	if view.y >= view.lines.len {
		view.lines << new_line
	} else {
		view.lines.insert(view.y, new_line)
	}
	view.changed = true
}

// enter splits the current line at the cursor. The new line keeps the indentation,
// gets one more level after an opening bracket, and `{|}` turns into three lines.
fn (mut view View) enter() {
	uline := view.uline()
	pos := if view.x > uline.len { uline.len } else { view.x }
	left := uline[..pos].string()
	right := uline[pos..].string().trim_left(' \t')
	nr_spaces, nr_tabs := nr_spaces_and_tabs_in_line(left)
	indent := strings.repeat(`\t`, nr_tabs) + strings.repeat(` `, nr_spaces)
	trimmed := left.trim_right(' \t')
	opens := trimmed.len > 0 && trimmed[trimmed.len - 1] in [`{`, `(`, `[`]
	inner := if opens { indent + '\t' } else { indent }
	view.set_line(left)
	if opens && right.len > 0 && right[0] in [`}`, `)`, `]`] {
		view.lines.insert(view.y + 1, inner)
		view.lines.insert(view.y + 2, indent + right)
	} else {
		view.lines.insert(view.y + 1, inner + right)
	}
	view.set_y(view.y + 1)
	view.x = inner.runes().len
	view.changed = true
}

// join joins the current line with the line below it (Ctrl+Shift+J).
fn (mut view View) join() {
	if view.y >= view.lines.len - 1 {
		return
	}
	line := view.line().trim_right(' \t')
	second_line := view.lines[view.y + 1].trim_left(' \t')
	view.x = line.runes().len
	if line.len > 0 && second_line.len > 0 {
		view.set_line('${line} ${second_line}')
		view.x++
	} else {
		view.set_line(line + second_line)
	}
	view.lines.delete(view.y + 1)
}

// returns the removed word
// db deletes the word backwards from the cursor position.
fn (mut view View) db(del_whitespace bool) { // string {
	typ := is_alpha(u8(view.char()))
	// While cur char has the same type - delete it
	for {
		line := view.line()
		if view.x < 0 || view.x >= line.len - 1 {
			break
		}
		view.x--
		if typ == is_alpha_underscore(u8(view.char())) {
			// println('del x=$view.x len=$line.len')
			view.delete_char()
		} else {
			break
		}
	}
	view.x++
	// Delete whitespace after the deleted word
	/*
	if del_whitespace {
		for is_whitespace(u8(view.char())) {
			line := view.line()
			if view.x < 0 || view.x >= line.len {
				break
			}
			view.delete_char()
		}
	}
	*/
}

// zz centers the current line vertically on the screen.
fn (mut view View) zz() {
	view.from = view.y - view.ved.page_height / 2
	if view.from < 0 {
		view.from = 0
	}
}

// tt toggles to the previously active file (Ctrl+E).
fn (mut view View) tt() {
	if view.prev_path == '' {
		return
	}
	view.open_file(view.prev_path, 0)
}

// move_to_line jumps the cursor and view to a specific `line` number.
fn (mut view View) move_to_line(line int) {
	view.prev_y = view.y
	view.from = line
	view.set_y(line)
	view.zz()
}

// is_alpha checks if a byte represents an alphanumeric character (`a-z`, `A-Z`, `0-9`).
fn is_alpha(r u8) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`)
}

// is_whitespace checks if a byte represents a whitespace character (space or tab).
fn is_whitespace(r u8) bool {
	return r == ` ` || r == `\t`
}

// is_alpha_underscore checks if an integer (rune) represents an alphanumeric character, an underscore, a hash, or a dollar sign.
fn is_alpha_underscore(r int) bool {
	return is_alpha(u8(r)) || u8(r) == `_` || u8(r) == `#` || u8(r) == `$`
}

// break_text splits a single string `s` into an array of strings, ensuring no line exceeds `max` characters.
fn break_text(s string, max int) []string {
	mut lines := []string{}
	mut start := 0
	for i := 0; i < s.len; i++ {
		if i == s.len - 1 {
			// Include the very last char
			lines << s[start..i + 1]
			break
		}
		if i - start >= max {
			lines << s[start..i]
			start = i
		}
	}
	return lines
}
