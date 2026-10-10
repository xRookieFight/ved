module main

import os
import time
import rand

// Git integration. Everything that runs git happens on a spawned thread and the
// result comes back through a channel that frame() drains, so a slow repo never
// freezes the UI and the main thread is the only one touching editor state.

enum GitKind {
	none
	modified
	added
	deleted
	renamed
	untracked
	conflict
}

struct GitFile {
	path string // full path
	rel  string // relative to the repo root, what git commands want
	kind GitKind
}

struct GitStatus {
	ok       bool // false when the workspace is not inside a git repo
	root     string
	branch   string
	upstream string
	ahead    int
	behind   int
	files    []GitFile
}

// LineChanges marks lines of a buffer that differ from HEAD: `a`dded, `m`odified,
// or `d`eleted (lines were removed right above that line).
struct LineChanges {
	path  string
	seq   int
	marks map[int]u8
}

// Note is a balloon notification shown in the bottom right corner.
struct Note {
	text     string
	is_error bool
	refresh  bool // git state changed, refresh the status
mut:
	until_ms i64
}

fn git_exec(root string, args []string) os.Result {
	mut cmd := ['git', '-C', root]
	cmd << args
	return os.exec(cmd)
}

fn git_kind(x u8, y u8) GitKind {
	if x == `?` {
		return .untracked
	}
	if x == `U` || y == `U` || (x == `A` && y == `A`) || (x == `D` && y == `D`) {
		return .conflict
	}
	if x == `R` {
		return .renamed
	}
	if x == `A` {
		return .added
	}
	if x == `D` || y == `D` {
		return .deleted
	}
	return .modified
}

// parse_git_status reads `git status --porcelain=v1 --branch -z` output.
fn parse_git_status(root string, out string) GitStatus {
	entries := out.split('\0')
	mut branch := ''
	mut upstream := ''
	mut ahead := 0
	mut behind := 0
	mut files := []GitFile{}
	mut i := 0
	for i < entries.len {
		e := entries[i]
		i++
		if e.len < 3 {
			continue
		}
		if e.starts_with('## ') {
			mut head := e[3..]
			if bracket := head.index(' [') {
				info := head[bracket + 2..].trim_right(']')
				for part in info.split(', ') {
					if part.starts_with('ahead ') {
						ahead = part[6..].int()
					} else if part.starts_with('behind ') {
						behind = part[7..].int()
					}
				}
				head = head[..bracket]
			}
			if dots := head.index('...') {
				upstream = head[dots + 3..]
				head = head[..dots]
			}
			// a fresh repo says "No commits yet on main"
			branch = head.all_after('No commits yet on ')
			continue
		}
		kind := git_kind(e[0], e[1])
		rel := e[3..]
		if kind == .renamed {
			i++ // the old name follows as its own entry
		}
		files << GitFile{
			path: os.join_path(root, rel)
			rel:  rel
			kind: kind
		}
	}
	return GitStatus{
		ok:       true
		root:     root
		branch:   branch
		upstream: upstream
		ahead:    ahead
		behind:   behind
		files:    files
	}
}

fn git_status_job(workspace string, ch chan GitStatus) {
	top := os.exec(['git', '-C', workspace, 'rev-parse', '--show-toplevel'])
	if top.exit_code != 0 {
		ch <- GitStatus{}
		return
	}
	root := top.output.trim_space()
	res := git_exec(root, ['status', '--porcelain=v1', '--branch', '-z', '--untracked-files=all'])
	if res.exit_code != 0 {
		ch <- GitStatus{}
		return
	}
	ch <- parse_git_status(root, res.output)
}

// parse_hunks turns `git diff -U0` output into line marks for the new file.
fn parse_hunks(diff string, nr_lines int) map[int]u8 {
	mut marks := map[int]u8{}
	for line in diff.split_into_lines() {
		if !line.starts_with('@@ ') {
			continue
		}
		// @@ -a,b +c,d @@
		fields := line.fields()
		if fields.len < 3 {
			continue
		}
		old := fields[1][1..].split(',')
		new := fields[2][1..].split(',')
		old_count := if old.len > 1 { old[1].int() } else { 1 }
		start := new[0].int()
		new_count := if new.len > 1 { new[1].int() } else { 1 }
		if new_count == 0 {
			// lines removed after line `start`, show it on the next line
			mut idx := start
			if idx >= nr_lines {
				idx = nr_lines - 1
			}
			if idx >= 0 && idx !in marks {
				marks[idx] = `d`
			}
			continue
		}
		kind := if old_count == 0 { `a` } else { `m` }
		for j := start - 1; j < start - 1 + new_count; j++ {
			marks[j] = kind
		}
	}
	return marks
}

