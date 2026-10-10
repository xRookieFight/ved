module main

import gg
import os

// The main menu bar on top (File, Edit, ...) plus the branch widget on its right.
// Dropdowns, including the branch popup, share one drawing and input path.

enum Action {
	none
	new_file
	open_file
	open_workspace
	save
	reload
	close_tab
	exit
	undo
	redo
	cut
	copy
	paste
	select_all
	duplicate
	delete_line
	join_lines
	comment
	find
	find_next
	find_prev
	find_in_files
	toggle_tree
	toggle_commit
	font_bigger
	font_smaller
	fullscreen
	goto_file
	goto_line
	goto_def
	matching_bracket
	prev_file
	next_tab
	prev_tab
	next_split
	prev_split
	next_workspace
	prev_workspace
	git_commit
	git_push
	git_pull
	git_fetch
	git_branches
	git_new_branch
	git_diff
	git_diff_all
	git_history
	git_log
	git_rollback
	git_refresh
	git_checkout
	git_checkout_remote
	run_file
	build
	build2
	run_command
	debug
	breakpoint
	new_task
	timer
	copy_path
	shortcuts
}

struct MenuItem {
	label    string
	shortcut string
	action   Action
	arg      string
	sep      bool
	header   bool // a dim, unclickable group title
	checked  bool
}

struct Menu {
	title string
	key   u8 // Alt+key opens it
	items []MenuItem
}

const branch_popup = 100

fn item(label string, shortcut string, action Action) MenuItem {
	return MenuItem{
		label:    label
		shortcut: shortcut
		action:   action
	}
}

fn sep() MenuItem {
	return MenuItem{
		sep: true
	}
}

fn build_menus() []Menu {
	return [
		Menu{'File', `F`, [
			item('New File...', '', .new_file),
			item('Open File...', 'Ctrl+O', .open_file),
			item('Open Workspace...', 'Ctrl+Shift+O', .open_workspace),
			sep(),
			item('Save All', 'Ctrl+S', .save),
			item('Reload from Disk', 'Ctrl+R', .reload),
			item('Close Tab', 'Ctrl+W', .close_tab),
			sep(),
			item('Exit', 'Ctrl+Q Q', .exit),
		]},
		Menu{'Edit', `E`, [
			item('Undo', 'Ctrl+Z', .undo),
			item('Redo', 'Ctrl+Shift+Z', .redo),
			sep(),
			item('Cut', 'Ctrl+X', .cut),
			item('Copy', 'Ctrl+C', .copy),
			item('Paste', 'Ctrl+V', .paste),
			item('Copy Path', 'Ctrl+Shift+C', .copy_path),
			sep(),
			item('Select All', 'Ctrl+A', .select_all),
			item('Duplicate Line', 'Ctrl+D', .duplicate),
			item('Delete Line', 'Ctrl+Y', .delete_line),
			item('Join Lines', 'Ctrl+Shift+J', .join_lines),
			item('Comment Line', 'Ctrl+/', .comment),
			sep(),
			item('Find...', 'Ctrl+F', .find),
			item('Find Next', 'F3', .find_next),
			item('Find Previous', 'Shift+F3', .find_prev),
			item('Find in Files...', 'Ctrl+Shift+F', .find_in_files),
		]},
		Menu{'View', `V`, [
			item('Project', 'Alt+1', .toggle_tree),
			item('Commit', 'Alt+0', .toggle_commit),
			sep(),
			item('Increase Font Size', 'Ctrl+Shift+=', .font_bigger),
			item('Decrease Font Size', 'Ctrl+Shift+-', .font_smaller),
			item('Toggle Full Screen', 'F11', .fullscreen),
		]},
		Menu{'Navigate', `N`, [
			item('File...', 'Ctrl+P', .goto_file),
			item('Line...', 'Ctrl+G', .goto_line),
			item('Declaration', 'Ctrl+B', .goto_def),
			item('Matching Bracket', 'Ctrl+Shift+M', .matching_bracket),
			item('Previous File', 'Ctrl+E', .prev_file),
			sep(),
			item('Next Tab', 'Alt+Right', .next_tab),
			item('Previous Tab', 'Alt+Left', .prev_tab),
			item('Next Split', 'Alt+Shift+Right', .next_split),
			item('Previous Split', 'Alt+Shift+Left', .prev_split),
			item('Next Workspace', 'Ctrl+]', .next_workspace),
			item('Previous Workspace', 'Ctrl+[', .prev_workspace),
		]},
		Menu{'Git', `G`, [
			item('Commit...', 'Ctrl+K', .git_commit),
			item('Push...', 'Ctrl+Shift+K', .git_push),
			item('Update Project', 'Ctrl+Shift+P', .git_pull),
			item('Fetch', '', .git_fetch),
			sep(),
			item('Branches...', '', .git_branches),
			item('New Branch...', '', .git_new_branch),
			sep(),
			item('Show Diff', 'Ctrl+Shift+D', .git_diff),
			item('Show All Changes', '', .git_diff_all),
			item('Show File History', '', .git_history),
			item('Show Log', 'Alt+9', .git_log),
			item('Rollback File...', 'Ctrl+Alt+Z', .git_rollback),
			sep(),
			item('Refresh Status', '', .git_refresh),
		]},
		Menu{'Run', `R`, [
			item('Run File', 'Shift+F10', .run_file),
			item('Build Project', 'Ctrl+F9', .build),
			item('Alternative Build', 'Ctrl+Shift+F9', .build2),
			item('Run Command...', 'Alt+F12', .run_command),
			sep(),
			item('Debug', 'Shift+F9', .debug),
			item('Toggle Breakpoint', 'Ctrl+F8', .breakpoint),
		]},
		Menu{'Tools', `T`, [
			item('New Task...', 'Ctrl+0', .new_task),
			item('Timer', 'Ctrl+T', .timer),
		]},
		Menu{'Help', `H`, [
			item('Keyboard Shortcuts', '', .shortcuts),
		]},
	]
}

