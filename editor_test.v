module main

// new_test_view gives a view wired to a bare Ved, enough for the editing code.
fn new_test_view(lines []string) &View {
	mut ved := &Ved{
		nr_splits: 1
	}
	ved.cfg.tab_size = 4
	ved.views << ved.new_view()
	ved.update_view()
	mut view := ved.view
	view.lines = lines.clone()
	view.page_height = 10
	return view
}

fn test_typing_is_one_undo_step() {
	mut view := new_test_view(['ab'])
	view.x = 2
	mut ved := view.ved
	ved.type_text('c')
	ved.type_text('d')
	assert view.lines == ['abcd']
	view.undo()
	assert view.lines == ['ab']
	assert view.x == 2
	view.redo()
	assert view.lines == ['abcd']
}

fn test_typing_replaces_selection() {
	mut view := new_test_view(['hello world'])
	view.sel_y = 0
	view.sel_x = 0
	view.x = 5
	mut ved := view.ved
	ved.type_text('bye')
	assert view.lines == ['bye world']
	assert !view.has_sel()
}

fn test_selection_across_lines() {
	mut view := new_test_view(['one', 'two', 'three'])
	view.sel_y = 2
	view.sel_x = 2
	view.y = 0
	view.x = 1
	assert view.selected_text() == 'ne\ntwo\nth'
	view.delete_sel()
	assert view.lines == ['oree']
	assert view.y == 0
	assert view.x == 1
}

fn test_paste_multiline() {
	mut view := new_test_view(['ab'])
	view.x = 1
	view.insert_multiline('1\n2\r\n3')
	assert view.lines == ['a1', '2', '3b']
	assert view.y == 2
	assert view.x == 1
}

fn test_enter_keeps_indent_and_splits_braces() {
	mut view := new_test_view(['\tfn x() {}'])
	view.x = 9
	view.enter()
	assert view.lines == ['\tfn x() {', '\t\t', '\t}']
	assert view.y == 1
	assert view.x == 2
	mut plain := new_test_view(['\tfoo bar'])
	plain.x = 4
	plain.enter()
	assert plain.lines == ['\tfoo', '\tbar']
	assert plain.x == 1
}

fn test_backspace_joins_lines() {
	mut view := new_test_view(['ab', 'cd'])
	view.y = 1
	view.x = 0
	view.backspace()
	assert view.lines == ['abcd']
	assert view.x == 2
}

fn test_word_movement() {
	mut view := new_test_view(['foo.bar  baz'])
	view.word_right()
	assert view.x == 3
	view.word_right()
	assert view.x == 4
	view.word_right()
	assert view.x == 9
	view.word_left()
	assert view.x == 4
}

fn test_columns_with_tabs() {
	line := '\t\tab'
	assert visual_col(line, 2, 4) == 8
	assert visual_col(line, 3, 4) == 9
	assert x_for_col(line, 9, 4) == 3
	assert x_for_col(line, 1, 4) == 0
	assert x_for_col(line, 100, 4) == 4
}

fn test_vertical_movement_keeps_column() {
	mut view := new_test_view(['abcdef', 'ab', 'abcdef'])
	view.x = 5
	view.move_vert(1)
	assert view.x == 2
	view.move_vert(1)
	assert view.x == 5
}

fn test_toggle_comment() {
	mut view := new_test_view(['\tfoo()', '\tbar()'])
	view.path = 'a.v'
	view.sel_y = 0
	view.sel_x = 0
	view.y = 1
	view.x = 3
	view.toggle_comment()
	assert view.lines == ['\t// foo()', '\t// bar()']
	view.toggle_comment()
	assert view.lines == ['\tfoo()', '\tbar()']
}

fn test_delete_last_line_keeps_buffer() {
	mut view := new_test_view(['only'])
	view.dd()
	assert view.lines == ['']
	assert view.x == 0
}