fn line_changes_job(root string, path string, lines []string, seq int, ch chan LineChanges) {
	rel := path[root.len..].trim_left('/')
	head := git_exec(root, ['show', 'HEAD:${rel}'])
	if head.exit_code != 0 {
		// new or untracked file, the tree and tab colors already say so
		ch <- LineChanges{
			path: path
			seq:  seq
		}
		return
	}
	id := rand.u64()
	head_tmp := os.join_path(os.vtmp_dir(), 'ved_head_${id}')
	buf_tmp := os.join_path(os.vtmp_dir(), 'ved_buf_${id}')
	defer {
		os.rm(head_tmp) or {}
		os.rm(buf_tmp) or {}
	}
	os.write_file(head_tmp, head.output) or { return }
	os.write_file(buf_tmp, lines.join('\n') + '\n') or { return }
	diff := os.exec(['git', 'diff', '--no-index', '--no-color', '-U0', head_tmp, buf_tmp])
	ch <- LineChanges{
		path:  path
		seq:   seq
		marks: parse_hunks(diff.output, lines.len)
	}
}

// git_async runs a git command that may take a while (push, pull, fetch) and
// reports back with a notification.
fn git_async(root string, args []string, done string, ch chan Note) {
	res := git_exec(root, args)
	if res.exit_code == 0 {
		ch <- Note{
			text:    done
			refresh: true
		}
	} else {
		ch <- Note{
			text:     'git ${args[0]} failed: ${last_line(res.output)}'
			is_error: true
			refresh:  true
		}
	}
}

fn last_line(s string) string {
	lines := s.split_into_lines().filter(it.trim_space() != '')
	return if lines.len > 0 { lines.last().trim_space() } else { '' }
}

fn (mut ved Ved) notify(text string, is_error bool) {
	ved.notes << Note{
		text:     text
		is_error: is_error
		until_ms: time.ticks() + 5000
	}
}

fn (mut ved Ved) refresh_git() {
	ved.git_last_refresh = 0
}

// poll_git is called every frame. It applies finished jobs and starts new ones.
fn (mut ved Ved) poll_git() {
	now := time.ticks()
	for {
		mut st := GitStatus{}
		if ved.git_ch.try_pop(mut st) != .success {
			break
		}
		ved.apply_git_status(st)
		ved.git_busy = false
	}
	for {
		mut lc := LineChanges{}
		if ved.lines_ch.try_pop(mut lc) != .success {
			break
		}
		for i, v in ved.views {
			if v.path == lc.path && v.git_req_seq == lc.seq {
				ved.views[i].git_marks = lc.marks.clone()
			}
		}
	}
	for {
		mut note := Note{}
		if ved.note_ch.try_pop(mut note) != .success {
			break
		}
		note.until_ms = now + 5000
		ved.notes << note
		if note.refresh {
			ved.refresh_git()
			ved.reload_unchanged_views()
		}
	}
	ved.notes = ved.notes.filter(it.until_ms > now)
	if !ved.git_busy && now - ved.git_last_refresh > 3000 && ved.workspace != '' {
		ved.git_busy = true
		ved.git_last_refresh = now
		spawn git_status_job(ved.workspace, ved.git_ch)
	}
	if !ved.git.ok {
		return
	}
	from, to := ved.get_splits_from_to()
	for i := from; i < to && i < ved.views.len; i++ {
		v := ved.views[i]
		if v.path == '' || !v.path.starts_with(ved.git.root + '/') || v.git_req_seq == v.edit_seq
			|| now - v.last_edit_ms < 400 {
			continue
		}
		// the job gets its own copy of the line array, the strings are shared
		mut lines := []string{len: v.lines.len}
		copy(mut lines, v.lines)
		ved.views[i].git_req_seq = v.edit_seq
		spawn line_changes_job(ved.git.root, v.path, lines, v.edit_seq, ved.lines_ch)
	}
}

