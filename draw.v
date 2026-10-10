module main

import gg
import os

// Layout: file tree on the left, tab bar on top of the editor area,
// status bar at the very bottom, and the splits fill the rest.
fn (ved &Ved) tree_width() int {
	if !ved.cfg.show_file_tree {
		return 0
	}
	mut w := ved.cfg.tree_width
	if w > ved.win_width / 3 {
		w = ved.win_width / 3
	}
	return w
}

fn (ved &Ved) tab_bar_height() int {
	return ved.cfg.line_height + 12
}

fn (ved &Ved) status_bar_height() int {
	return ved.cfg.line_height + 6
}

// content_top is where everything below the menu bar starts.
fn (ved &Ved) content_top() int {
	return ved.menu_bar_height() + 1
}

fn (ved &Ved) tab_bar_bottom() int {
	return ved.content_top() + ved.tab_bar_height()
}

// text_top is the y of the first text line.
fn (ved &Ved) text_top() int {
	return ved.tab_bar_bottom() + 4
}

fn (mut ved Ved) draw() {
	mut view := ved.view
	split_width := ved.split_width()
	ved.page_height = (ved.win_height - ved.text_top() - ved.status_bar_height()) / ved.cfg.line_height
	if ved.page_height < 1 {
		ved.page_height = 1
	}
	from, to := ved.get_splits_from_to()
	for i := from; i < to && i < ved.views.len; i++ {
		ved.views[i].page_height = ved.page_height
	}
	// Current line
	y := ved.calc_cursor_y()
	cursor_visible := view.y >= view.from && view.y < view.from + ved.page_height
	line_x := ved.split_x(ved.cur_split - from) + view.padding_left + 10
	line_width := split_width - view.padding_left - 10
	if cursor_visible && !view.has_sel() {
		ved.gg.draw_rect_filled(line_x, y, line_width, ved.cfg.line_height, ved.cfg.vcolor)
	}
	// Splits
	for i := to - 1; i >= from; i-- {
		ved.draw_split(i, from)
	}
	// Debugger variables
	if ved.mode == .debugger && ved.debugger.output.vars.len > 0 {
		ved.draw_debugger_variables()
	}
	if cursor_visible {
		ved.draw_cursor(ved.calc_cursor_x(), y)
	}
	if ved.cfg.show_file_tree {
		ved.draw_left_panel()
	}
	ved.draw_tab_bar()
	ved.draw_status_bar()
	ved.draw_menu_bar()
	if ved.mode == .query {
		ved.draw_query()
	} else if ved.mode == .autocomplete {
		ved.draw_autocomplete_window()
	}
	ved.draw_notes()
	ved.draw_dropdown()
}

// draw_notes draws the notification balloons in the bottom right corner.
fn (mut ved Ved) draw_notes() {
	mut y := ved.win_height - ved.status_bar_height() - 12
	cw := ved.cfg.char_width
	for i := ved.notes.len - 1; i >= 0; i-- {
		note := ved.notes[i]
		w := int_min(note.text.runes().len * cw + 36, ved.win_width - 24)
		h := ved.cfg.line_height + 18
		y -= h
		x := ved.win_width - w - 12
		ved.gg.draw_rounded_rect_filled(x + 2, y + 3, w, h, 6, gg.rgba(0, 0, 0, 60))
		ved.gg.draw_rounded_rect_filled(x - 1, y - 1, w + 2, h + 2, 6, ved.cfg.split_color)
		ved.gg.draw_rounded_rect_filled(x, y, w, h, 6, ved.cfg.popup_bgcolor)
		dot := if note.is_error { gg.rgb(220, 80, 80) } else { ved.cfg.git_added_color }
		ved.gg.draw_circle_filled(x + 14, y + h / 2, 4, dot)
		max_chars := (w - 36) / cw
		text := if note.text.runes().len > max_chars {
			note.text.runes()[..max_chars - 1].string() + '…'
		} else {
			note.text
		}
		ved.gg.draw_text(x + 26, y + 9, text, ved.cfg.txt_cfg)
		y -= 8
	}
}

