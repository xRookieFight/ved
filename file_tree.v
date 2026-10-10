module main

import os
import gg

struct Node {
mut:
	path     string
	name     string
	is_dir   bool
	expanded bool
	loaded   bool
	children []int // index of the nodes in []Node array
	depth    int
}

struct Tree {
mut:
	nodes         []Node
	visible_nodes []int
	root          int
	scroll        int // index of the first visible row
	selected      int = -1 // last clicked node
	hover         int = -1 // row under the mouse, relative to the first visible row
}

const tree_indent = 14
const tree_arrow_size = 7
const tree_icon_size = 12

fn (mut t Tree) init(workspace_path string) {
	t.nodes.clear()
	t.nodes << Node{
		path:     workspace_path
		name:     os.base(workspace_path)
		is_dir:   true
		expanded: true
		depth:    0
	}
	t.root = 0
	t.scroll = 0
	t.selected = -1
	t.load_children(t.root)
	t.compute_visible_nodes()
}

// reload re-reads the directories, keeping the expanded folders open.
// Used when files appear or disappear (new file, checkout, pull).
fn (mut t Tree) reload() {
	if t.nodes.len == 0 {
		return
	}
	mut open := map[string]bool{}
	for n in t.nodes {
		if n.is_dir && n.expanded {
			open[n.path] = true
		}
	}
	scroll := t.scroll
	t.init(t.nodes[0].path)
	mut i := 0
	for i < t.nodes.len {
		if t.nodes[i].is_dir && t.nodes[i].path in open && i != t.root {
			t.nodes[i].expanded = true
			t.load_children(i)
		}
		i++
	}
	t.compute_visible_nodes()
	t.scroll = scroll
}

// load_children reads a directory once, folders first, then files, both sorted by name.
fn (mut t Tree) load_children(node_idx int) {
	node := t.nodes[node_idx]
	if !node.is_dir || node.loaded {
		return
	}
	t.nodes[node_idx].loaded = true
	mut entries := os.ls(node.path) or { return }
	entries = entries.filter(it != '.git')
	mut dirs := []string{}
	mut files := []string{}
	for entry in entries {
		if os.is_dir(os.join_path(node.path, entry)) {
			dirs << entry
		} else {
			files << entry
		}
	}
	dirs.sort_ignore_case()
	files.sort_ignore_case()
	nr_dirs := dirs.len
	dirs << files
	for i, entry in dirs {
		t.nodes << Node{
			path:   os.join_path(node.path, entry)
			name:   entry
			is_dir: i < nr_dirs
			depth:  node.depth + 1
		}
		t.nodes[node_idx].children << t.nodes.len - 1
	}
}

fn (mut t Tree) compute_visible_nodes() {
	t.visible_nodes.clear()
	mut stack := []int{}
	stack << t.root
	for stack.len > 0 {
		idx := stack.pop()
		t.visible_nodes << idx
		node := t.nodes[idx]
		if node.is_dir && node.expanded {
			for i := node.children.len - 1; i >= 0; i-- {
				stack << node.children[i]
			}
		}
	}
}

fn (mut t Tree) scroll_by(delta int, rows int) {
	t.scroll += delta
	max_scroll := t.visible_nodes.len - rows
	if t.scroll > max_scroll {
		t.scroll = max_scroll
	}
	if t.scroll < 0 {
		t.scroll = 0
	}
}

// Initialize the tree when workspace is set:
fn (mut ved Ved) init_tree() {
	ved.tree.init(ved.workspace)
}

fn (ved &Ved) tree_row_height() int {
	return ved.cfg.line_height + 6
}

// tree_hover_at remembers which row is under the mouse, for the hover highlight.
fn (mut ved Ved) tree_hover_at(mx int, my int) {
	if mx >= ved.tree_width() || my < ved.tab_bar_bottom() {
		ved.tree.hover = -1
		return
	}
	ved.tree.hover = (my - ved.tab_bar_bottom()) / ved.tree_row_height()
}

// tree_rows is how many rows fit in the panel.
fn (ved &Ved) tree_rows() int {
	h := ved.win_height - ved.tab_bar_bottom() - ved.status_bar_height()
	return h / ved.tree_row_height()
}

// tree_click opens a file or folds/unfolds a folder.
fn (mut ved Ved) tree_click(my int) {
	if my < ved.tab_bar_bottom() {
		return
	}
	row := (my - ved.tab_bar_bottom()) / ved.tree_row_height() + ved.tree.scroll
	if row < 0 || row >= ved.tree.visible_nodes.len {
		return
	}
	idx := ved.tree.visible_nodes[row]
	ved.tree.selected = idx
	node := ved.tree.nodes[idx]
	if node.is_dir {
		ved.tree.nodes[idx].expanded = !node.expanded
		if ved.tree.nodes[idx].expanded {
			ved.tree.load_children(idx)
		}
		ved.tree.compute_visible_nodes()
		ved.tree.scroll_by(0, ved.tree_rows())
	} else {
		ved.open_tab(node.path)
	}
}

// file_icon_color picks a badge color per file type, roughly the colors IDEs use.
fn file_icon_color(name string) gg.Color {
	return match os.file_ext(name) {
		'.v', '.vv', '.vsh' { gg.rgb(93, 135, 191) }
		'.go' { gg.rgb(0, 173, 216) }
		'.c', '.h', '.cpp', '.hpp', '.cc' { gg.rgb(101, 154, 210) }
		'.rs' { gg.rgb(222, 165, 132) }
		'.js', '.ts', '.json' { gg.rgb(214, 186, 78) }
		'.py' { gg.rgb(76, 140, 191) }
		'.md', '.txt' { gg.rgb(150, 150, 150) }
		'.html', '.css', '.scss' { gg.rgb(227, 108, 78) }
		'.sh', '.toml', '.yml', '.yaml' { gg.rgb(130, 170, 100) }
		'.png', '.jpg', '.svg', '.ico', '.icns' { gg.rgb(178, 120, 200) }
		else { gg.rgb(130, 130, 130) }
	}
}