fn (mut ved Ved) apply_git_status(st GitStatus) {
	mut sig := st.branch
	for f in st.files {
		sig += '\n${f.rel}:${int(f.kind)}'
	}
	changed := sig != ved.git_sig
	ved.git_sig = sig
	ved.git = st
	ved.git_kinds = map[string]GitKind{}
	ved.git_dirs = map[string]bool{}
	for f in st.files {
		ved.git_kinds[f.path] = f.kind
		mut dir := os.dir(f.path)
		for dir.len > st.root.len && dir !in ved.git_dirs {
			ved.git_dirs[dir] = true
			dir = os.dir(dir)
		}
	}
	// drop commit checkboxes of files that are no longer changed
	for path in ved.commit_excluded.keys() {
		if path !in ved.git_kinds {
			ved.commit_excluded.delete(path)
		}
	}
	// a commit or checkout moves HEAD, the line marks have to be recomputed
	if changed {
		for mut v in ved.views {
			v.edit_seq++
		}
	}
}

// reload_unchanged_views picks up files changed on disk by git (pull, checkout, rollback).
fn (mut ved Ved) reload_unchanged_views() {
	for mut v in ved.views {
		if v.path != '' && !v.changed && os.exists(v.path) {
			v.reopen()
		}
	}
	ved.tree.reload()
}

fn (ved &Ved) git_rel(path string) string {
	return path[ved.git.root.len..].trim_left('/')
}

fn (ved &Ved) git_kind_of(path string) GitKind {
	return ved.git_kinds[path] or { GitKind.none }
}

// Git actions

fn (mut ved Ved) git_push() {
	if !ved.git.ok {
		return
	}
	push_args := if ved.git.upstream == '' {
		['push', '-u', 'origin', 'HEAD']
	} else {
		['push']
	}
	ved.notify('Pushing ${ved.git.branch}...', false)
	spawn git_async(ved.git.root, push_args, 'Pushed ${ved.git.branch}', ved.note_ch)
}

fn (mut ved Ved) git_pull_async() {
	if !ved.git.ok {
		return
	}
	ved.notify('Pulling...', false)
	spawn git_async(ved.git.root, ['pull', '--rebase'], 'Pulled ${ved.git.branch}', ved.note_ch)
}

fn (mut ved Ved) git_fetch() {
	if !ved.git.ok {
		return
	}
	spawn git_async(ved.git.root, ['fetch', '--all', '--prune'], 'Fetched all remotes',
		ved.note_ch)
}

// git_commit_selected commits the checked files of the commit panel.
fn (mut ved Ved) git_commit_selected(push bool) {
	msg := ved.commit_msg.trim_space()
	if msg == '' && !ved.commit_amend {
		ved.notify('Commit message is empty', true)
		return
	}
	mut rels := []string{}
	for f in ved.git.files {
		if f.path !in ved.commit_excluded {
			rels << f.rel
		}
	}
	if rels.len == 0 && !ved.commit_amend {
		ved.notify('No files selected', true)
		return
	}
	ved.save_all()
	if rels.len > 0 {
		mut add := ['add', '-A', '--']
		add << rels
		res := git_exec(ved.git.root, add)
		if res.exit_code != 0 {
			ved.notify('git add failed: ${last_line(res.output)}', true)
			return
		}
	}
	mut commit := ['commit']
	if ved.commit_amend {
		commit << '--amend'
		if msg == '' {
			commit << '--no-edit'
		}
	}
	if msg != '' {
		commit << ['-m', msg]
	}
	if rels.len > 0 {
		commit << '--'
		commit << rels
	}
	res := git_exec(ved.git.root, commit)
	if res.exit_code != 0 {
		ved.notify('Commit failed: ${last_line(res.output)}', true)
		return
	}
	n := rels.len
	ved.notify('Committed ${n} file' + if n == 1 { '' } else { 's' }, false)
	ved.commit_msg = ''
	ved.commit_amend = false
	ved.commit_focus = false
	ved.refresh_git()
	if push {
		ved.git_push()
	}
}

fn (mut ved Ved) git_checkout(args []string) {
	mut cmd := ['checkout']
	cmd << args
	res := git_exec(ved.git.root, cmd)
	if res.exit_code != 0 {
		ved.notify('Checkout failed: ${last_line(res.output)}', true)
		return
	}
	ved.notify('Checked out ${args.last()}', false)
	ved.refresh_git()
	ved.reload_unchanged_views()
}