fn (ved &Ved) menu_bar_height() int {
	return ved.cfg.line_height + 10
}

fn (ved &Ved) menu_title_x(idx int) int {
	mut x := 8
	for i in 0 .. idx {
		x += ved.menus[i].title.len * ved.cfg.char_width + 20
	}
	return x
}

fn (ved &Ved) menu_items(idx int) []MenuItem {
	if idx == branch_popup {
		return ved.branch_items
	}
	if idx >= 0 && idx < ved.menus.len {
		return ved.menus[idx].items
	}
	return []MenuItem{}
}

fn (ved &Ved) item_height(it MenuItem) int {
	if it.sep {
		return 9
	}
	if it.header {
		return ved.cfg.line_height + 4
	}
	return ved.cfg.line_height + 8
}

// dropdown_rect returns where the open dropdown is drawn.
fn (ved &Ved) dropdown_rect() (int, int, int, int) {
	items := ved.menu_items(ved.menu_open)
	cw := ved.cfg.char_width
	mut label_w := 0
	mut short_w := 0
	mut h := 8
	for it in items {
		label_w = int_max(label_w, it.label.runes().len * cw)
		short_w = int_max(short_w, it.shortcut.len * cw)
		h += ved.item_height(it)
	}
	w := 28 + label_w + (if short_w > 0 { 40 + short_w } else { 0 }) + 16
	mut x := if ved.menu_open == branch_popup {
		ved.branch_widget_x + ved.branch_widget_w - w
	} else {
		ved.menu_title_x(ved.menu_open)
	}
	if x + w > ved.win_width - 4 {
		x = ved.win_width - 4 - w
	}
	if x < 4 {
		x = 4
	}
	return x, ved.menu_bar_height(), w, h
}

// dropdown_item_at returns the index of the clickable item under a point, or -1.
fn (ved &Ved) dropdown_item_at(mx int, my int) int {
	x, y, w, h := ved.dropdown_rect()
	if mx < x || mx >= x + w || my < y || my >= y + h {
		return -1
	}
	mut iy := y + 4
	for i, it in ved.menu_items(ved.menu_open) {
		ih := ved.item_height(it)
		if my >= iy && my < iy + ih {
			return if it.sep || it.header { -1 } else { i }
		}
		iy += ih
	}
	return -1
}

fn (mut ved Ved) open_menu(idx int) {
	if idx == branch_popup {
		if !ved.git.ok {
			ved.notify('Not a git repository', true)
			return
		}
		ved.load_branch_items()
	}
	ved.menu_open = idx
	ved.menu_sel = -1
	ved.mode = .edit
}

fn (mut ved Ved) close_menu() {
	ved.menu_open = -1
	ved.menu_sel = -1
}