fn (mut ved Ved) draw_status_bar() {
	h := ved.status_bar_height()
	y := ved.win_height - h
	text_y := y + (h - ved.cfg.line_height) / 2
	// Big red error line at the bottom
	if ved.error_line != '' {
		ved.gg.draw_rect_filled(0, y, ved.win_width, h, ved.cfg.errorbgcolor)
		ved.gg.draw_text(8, text_y, ved.error_line, gg.TextCfg{
			size:  ved.cfg.text_size
			color: gg.white
			align: gg.align_left
		})
		return
	}
	ved.gg.draw_rect_filled(0, y, ved.win_width, h, ved.cfg.panel_color)
	ved.gg.draw_line(0, y, ved.win_width, y, ved.cfg.split_color)
	view := ved.view
	mut left := view.short_path
	if ved.cur_fn_name != '' {
		left += '  >  ${ved.cur_fn_name}'
	}
	if ved.cur_task != '' {
		left += '    ${ved.cur_task} ${ved.task_minutes()}m'
	}
	if ved.timer.pom_is_started {
		left += '    pomodoro ${ved.pomodoro_minutes()}m'
	}
	ved.gg.draw_text(8, text_y, left, ved.cfg.dim_cfg)
	mut right := '${view.y + 1}:${view.x + 1}'
	if view.has_sel() {
		y1, x1, y2, x2 := view.sel_bounds()
		sel_info := if y1 == y2 { '${x2 - x1} chars' } else { '${y2 - y1 + 1} lines' }
		right = sel_info + '    ' + right
	}
	if ved.git_diff_plus !in ['', '+'] {
		right += '    ${ved.git_diff_plus} ${ved.git_diff_minus}'
	}
	right += '    ${short_space(ved.workspace)} ${ved.workspace_idx + 1}/${ved.workspaces.len}'
	right += '    ${ved.now.hhmm()}'
	ved.gg.draw_text(ved.win_width - 8, text_y, right, gg.TextCfg{
		...ved.cfg.dim_cfg
		align: gg.align_right
	})
}

fn (ved &Ved) split_x(i int) int {
	return ved.tree_width() + ved.split_width() * i
}