// draw_folder_icon draws a small folder: a tab on top of a rounded body.
fn (ved &Ved) draw_folder_icon(x int, y int, open bool) {
	s := tree_icon_size
	color := if ved.cfg.dark_mode { gg.rgb(135, 160, 195) } else { gg.rgb(100, 125, 165) }
	ved.gg.draw_rounded_rect_filled(x, y + 1, s / 2, 4, 1, color)
	if open {
		ved.gg.draw_rounded_rect_filled(x, y + 3, s, s - 4, 2, color)
		ved.gg.draw_rect_filled(x + 2, y + 6, s - 4, 1, ved.cfg.panel_color)
	} else {
		ved.gg.draw_rounded_rect_filled(x, y + 3, s, s - 4, 2, color)
	}
}

// draw_file_icon draws a page with a colored band, the color says what kind of file it is.
fn (ved &Ved) draw_file_icon(x int, y int, name string) {
	s := tree_icon_size
	page := if ved.cfg.dark_mode { gg.rgb(110, 115, 120) } else { gg.rgb(165, 170, 175) }
	ved.gg.draw_rounded_rect_filled(x + 1, y, s - 2, s, 2, page)
	ved.gg.draw_rounded_rect_filled(x, y + s / 2 - 1, s, s / 2 + 1, 2, file_icon_color(name))
}

// draw draws the tree rows, the panel and its header come from draw_left_panel.
fn (mut t Tree) draw(mut ved Ved) {
	w := ved.tree_width()
	header_h := ved.tab_bar_bottom()
	lh := ved.cfg.line_height
	row_h := ved.tree_row_height()
	cw := ved.cfg.char_width
	rows := ved.tree_rows()
	guide_color := if ved.cfg.dark_mode { gg.rgb(60, 63, 66) } else { gg.rgb(215, 215, 215) }
	hover_color := ved.cfg.hover_color
	active_color := ved.cfg.active_color
	for r := 0; r < rows && t.scroll + r < t.visible_nodes.len; r++ {
		idx := t.visible_nodes[t.scroll + r]
		node := t.nodes[idx]
		y := header_h + r * row_h
		is_active := !node.is_dir && node.path == ved.view.path
		if is_active {
			ved.gg.draw_rect_filled(0, y, w, row_h, active_color)
			ved.gg.draw_rect_filled(0, y, 3, row_h, ved.cfg.accent_color)
		} else if idx == t.selected {
			ved.gg.draw_rect_filled(0, y, w, row_h, ved.cfg.vcolor)
		} else if r == t.hover {
			ved.gg.draw_rect_filled(0, y, w, row_h, hover_color)
		}
		// indent guides, one thin line per parent level
		for d := 1; d < node.depth; d++ {
			gx := 12 + d * tree_indent + tree_arrow_size / 2
			ved.gg.draw_line(gx, y, gx, y + row_h, guide_color)
		}
		x := 12 + node.depth * tree_indent
		mid := y + row_h / 2
		if node.is_dir {
			a := tree_arrow_size
			if node.expanded {
				ved.gg.draw_triangle_filled(x, mid - a / 3, x + a, mid - a / 3, x + a / 2, mid +
					a / 3, ved.cfg.dim_cfg.color)
			} else {
				ved.gg.draw_triangle_filled(x + a / 4, mid - a / 2, x + a / 4, mid + a / 2,
					x + a * 3 / 4 + 1, mid, ved.cfg.dim_cfg.color)
			}
		}
		icon_x := x + tree_arrow_size + 5
		icon_y := mid - tree_icon_size / 2
		if node.is_dir {
			ved.draw_folder_icon(icon_x, icon_y, node.expanded)
		} else {
			ved.draw_file_icon(icon_x, icon_y, node.name)
		}
		text_x := icon_x + tree_icon_size + 7
		// keep long names inside the panel
		max_chars := (w - text_x - 8) / cw
		if max_chars <= 0 {
			continue
		}
		mut name := node.name
		if name.runes().len > max_chars {
			name = name.runes()[..max_chars - 1].string() + '…'
		}
		// git status colors, folders holding changes are tinted like modified files
		kind := if node.is_dir {
			if node.path in ved.git_dirs { GitKind.modified } else { GitKind.none }
		} else {
			ved.git_kind_of(node.path)
		}
		cfg := if kind != .none {
			ved.git_text_cfg(kind)
		} else if node.name.starts_with('.') {
			ved.cfg.dim_cfg
		} else {
			ved.cfg.txt_cfg
		}
		ved.gg.draw_text(text_x, y + (row_h - lh) / 2, name, cfg)
	}
	// thin scrollbar when the tree doesn't fit
	total := t.visible_nodes.len
	if total > rows && rows > 0 {
		track_h := rows * row_h
		thumb_h := int_max(track_h * rows / total, 20)
		thumb_y := header_h + (track_h - thumb_h) * t.scroll / int_max(total - rows, 1)
		ved.gg.draw_rounded_rect_filled(w - 7, thumb_y, 4, thumb_h, 2, guide_color)
	}
}