fn (mut ved Ved) draw_menu_bar() {
	h := ved.menu_bar_height()
	ved.gg.draw_rect_filled(0, 0, ved.win_width, h, ved.cfg.toolbar_color)
	ved.gg.draw_line(0, h, ved.win_width, h, ved.cfg.split_color)
	text_y := (h - ved.cfg.line_height) / 2
	cw := ved.cfg.char_width
	for i, m in ved.menus {
		x := ved.menu_title_x(i)
		w := m.title.len * cw + 20
		hovered := ved.mouse_y < h && ved.mouse_x >= x - 2 && ved.mouse_x < x + w - 2
		if i == ved.menu_open || hovered {
			ved.gg.draw_rounded_rect_filled(x - 2, 4, w - 4, h - 8, 4, ved.cfg.hover_color)
		}
		ved.gg.draw_text(x + 8, text_y, m.title, ved.cfg.txt_cfg)
	}
	ved.draw_branch_widget()
}

// draw_branch_widget shows the current branch on the right, like IntelliJ's toolbar.
fn (mut ved Ved) draw_branch_widget() {
	h := ved.menu_bar_height()
	if !ved.git.ok {
		ved.branch_widget_w = 0
		return
	}
	cw := ved.cfg.char_width
	mut extra := ''
	if ved.git.ahead > 0 {
		extra += ' +${ved.git.ahead}'
	}
	if ved.git.behind > 0 {
		extra += ' -${ved.git.behind}'
	}
	label := ved.git.branch
	w := 16 + 14 + (label.runes().len + extra.len) * cw + 22
	x := ved.win_width - w - 8
	ved.branch_widget_x = x
	ved.branch_widget_w = w
	hovered := ved.mouse_y < h && ved.mouse_x >= x && ved.mouse_x < x + w
	if ved.menu_open == branch_popup || hovered {
		ved.gg.draw_rounded_rect_filled(x, 4, w, h - 8, 4, ved.cfg.hover_color)
	}
	// branch icon: two dots joined by a line, plus a branch off to the side
	ix := x + 10
	mid := h / 2
	c := ved.cfg.dim_cfg.color
	ved.gg.draw_line(ix + 2, mid - 5, ix + 2, mid + 5, c)
	ved.gg.draw_line(ix + 2, mid + 1, ix + 9, mid - 3, c)
	ved.gg.draw_circle_filled(ix + 2, mid - 6, 2, c)
	ved.gg.draw_circle_filled(ix + 2, mid + 6, 2, c)
	ved.gg.draw_circle_filled(ix + 9, mid - 4, 2, c)
	text_y := (h - ved.cfg.line_height) / 2
	tx := ix + 18
	ved.gg.draw_text(tx, text_y, label, ved.cfg.txt_cfg)
	if extra != '' {
		ved.gg.draw_text(tx + label.runes().len * cw, text_y, extra, gg.TextCfg{
			...ved.cfg.dim_cfg
			color: ved.cfg.git_added_color
		})
	}
	// little chevron
	ax := x + w - 14
	ved.gg.draw_triangle_filled(ax, mid - 2, ax + 7, mid - 2, ax + 4, mid + 2, c)
}

fn (mut ved Ved) draw_dropdown() {
	if ved.menu_open < 0 {
		return
	}
	x, y, w, h := ved.dropdown_rect()
	// soft shadow, then the popup itself
	ved.gg.draw_rounded_rect_filled(x + 2, y + 3, w, h, 6, gg.rgba(0, 0, 0, 60))
	ved.gg.draw_rounded_rect_filled(x - 1, y - 1, w + 2, h + 2, 6, ved.cfg.split_color)
	ved.gg.draw_rounded_rect_filled(x, y, w, h, 6, ved.cfg.popup_bgcolor)
	hover := ved.dropdown_item_at(ved.mouse_x, ved.mouse_y)
	cw := ved.cfg.char_width
	mut iy := y + 4
	for i, it in ved.menu_items(ved.menu_open) {
		ih := ved.item_height(it)
		if it.sep {
			ved.gg.draw_line(x + 10, iy + ih / 2, x + w - 10, iy + ih / 2, ved.cfg.split_color)
		} else if it.header {
			ved.gg.draw_text(x + 12, iy + 2, it.label, ved.cfg.dim_cfg)
		} else {
			if i == hover || i == ved.menu_sel {
				ved.gg.draw_rounded_rect_filled(x + 4, iy, w - 8, ih, 4, ved.cfg.active_color)
			}
			ty := iy + (ih - ved.cfg.line_height) / 2
			if it.checked {
				// check mark
				cx := x + 10
				cy := iy + ih / 2
				ved.gg.draw_line(cx, cy, cx + 3, cy + 3, ved.cfg.accent_color)
				ved.gg.draw_line(cx + 3, cy + 3, cx + 9, cy - 4, ved.cfg.accent_color)
			}
			ved.gg.draw_text(x + 28, ty, it.label, ved.cfg.txt_cfg)
			if it.shortcut != '' {
				ved.gg.draw_text(x + w - 16 - it.shortcut.len * cw, ty, it.shortcut,
					ved.cfg.dim_cfg)
			}
		}
		iy += ih
	}
}