fn (mut ved Ved) draw_split(i int, split_from int) {
	view := ved.views[i]
	// Determine initial comment state for the first visible line
	// (handle /**/ comments blocks that start before current page)
	mut current_is_ml_comment := false
	if view.hl_on {
		current_is_ml_comment = ved.determine_ml_comment_state(view, view.from)
	}
	ext := os.file_ext(view.path) // Cache extension
	is_diff := ext == '.diff'
	mcomment := get_mcomment_by_ext(ext) // Cache delimiters

	split_width := ved.split_width()
	split_x := ved.split_x(i - split_from)
	// Vertical split line
	if i > split_from {
		ved.gg.draw_line(split_x, ved.tab_bar_bottom(), split_x, ved.win_height, ved.cfg.split_color)
	}
	if view.has_sel() {
		ved.draw_selection(view, split_x + view.padding_left + 10)
	}
	// Lines
	mut line_nr_rel := 0 // relative y on screen
	for j := view.from; j < view.from + ved.page_height && j < view.lines.len; j++ {
		line := view.lines[j]
		if line.len > 5000 {
			println('line len too big! views[${i}].lines[${j}] (${line.len}) path=${ved.view.path}')
			continue
		}
		x := split_x + view.padding_left
		y := ved.text_top() + line_nr_rel * ved.cfg.line_height
		// Error bg
		if view.error_y == j {
			ved.gg.draw_rect_filled(x + 10, y - 1, split_width - view.padding_left - 10,
				ved.cfg.line_height, ved.cfg.errorbgcolor)
		}
		// Breakpoint red circle
		if view.breakpoints.contains(j) {
			ved.gg.draw_circle_filled(split_x + 3, y + ved.cfg.line_height / 2 - 1, 5,
				gg.red)
		}
		// Breakpoint yellow line
		if ved.mode == .debugger && ved.cur_split == i && ved.debugger.output.line_nr != 0
			&& ved.debugger.output.line_nr == j + 1 {
			line_width := split_width - view.padding_left - 10
			ved.gg.draw_rect_filled(x + 10, y, line_width, ved.cfg.line_height, breakpoint_color)
		}
		// Line number
		line_number := j + 1
		ved.gg.draw_text(x + 3, y, '${line_number}', ved.cfg.line_nr_cfg)
		// Git change marker in the gutter, between the number and the text
		if mark := view.git_marks[j] {
			gx := x + 5
			match mark {
				`a` {
					ved.gg.draw_rect_filled(gx, y, 3, ved.cfg.line_height, ved.cfg.git_added_color)
				}
				`m` {
					ved.gg.draw_rect_filled(gx, y, 3, ved.cfg.line_height, ved.cfg.git_modified_color)
				}
				else {
					ved.gg.draw_triangle_filled(gx - 1, y - 4, gx + 5, y, gx - 1, y + 4, ved.cfg.line_nr_color)
				}
			}
		}
		// Tab offset
		mut line_x := x + 10
		mut nr_tabs := 0
		// for k := 0; k < line.len; k++ {
		for c in line {
			if c != `\t` {
				break
			}
			nr_tabs++
			line_x += ved.cfg.char_width * ved.cfg.tab_size
		}
		mut s := line[nr_tabs..] // tabs have been skipped, remove them from the string
		if s == '' {
			line_nr_rel++
			continue
		}
		// Number of chars to display in this view
		// mut max := (split_width - view.padding_left - ved.cfg.char_width * TAB_SIZE *
		// nr_tabs) / ved.cfg.char_width - 1
		max := ved.max_chars(i, nr_tabs)
		if view.y == j {
			// Display entire line if its current
			// if line.len > max {
			// ved.gg.draw_rect_filled(line_x, y - 1, ved.win_width, line_height, vcolor)
			// }
			// max = line.len
		}
		// if s.contains('width :=') {
		// println('"$s" max=$max')
		//}
		// Handle utf8 codepoints
		// old_len := s.len
		if s.len != s.len_utf8() {
			u := s.runes()
			if max > 0 && max < u.len {
				s = u[..max].string()
			}
		} else {
			if max > 0 && max < s.len {
				s = s[..max]
			}
		}

		if is_diff {
			// unified diff output from the git actions
			color := if s.starts_with('+') && !s.starts_with('+++') {
				ved.cfg.git_added_color
			} else if s.starts_with('-') && !s.starts_with('---') {
				ved.cfg.git_untracked_color
			} else if s.starts_with('@@') {
				ved.cfg.git_modified_color
			} else {
				ved.cfg.text_color
			}
			ved.gg.draw_text(line_x, y, s, gg.TextCfg{
				...ved.cfg.txt_cfg
				color: color
			})
		} else if view.hl_on {
			// Handle multi page /**/
			// Find the position of start and end comment delimiters on the current line.
			// This now uses the string-based delimiters from the Mcomment struct.
			start_comment_pos := s.index(mcomment.start) or { -1 }
			end_comment_pos := s.index(mcomment.end) or { -1 }

			// This logic handles rendering for a line that starts inside a multi-line comment.
			if current_is_ml_comment {
				if end_comment_pos != -1 { // The multi-line comment ends on this line.
					// Draw the part of the line that is inside the comment.
					// The slice now uses `mcomment.end.len` for an accurate length.
					comment_part := s[..end_comment_pos + mcomment.end.len]
					ved.gg.draw_text(line_x, y, comment_part, ved.cfg.comment_cfg)

					// Draw the rest of the line (after the comment) using standard syntax highlighting.
					normal_part := s[end_comment_pos + mcomment.end.len..]
					if normal_part.len > 0 {
						// Calculate the starting x-position for the text after the comment.
						normal_part_x := line_x + comment_part.len * ved.cfg.char_width
						ved.draw_text_line_standard_syntax(normal_part_x, y, normal_part,
							ext)
					}

					// Update the state since the comment block is now closed.
					current_is_ml_comment = false
				} else { // The entire line is still inside the comment.
					// Draw the whole line with the comment color.
					ved.gg.draw_text(line_x, y, s, ved.cfg.comment_cfg)
					// The state `current_is_ml_comment` remains true for the next line.
				}
			} else { // current_is_ml_comment is false
				if start_comment_pos != -1
					&& (end_comment_pos == -1 || end_comment_pos < start_comment_pos) { // Comment starts here and continues
					// Draw normal part before / *
					normal_part := s[..start_comment_pos]
					if normal_part.len > 0 {
						ved.draw_text_line_standard_syntax(line_x, y, normal_part, ext)
					}
					// Draw comment part from / * onwards
					comment_part := s[start_comment_pos..]
					comment_part_x := line_x + normal_part.len * ved.cfg.char_width // Adjust based on actual rendered width if needed
					ved.gg.draw_text(comment_part_x, y, comment_part, ved.cfg.comment_cfg)
					current_is_ml_comment = true // Update state for next line
				} else { // No multiline comment start OR it's a single-line /* ... */
					// Use the standard highlighter for the whole line
					ved.draw_text_line_standard_syntax(line_x, y, s, ext)
					// current_is_ml_comment remains false
				}
			}
		} else {
			ved.gg.draw_text(line_x, y, s, ved.cfg.txt_cfg)
		}
		line_nr_rel++
	}
}

