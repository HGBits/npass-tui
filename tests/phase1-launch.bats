#!/usr/bin/env bats
load test_helper

# Launch through a symlink in a different directory (lib/ must resolve via
# readlink -f) and check the empty-entries state message.
@test "lança via symlink e mostra estado vazio da identidade" {
  ln -s "$ROOT/npass-tui" "$TMP/npass-tui-link"
  cat >"$TMP/empty-npass" <<'M'
#!/usr/bin/env bash
case $1 in help) echo "npass 2.8 - m";; identities) echo "personal - 0 senhas";; ls) ;; esac
M
  chmod +x "$TMP/empty-npass"
  run python3 - "$TMP/npass-tui-link" "$TMP/empty-npass" <<'PY'
import pty, os, sys, time, select
link, mock = sys.argv[1:3]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM="xterm", NPASS_BIN=mock)
    os.execv(link, ["npass-tui"])
def rd(t):
    out = b""; end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: out += os.read(fd, 4096)
            except OSError: break
    return out
rd(1.0); os.write(fd, b"\r"); o = rd(1.0)
ok = b"Identidade sem entradas" in o
os.write(fd, b"q"); rd(0.5); os.write(fd, b"q"); rd(0.5)
rc = os.waitpid(pid, 0)[1]
sys.exit(0 if ok and rc == 0 else 1)
PY
  [ "$status" -eq 0 ]
}