// menu_mouse_down handles clicks while a dropdown is open or on the menu bar.
// Returns true when the click was used up.
fn (mut ved Ved) menu_mouse_down(mx int, my int) bool {
	h := ved.menu_bar_height()
	if ved.menu_open >= 0 {
		idx := ved.dropdown_item_at(mx, my)
		if idx >= 0 {
			it := ved.menu_items(ved.menu_open)[idx]
			ved.close_menu()
			ved.run_action(it.action, it.arg)
			return true
		}
		x, y, w, dh := ved.dropdown_rect()
		inside := mx >= x && mx < x + w && my >= y && my < y + dh
		if !inside && my >= h {
			ved.close_menu()
			return true
		}
		if inside {
			return true
		}
	}
	if my >= h {
		return false
	}
	if ved.branch_widget_w > 0 && mx >= ved.branch_widget_x
		&& mx < ved.branch_widget_x + ved.branch_widget_w {
		if ved.menu_open == branch_popup {
			ved.close_menu()
		} else {
			ved.open_menu(branch_popup)
		}
		return true
	}
	for i, m in ved.menus {
		x := ved.menu_title_x(i)
		if mx >= x - 2 && mx < x + m.title.len * ved.cfg.char_width + 18 {
			if ved.menu_open == i {
				ved.close_menu()
			} else {
				ved.open_menu(i)
			}
			return true
		}
	}
	ved.close_menu()
	return true
}

// menu_mouse_move switches between open menus while sliding over the bar.
fn (mut ved Ved) menu_mouse_move(mx int, my int) {
	if ved.menu_open < 0 || ved.menu_open == branch_popup || my >= ved.menu_bar_height() {
		return
	}
	for i, m in ved.menus {
		x := ved.menu_title_x(i)
		if mx >= x - 2 && mx < x + m.title.len * ved.cfg.char_width + 18 && i != ved.menu_open {
			ved.open_menu(i)
			return
		}
	}
}

// key_menu handles the keyboard while a dropdown is open.
fn (mut ved Ved) key_menu(key gg.KeyCode) {
	items := ved.menu_items(ved.menu_open)
	match key {
		.escape {
			ved.close_menu()
		}
		.up, .down {
			delta := if key == .up { -1 } else { 1 }
			mut i := ved.menu_sel
			for _ in 0 .. items.len {
				i += delta
				if i < 0 {
					i = items.len - 1
				}
				if i >= items.len {
					i = 0
				}
				if !items[i].sep && !items[i].header {
					break
				}
			}
			ved.menu_sel = i
		}
		.left, .right {
			if ved.menu_open != branch_popup {
				n := ved.menus.len
				ved.open_menu((ved.menu_open + (if key == .left { n - 1 } else { 1 })) % n)
			}
		}
		.enter {
			if ved.menu_sel >= 0 && ved.menu_sel < items.len {
				it := items[ved.menu_sel]
				ved.close_menu()
				ved.run_action(it.action, it.arg)
			}
		}
		else {}
	}
}

fn (mut ved Ved) copy_selection() {
	if ved.view.has_sel() {
		ved.cb.copy(ved.view.selected_text())
	} else {
		ved.cb.copy(ved.view.line() + '\n')
	}
}

fn (mut ved Ved) cut_selection() {
	mut view := ved.view
	view.push_undo(.other)
	ved.copy_selection()
	if view.has_sel() {
		view.delete_sel()
	} else {
		view.dd()
	}
}

fn (mut ved Ved) paste() {
	text := ved.cb.paste()
	if text == '' {
		return
	}
	mut view := ved.view
	view.push_undo(.other)
	view.delete_sel()
	view.insert_multiline(text)
}

fn (mut ved Ved) show_panel(panel LeftPanel) {
	if ved.cfg.show_file_tree && ved.left_panel == panel {
		ved.cfg.show_file_tree = false
		ved.commit_focus = false
		return
	}
	ved.cfg.show_file_tree = true
	ved.left_panel = panel
}