// draw_selection paints the selection background of a split, line by line.
fn (ved &Ved) draw_selection(view &View, line_x int) {
	y1, x1, y2, x2 := view.sel_bounds()
	top := if y1 > view.from { y1 } else { view.from }
	bot := if y2 < view.from + ved.page_height - 1 { y2 } else { view.from + ved.page_height - 1 }
	cw := ved.cfg.char_width
	for j := top; j <= bot && j < view.lines.len; j++ {
		line := view.lines[j]
		start := if j == y1 { visual_col(line, x1, ved.cfg.tab_size) } else { 0 }
		// lines fully inside the selection get one extra column for the newline
		end := if j == y2 {
			visual_col(line, x2, ved.cfg.tab_size)
		} else {
			visual_col(line, line.len, ved.cfg.tab_size) + 1
		}
		if end <= start {
			continue
		}
		y := ved.text_top() + (j - view.from) * ved.cfg.line_height
		ved.gg.draw_rect_filled(line_x + start * cw, y, (end - start) * cw, ved.cfg.line_height,
			ved.cfg.sel_color)
	}
}

fn (ved &Ved) max_chars(view_idx int, nr_tabs int) int {
	width := ved.split_width() - ved.views[view_idx].padding_left - ved.cfg.char_width * ved.cfg.tab_size * nr_tabs
	return width / ved.cfg.char_width - 1
}

fn (ved &Ved) draw_cursor(cursor_x int, y int) {
	mut width := ved.cfg.char_width
	// println('CURSOR WIDTH=${ved.cfg.char_width}')
	match ved.cfg.cursor_style {
		.block {
			width = ved.cfg.char_width
		}
		.beam, .variable {
			// there are no modes anymore, so variable is just a beam
			ved.gg.draw_rect_filled(cursor_x, y, 2, ved.cfg.line_height, ved.cfg.cursor_color)
			return
		}
	}
	ved.gg.draw_rect_empty(cursor_x, y, width, ved.cfg.line_height, ved.cfg.cursor_color)
}

fn (ved &Ved) calc_cursor_x() int {
	from := ved.workspace_idx * ved.nr_splits
	line_x := ved.split_x(ved.cur_split - from) + ved.view.padding_left + 10
	return line_x + visual_col(ved.view.line(), ved.view.x, ved.cfg.tab_size) * ved.cfg.char_width
}

fn (ved &Ved) calc_cursor_y() int {
	return ved.text_top() + (ved.view.y - ved.view.from) * ved.cfg.line_height
}