// open_git_output writes command output to a scratch file and opens it as a tab.
// The extension picks the coloring: .diff gets +/- colors.
fn (mut ved Ved) open_git_output(name string, text string) {
	dir := os.join_path(settings_dir, 'git')
	os.mkdir_all(dir) or {}
	path := os.join_path(dir, name)
	os.write_file(path, if text == '' { 'No changes\n' } else { text }) or {
		ved.notify('cannot write ${path}', true)
		return
	}
	ved.view.open_file(path, 0)
}

fn (mut ved Ved) git_show_diff(path string) {
	if !ved.git.ok || path == '' {
		return
	}
	rel := ved.git_rel(path)
	res := if ved.git_kind_of(path) == .untracked {
		os.exec(['git', '-C', ved.git.root, 'diff', '--no-color', '--no-index', '/dev/null', rel])
	} else {
		git_exec(ved.git.root, ['diff', '--no-color', 'HEAD', '--', rel])
	}
	ved.open_git_output('${os.base(path)}.diff', res.output)
}

fn (mut ved Ved) git_show_all_diff() {
	if !ved.git.ok {
		return
	}
	res := git_exec(ved.git.root, ['diff', '--no-color', 'HEAD'])
	ved.open_git_output('changes.diff', res.output)
}

fn (mut ved Ved) git_file_history(path string) {
	if !ved.git.ok || path == '' {
		return
	}
	res := git_exec(ved.git.root, ['log', '--date=short', '--pretty=format:%h  %ad  %<(14,trunc)%an  %s',
		'--', ved.git_rel(path)])
	ved.open_git_output('${os.base(path)}.history', res.output)
}

fn (mut ved Ved) git_log() {
	if !ved.git.ok {
		return
	}
	res := git_exec(ved.git.root, ['log', '--graph', '--date=short', '-n', '300',
		'--pretty=format:%h %ad %<(14,trunc)%an %s%d'])
	ved.open_git_output('git.log', res.output)
}

fn (mut ved Ved) git_rollback(path string) {
	kind := ved.git_kind_of(path)
	if kind in [.none, .untracked, .added] {
		ved.notify('Nothing to roll back in ${os.base(path)}', true)
		return
	}
	res := git_exec(ved.git.root, ['checkout', 'HEAD', '--', ved.git_rel(path)])
	if res.exit_code != 0 {
		ved.notify('Rollback failed: ${last_line(res.output)}', true)
		return
	}
	ved.stash.delete(path)
	for mut v in ved.views {
		if v.path == path {
			v.changed = false
			v.reopen()
		}
	}
	ved.notify('Rolled back ${os.base(path)}', false)
	ved.refresh_git()
}

// load_branch_items fills the branch popup: actions on top, then local and remote branches.
fn (mut ved Ved) load_branch_items() {
	mut items := []MenuItem{}
	items << MenuItem{
		label:  'New Branch...'
		action: .git_new_branch
	}
	items << MenuItem{
		label:  'Fetch'
		action: .git_fetch
	}
	items << MenuItem{
		label:  'Update Project'
		action: .git_pull
	}
	items << MenuItem{
		label:  'Push'
		action: .git_push
	}
	items << MenuItem{
		sep: true
	}
	items << MenuItem{
		label:  'Local'
		header: true
	}
	local := git_exec(ved.git.root, ['branch', '--format=%(refname:short)'])
	for b in local.output.split_into_lines() {
		if b.trim_space() == '' {
			continue
		}
		items << MenuItem{
			label:   b
			action:  .git_checkout
			arg:     b
			checked: b == ved.git.branch
		}
	}
	remote := git_exec(ved.git.root, ['branch', '-r', '--format=%(refname:short)'])
	mut remotes := remote.output.split_into_lines().filter(it.trim_space() != ''
		&& !it.ends_with('/HEAD') && it.contains('/'))
	if remotes.len > 0 {
		items << MenuItem{
			label:  'Remote'
			header: true
		}
		for b in remotes {
			items << MenuItem{
				label:  b
				action: .git_checkout_remote
				arg:    b
			}
		}
	}
	ved.branch_items = items
}
