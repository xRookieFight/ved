<h1 align="center">Ved</h1>
<h3 align="center">A small and fast text editor written in V</h3>

<img src="https://user-images.githubusercontent.com/47652746/199333211-ee78f600-039c-4d96-85ec-e5580fca6736.jpg" alt="Screenshot of the editor">

[![Patreon-badge](https://img.shields.io/badge/Patreon-F96854?logo=patreon&logoColor=white)](https://www.patreon.com/vlang)
![GitHub Workflow Status (event)](https://img.shields.io/github/actions/workflow/status/vlang/ved/ci.yml?branch=master)

### This is pre-alpha software.

I've been using Ved as my main editor since June 2017 (it was re-written in V in June 2018).

It may not work for everyone. There are currently limitations that must be worked around.
We are working on slowly improving the ved stability and user experience.

To configure the editor, please see the [configuration](#configuration) section.

### Building from source

On Linux, you will need to [install some packages](https://github.com/vlang/v?tab=readme-ov-file#testing-and-running-the-examples),
needed to use the X11 libraries, since Ved is a graphical application. On macos and windows, that can be skipped.
Then [install V](https://github.com/vlang/v#installing-v---from-source-preferred-method) and compile ved.
This will take a couple of seconds.

```
git clone https://github.com/vlang/ved
cd ved
v .
./ved
```

Ved should build in under a second.

By default V's built-in font rendering is used, but there's an option to use freetype,
which may provide better rendering for some users:

```
v -d use_freetype .
```

To use freetype, it must first be installed on your system.
Follow the steps for your platform below.

Ubuntu:
```
sudo apt install libfreetype6-dev libx11-dev libxrandr-dev mesa-common-dev libxi-dev libxcursor-dev
```

Fedora:
```
sudo dnf install freetype-devel libXcursor-devel libXi-devel
```

Arch:
```
pacman -S freetype2
```

macOS:
```
brew install freetype
```

Windows:
```
v setup-freetype
```

### Communities:

Discord (primary community): https://discord.gg/vlang. Join the `#ved` channel.

### Main features

- Small size (~ 1 MB binary, builds in <1s)
- Hardware accelerated text rendering
- High performance (scrolling through 300k lines with syntax highlighting without any lag)
- IDE style editing: file tree, tabs, mouse selection, undo/redo
- Easy integration with any compiler/build system
- Go to definition
- Fuzzy file finder
- Fast search
- Integration with git
- Built-in time management system (based on Pomodoro)
- Global bring-to-front key
- Split view
- Workspaces
- Cross-platform (Windows, macOS, GNU/Linux)

### Planned features

- Emacs keybindings
- Nano keybindings
- Word wrap
- Better syntax highlighting

### Configuration

Ved creates a settings directory in `$HOME/.ved` where it stores workspaces,
sessions, tasks, and the configuration file.
The configuration file is simply a [TOML](https://toml.io/) file called `conf.toml`.
It provides a way to change some basic settings and the editor colors.

If you don't want to touch the config file, you never have to!
Ved does not create it by itself and it provides sensible defaults to get you started.
If you are more adventurous, here is an example configuration file that contains all
of the possible settings:

```toml
# To get started, create a file called "conf.toml" in $HOME/.ved
# Most of the settings are contained inside this "editor" table.
[editor]
dark_mode = true        # Ved comes with a light and dark mode built-in. Dark is the default, use -light to switch.
cursor = 'variable'     # Ved has three variants: Variable, block, and beam. You are probably used to "variable" or "beam".
text_size = 18          # ┌───────────────────────────────────────────────────┐
line_height = 20        # │ These *can* be edited, but you probably shouldn't │
char_width = 8          # └───────────────────────────────────────────────────┘
tab_size = 4            # Ved uses tab characters (\t). This settings changes how many spaces a tab should be displayed as
backspace_go_up = true  # If set to true, hitting the backspace doesn't do anything when you reach the beginning of the line

# If you do not like ved's default colorscheme, or you just want
# something new, edit the "colors" table. Ved uses a form of base16
# to control syntax and editor highlighting. Please note that due
# to ved's very minimal highlighting, base16 themes copied off of
# the internet are not going to look like very much like their
# screenshots.
[colors]
base00 = "efecf4"
base01 = "e2dfe7"
base02 = "8b8792"
base03 = "7e7887"
base04 = "655f6d"
base05 = "585260"
base06 = "26232a"
base07 = "19171c"
base08 = "be4678"
base09 = "aa573c"
base0A = "a06e3b"
base0B = "2a9292"
base0C = "398bc6"
base0D = "576ddb"
base0E = "955ae7"
base0F = "bf40bf"
```

### Basic usage

Ved works best with workspaces (directories with code).
You can have multiple workspaces and quickly switch between them with `C [` and `C ]`.

To open multiple workspaces, run

`ved path/to/project1 path/to/project2`

Key bindings follow IntelliJ's default keymap.
`C` is `⌘` on macOS, `Ctrl` on all other systems, `S` is Shift and `A` is Alt.

Editing works like in any IDE: just type. The menu bar on top has every
command, Alt plus the first letter of a menu opens it (A f for File). Hold Shift with the movement keys
or drag with the mouse to select. Click files in the tree on the left to open
them, they show up as tabs on top.

```
Editing:

C s            save (unsaved files in other tabs too)
C z  C S z     undo, redo
C c  C x  C v  copy, cut, paste (the whole line when nothing is selected)
C a            select all
C d            duplicate line or selection
C y            delete line
C /            comment/uncomment lines
C S j          join lines
S Enter        new line below
C A Enter      new line above
Tab  S Tab     indent, unindent selected lines
A q            reflow selected lines to 80 columns
C Space        complete the word from words in the file

Navigation:

C Left/Right   previous/next word
Home  End      start/end of line
C Home/End     start/end of file
C g            go to line
C b            go to definition (or C click)
C S m          go to matching bracket
C e            go to the previously opened file
A Left/Right   previous/next tab (also C Tab, C S Tab)
C w            close tab (also C F4, middle click)
A 1            show/hide the file tree
A S Left/Right previous/next split
C [  C ]       previous/next workspace

Search:

C f            find in file (F3, S F3 for next/previous)
C F3           find the word under the cursor
C S f          find in workspace (git grep)
C A f          find in the current file's folder
C p  C S n     go to file (fuzzy search)
C o            open a file by path
C S o          open a workspace

Git (also in the Git menu, the branch widget on the top right switches branches):

C k            commit: opens the Commit panel, C Enter commits, C A Enter commits and pushes
C S k          push
C S p          update project (git pull --rebase)
C S d          show diff of the current file
C A z          roll back the current file
A 0            show/hide the Commit panel
A 9            show the git log
C -  C A d     git diff of the workspace

Tools:

C u  C F9      build current project (build instructions must be located in "build")
C S F9         alternative build (instructions in "build2")
F5  S F10      run current file
C S r  A F12   run a shell command
C F8           toggle breakpoint
S F9  C S u    start the debugger, F8 steps over
C r            reload current file from disk
C S c          copy current file's path to clipboard
C S =  C S -   bigger/smaller font
C Enter  F11   toggle fullscreen
C 0            start a new task
C t            show the Timer/Pomodoro window
C q q          exit the editor
```

