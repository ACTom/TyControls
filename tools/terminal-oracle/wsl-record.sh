#!/bin/bash
# Records one real program session for the oracle, in WSL, through tmux.
#
#   wsl-record.sh NAME WIDTH HEIGHT KEYSFILE
#   (from Windows: wsl.exe -d Ubuntu -- bash /mnt/d/Projects/ty-3.1/tools/terminal-oracle/wsl-record.sh ...)
#
# A tmux server on its own socket (-L tyrec) runs a WIDTH x HEIGHT session whose
# shell starts with a scrubbed environment -- env -i with a fixed HOME, PATH, TERM,
# LANG and PS1='$ ' -- so no user name, host name or path of this machine reaches
# the recording. pipe-pane hands the pane's raw output to wsl-record-pipe.py, which
# writes recordings/NAME.cast (asciicast v2). KEYSFILE is played line by line:
#   #sleep N      wait N seconds
#   #key K ...    tmux send-keys K ... (key names: Escape, C-c, PageDown, q ...)
#   #raw TEXT     send TEXT literally, no Enter
#   anything else send the line literally, then Enter
# with a short pause after each. The keys files live next to the recordings, so a
# recording can be made again.
set -eu
name=$1; width=$2; height=$3; keys=$4
here=$(cd "$(dirname "$0")" && pwd)
out="$here/recordings/$name.cast"
home=/tmp/tyrec
rm -rf "$home"
mkdir -p "$home/.config/htop"
# htop without the USER column (process owner = this machine's user name)
cat > "$home/.config/htop/htoprc" <<'EOF'
fields=0 2 46 47 49 1
hide_userland_threads=1
hide_kernel_threads=1
show_program_path=0
EOF
# the nested tmux: no status line (it would show the host name and the clock), and
# the same bare shell -- a login shell would read /etc/profile and put user@host
# into the prompt
printf 'set -g status off\nset -g default-command "bash --norc --noprofile"\n' > "$home/inner.conf"
rm -f "$out"
T="tmux -L tyrec"
$T kill-server 2>/dev/null || true
env -i HOME="$home" PATH=/usr/bin:/bin TERM=xterm-256color LANG=C.UTF-8 PS1='$ ' \
  $T -f /dev/null new-session -d -s tyrec -x "$width" -y "$height" \
  "cd $home; sleep 1; export PS1='\$ '; exec bash --norc --noprofile"
$T set-option -t tyrec status off
$T pipe-pane -o -t tyrec "python3 '$here/wsl-record-pipe.py' $width $height > '$out'"
sleep 1.5
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}                     # a Windows checkout may give the keys file CRLF
  case "$line" in
    '#sleep '*) sleep "${line#\#sleep }" ;;
    '#key '*) # shellcheck disable=SC2086
      $T send-keys -t tyrec ${line#\#key } ;;
    '#raw '*) $T send-keys -t tyrec -l "${line#\#raw }" ;;
    *) $T send-keys -t tyrec -l "$line"; $T send-keys -t tyrec Enter ;;
  esac
  sleep 0.4
done < "$keys"
sleep 1
$T pipe-pane -t tyrec
$T kill-server
sleep 0.5
ls -l "$out"
