#!/usr/bin/env bats
load test_helper

# O binário gerado é um arquivo único: copiado sozinho para outro diretório
# (sem lib/ ao lado) e executado direto via execv, tem de abrir a TUI e mostrar
# o estado vazio da identidade. Cobre também o bit de execução do build.
@test "binário gerado é autocontido: roda copiado, sem lib/, e mostra estado vazio" {
  mkdir "$TMP/solto"
  cp "$TUI" "$TMP/solto/npass-tui"
  cat >"$TMP/empty-npass" <<'M'
#!/usr/bin/env bash
case $1 in help) echo "npass 2.8 - m";; identities) echo "personal - 0 senhas";; ls) ;; esac
M
  chmod +x "$TMP/empty-npass"
  run python3 - "$TMP/solto/npass-tui" "$TMP/empty-npass" <<'PY'
import pty, os, sys, time, select
exe, mock = sys.argv[1:3]
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM="xterm", NPASS_BIN=mock)
    os.execv(exe, ["npass-tui"])
buf = b""
def wait_for(marker, timeout=5.0):
    global buf
    end = time.time() + timeout
    needle = marker.encode()
    while needle not in buf and time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try: buf += os.read(fd, 4096)
            except OSError: break
    return needle in buf
def fail(msg):
    sys.stderr.write(msg + "\n--- saída da TUI ---\n" + buf.decode("utf-8", "replace") + "\n")
    sys.exit(1)
if not wait_for("IDENTIDADES"): fail("TUI não abriu a lista de identidades")
mark = len(buf)
os.write(fd, b"\r")
if not wait_for("Identidade sem entradas"): fail("estado vazio não apareceu")
os.write(fd, b"q"); time.sleep(0.3); os.write(fd, b"q")
_, status = os.waitpid(pid, 0)
if status != 0: fail("TUI terminou com status %d" % status)
PY
  if (( status != 0 )); then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}
