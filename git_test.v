module main

fn test_parse_git_status() {
	out := '## main...origin/main [ahead 2, behind 1]\0 M src/a.v\0A  b.v\0?? new.txt\0R  c.v\0old_c.v\0 D gone.v\0'
	st := parse_git_status('/repo', out)
	assert st.ok
	assert st.branch == 'main'
	assert st.upstream == 'origin/main'
	assert st.ahead == 2
	assert st.behind == 1
	assert st.files.map(it.rel) == ['src/a.v', 'b.v', 'new.txt', 'c.v', 'gone.v']
	assert st.files.map(it.kind) == [GitKind.modified, .added, .untracked, .renamed, .deleted]
	assert st.files[0].path == '/repo/src/a.v'
}

fn test_parse_git_status_new_repo() {
	st := parse_git_status('/repo', '## No commits yet on main\0')
	assert st.branch == 'main'
	assert st.upstream == ''
	assert st.files.len == 0
}

fn test_parse_hunks() {
	diff := 'diff --git a/x b/x\n@@ -3 +3 @@\n-old\n+new\n@@ -10,0 +11,2 @@\n+a\n+b\n@@ -20,2 +21,0 @@\n-x\n-y\n'
	marks := parse_hunks(diff, 30)
	assert marks[2] == `m`
	assert marks[10] == `a`
	assert marks[11] == `a`
	assert marks[21] == `d`
	assert 3 !in marks
}