// run_action is what menu items do. Most of them mirror a key binding.
fn (mut ved Ved) run_action(action Action, arg string) {
	mut view := ved.view
	match action {
		.none {}
		.new_file {
			ved.open_query(.new_file)
		}
		.open_file {
			ved.open_query(.open)
		}
		.open_workspace {
			ved.open_query(.open_workspace)
		}
		.save {
			ved.save_all()
		}
		.reload {
			view.reopen()
		}
		.close_tab {
			ved.close_tab(view.path)
		}
		.exit {
			exit(0)
		}
		.undo {
			view.undo()
		}
		.redo {
			view.redo()
		}
		.cut {
			ved.cut_selection()
		}
		.copy {
			ved.copy_selection()
		}
		.paste {
			ved.paste()
		}
		.select_all {
			view.select_all()
		}
		.duplicate {
			view.push_undo(.other)
			view.duplicate()
		}
		.delete_line {
			view.push_undo(.other)
			view.clear_sel()
			view.dd()
		}
		.join_lines {
			view.push_undo(.other)
			view.join()
		}
		.comment {
			view.push_undo(.other)
			view.toggle_comment()
		}
		.find {
			ved.search_query = ''
			ved.search_dir = ''
			ved.open_query(.search)
		}
		.find_next {
			ved.search(.forward)
		}
		.find_prev {
			ved.search(.backward)
		}
		.find_in_files {
			ved.search_query = ''
			ved.open_query(.grep)
		}
		.toggle_tree {
			ved.show_panel(.project)
		}
		.toggle_commit {
			ved.show_panel(.commit)
		}
		.font_bigger {
			ved.increase_font(1)
		}
		.font_smaller {
			ved.increase_font(-1)
		}
		.fullscreen {
			ved.toggle_fullscreen()
		}
		.goto_file {
			ved.open_query(.ctrlp)
			ved.load_git_tree()
		}
		.goto_line {
			ved.open_query(.goto_line)
		}
		.goto_def {
			view.clear_sel()
			ved.go_to_def()
		}
		.matching_bracket {
			view.clear_sel()
			ved.pct()
		}
		.prev_file {
			view.tt()
		}
		.next_tab {
			ved.next_tab(1)
		}
		.prev_tab {
			ved.next_tab(-1)
		}
		.next_split {
			ved.next_split()
		}
		.prev_split {
			ved.prev_split()
		}
		.next_workspace {
			ved.open_workspace(ved.workspace_idx + 1)
		}
		.prev_workspace {
			ved.open_workspace(ved.workspace_idx - 1)
		}
		.git_commit {
			ved.cfg.show_file_tree = true
			ved.left_panel = .commit
			ved.commit_focus = true
			ved.refresh_git()
		}
		.git_push {
			ved.git_push()
		}
		.git_pull {
			ved.git_pull_async()
		}
		.git_fetch {
			ved.git_fetch()
		}
		.git_branches {
			ved.open_menu(branch_popup)
		}
		.git_new_branch {
			if ved.git.ok {
				ved.open_query(.new_branch)
			}
		}
		.git_diff {
			ved.git_show_diff(view.path)
		}
		.git_diff_all {
			ved.git_show_all_diff()
		}
		.git_history {
			ved.git_file_history(view.path)
		}
		.git_log {
			ved.git_log()
		}
		.git_rollback {
			if ved.git_kind_of(view.path) in [.modified, .deleted, .renamed, .conflict] {
				ved.open_query(.confirm_rollback)
			} else {
				ved.notify('No changes to roll back in ${os.base(view.path)}', true)
			}
		}
		.git_refresh {
			ved.refresh_git()
			ved.tree.reload()
		}
		.git_checkout {
			if arg != ved.git.branch {
				ved.git_checkout([arg])
			}
		}
		.git_checkout_remote {
			ved.git_checkout(['--track', arg])
		}
		.run_file {
			ved.run_file()
		}
		.build {
			ved.key_u()
		}
		.build2 {
			spawn ved.build_app2()
		}
		.run_command {
			ved.open_query(.run)
		}
		.debug {
			ved.mode = .debugger
			ved.run_debugger(view.breakpoints)
		}
		.breakpoint {
			view.add_breakpoint(view.y)
		}
		.new_task {
			ved.open_query(.task)
		}
		.timer {
			ved.timer.load_tasks()
			ved.mode = .timer
		}
		.copy_path {
			ved.cb.copy(view.path)
		}
		.shortcuts {
			ved.view.open_file(os.join_path(exe_dir, 'welcome.txt'), 0)
		}
	}
	ved.view.ensure_visible()
}
