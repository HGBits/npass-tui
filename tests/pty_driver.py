#!/usr/bin/env python3
"""Deterministic PTY driver for Bats tests of npass-tui.

Uses Python's standard-library PTY support instead of timing-dependent pipelines
through util-linux script(1). Every interaction waits for the prompt it expects,
and the whole child process has a hard timeout.

A minimal terminal emulator (tests/vt.py) keeps the *screen* the user would see,
so scenarios can assert on rendered text and attributes and not only on bytes.

usage: pty_driver.py SCENARIO TUI_PATH
env:   PTY_ROWS, PTY_COLS  terminal size (default 24x100)
"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vt import Screen  # noqa: E402

SECRET_OTP = "OTP-SENTINEL-123456"
FAIL_SENTINEL = "FAIL-SECRET-SENTINEL"


class Fail(Exception):
    """Falha de asserção do cenário (mensagem vai para stderr, status 1)."""


class Session:
    def __init__(self, tui_path, rows, cols, timeout=10):
        self.rows, self.cols = rows, cols
        self.master, slave = pty.openpty()
        self.set_size(rows, cols, slave)
        self.original_tty = termios.tcgetattr(slave)
        env = os.environ.copy()
        env["TERM"] = "xterm"
        env["LC_ALL"] = os.environ.get("PTY_LOCALE", "C.UTF-8")
        env.pop("LINES", None)
        env.pop("COLUMNS", None)
        self.proc = subprocess.Popen(
            ["bash", tui_path],
            stdin=slave, stdout=slave, stderr=slave,
            env=env, close_fds=True, start_new_session=True,
        )
        os.close(slave)
        self.output = bytearray()
        self.screen = Screen(rows, cols)
        self.deadline = time.monotonic() + timeout

    # ---- terminal ---------------------------------------------------------
    def set_size(self, rows, cols, fd=None):
        fcntl.ioctl(self.master if fd is None else fd, termios.TIOCSWINSZ,
                    struct.pack("HHHH", rows, cols, 0, 0))

    def resize(self, rows, cols):
        """Muda o tamanho do pty e avisa a TUI (sem terminal de controle, o
        kernel não entrega SIGWINCH sozinho)."""
        self.set_size(rows, cols)
        self.rows, self.cols = rows, cols
        self.screen.resize(rows, cols)
        os.kill(self.proc.pid, signal.SIGWINCH)

    def tty_attrs(self):
        return termios.tcgetattr(self.master)

    # ---- E/S ---------------------------------------------------------------
    def send(self, data):
        os.write(self.master, data.encode("utf-8"))

    def pump(self, timeout):
        """Lê o que houver (até `timeout`) e alimenta o emulador. False = EOF."""
        ready, _, _ = select.select([self.master], [], [], max(0.0, timeout))
        if not ready:
            return True
        try:
            chunk = os.read(self.master, 65536)
        except OSError:
            chunk = b""
        if not chunk:
            return False
        self.output.extend(chunk)
        self.screen.feed(bytes(chunk))
        return True

    def mark(self):
        """Posição atual na saída bruta, para raw_has/read_until(after=...)."""
        return len(self.output)

    def read_until(self, marker, timeout=3, after=0):
        end = min(time.monotonic() + timeout, self.deadline)
        needle = marker.encode("utf-8")
        while self.output.find(needle, after) < 0:
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for prompt: " + marker)
            if not self.pump(remaining):
                break
        position = self.output.find(needle, after)
        if position < 0:
            raise TimeoutError("child exited before prompt: " + marker)
        return position + len(needle)

    def wait_screen(self, predicate, what, timeout=3):
        end = min(time.monotonic() + timeout, self.deadline)
        while not predicate(self.screen):
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for screen: " + what)
            if not self.pump(remaining):
                if predicate(self.screen):
                    break
                raise TimeoutError("child exited before screen: " + what)

    def wait_text(self, *needles, timeout=3):
        self.wait_screen(lambda s: all(s.has(n) for n in needles),
                         " + ".join(needles), timeout)

    def settle(self, quiet=0.05):
        """Esgota a saída pendente (para asserções após uma saída)."""
        while select.select([self.master], [], [], quiet)[0]:
            if not self.pump(0):
                break

    def wait_exit(self):
        remaining = max(0.1, self.deadline - time.monotonic())
        return self.proc.wait(timeout=remaining)

    def raw_has(self, text, after=0):
        return self.output.find(text.encode("utf-8"), after) >= 0

    def close(self):
        os.close(self.master)
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()


def flag_enabled(attrs, flag):
    return bool(attrs[3] & flag)


def cc_value(attrs, index):
    value = attrs[6][index]
    return value[0] if isinstance(value, bytes) else int(value)


# ---------------------------------------------------------------------------
# Marcadores da UI. Ficam num só lugar: quando a tela muda, muda aqui.
# ---------------------------------------------------------------------------
IDENTITIES_TITLE = "Escolha uma identidade"
FOOT_IDENTITIES = "Q Sair"
FOOT_ENTRIES = "Esc Voltar"


def wait_identities(s):
    s.wait_text(IDENTITIES_TITLE, FOOT_IDENTITIES)


def wait_entries(s):
    s.wait_text("Entradas", FOOT_ENTRIES)


def quit_tui(s):
    """q nas entradas volta às identidades; q nas identidades sai."""
    s.send("q")
    wait_identities(s)
    s.send("q")
    code = s.wait_exit()
    if code != 0:
        raise Fail("TUI exited with status %d" % code)


def check_clean_exit(s, what):
    code = s.wait_exit()
    if code != 0 or s.tty_attrs() != s.original_tty:
        raise Fail("%s did not exit cleanly and restore the terminal" % what)


def start(s):
    s.read_until("personal")


def open_identity(s):
    start(s)
    s.send("\r")


# ---------------------------------------------------------------------------
# Cenários
# ---------------------------------------------------------------------------
def sc_identities_empty(s):
    s.wait_text(IDENTITIES_TITLE)
    s.wait_text("Nenhuma identidade encontrada.", FOOT_IDENTITIES)
    if s.raw_has("Nenhuma identidade em /tmp/npass-test-store."):
        raise Fail("CLI empty-store message was rendered as an identity")
    s.send("q")
    check_clean_exit(s, "empty identity list")


def sc_identities_fail(s):
    s.wait_text("Erro ao listar identidades (código 17)", FOOT_IDENTITIES)
    if s.raw_has(FAIL_SENTINEL):
        raise Fail("identity-list failure output leaked into the terminal")
    s.send("q")
    check_clean_exit(s, "identity-list failure")


def sc_signal(signal_number, expected_code, name):
    def run(s):
        start(s)
        # Wait for a complete frame so cleanup is tested while idle in read_key().
        s.wait_text(FOOT_IDENTITIES)
        os.kill(s.proc.pid, signal_number)
        code = s.wait_exit()
        s.settle()
        if code != expected_code:
            raise Fail("expected exit status %d after %s, got %d" % (expected_code, name, code))
        if s.tty_attrs() != s.original_tty:
            raise Fail("terminal attributes were not restored after %s" % name)
        if not s.raw_has("\x1b[?25h"):
            raise Fail("cursor-show sequence missing after %s" % name)
    return run


def sc_exit_cleanup(s):
    start(s)
    s.wait_text(FOOT_IDENTITIES)
    s.send("q")
    code = s.wait_exit()
    s.settle()
    if code != 0:
        raise Fail("expected exit status 0 after normal exit, got %d" % code)
    if s.tty_attrs() != s.original_tty:
        raise Fail("terminal attributes were not restored after normal exit")
    if not s.raw_has("\x1b[?25h"):
        raise Fail("cursor-show sequence missing after normal exit")


def sc_ls_fail(s):
    open_identity(s)
    s.wait_text("Erro ao listar entradas (código 17)", FOOT_ENTRIES)
    if s.raw_has(FAIL_SENTINEL):
        raise Fail("path-list failure output leaked into the terminal")
    quit_tui(s)


def sc_path_control(s):
    open_identity(s)
    s.read_until("example/login")
    s.wait_text(FOOT_ENTRIES)
    if s.raw_has("PWNED-PATH") or s.raw_has("\x1b]0;PWNED-PATH\x07"):
        raise Fail("untrusted path control sequence reached the terminal")
    quit_tui(s)


def sc_path_spaces(s):
    open_identity(s)
    s.read_until("dir with spaces/login entry")
    s.send("c")
    s.wait_text("Comando npass clip concluído.", FOOT_ENTRIES)
    # Successful clip uses show_message(), which consumes one dismissal key.
    s.send("x")
    wait_entries(s)
    quit_tui(s)


def sc_create(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("a")
    s.read_until("Caminho da nova entrada")
    s.send("new/site\n")
    s.wait_text("Entrada enviada ao npass", FOOT_ENTRIES)
    quit_tui(s)


def sc_cancel(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("a")
    s.read_until("Caminho da nova entrada")
    s.send("\n")
    s.wait_text("Criação cancelada.", FOOT_ENTRIES)
    quit_tui(s)


def sc_edit(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("e")
    s.wait_text("Edição concluída", FOOT_ENTRIES)
    quit_tui(s)


def sc_edit_fail(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("e")
    s.wait_text("npass edit falhou (código 17)", FOOT_ENTRIES)
    tui_tty = s.tty_attrs()
    # TUI raw_mode() relies on these modes, not on every platform-
    # specific termios flag or control character.
    if flag_enabled(tui_tty, termios.ICANON) or flag_enabled(tui_tty, termios.ECHO):
        raise Fail("TUI did not return to non-canonical, no-echo mode after CLI failure")
    if cc_value(tui_tty, termios.VMIN) != 1 or cc_value(tui_tty, termios.VTIME) != 0:
        raise Fail("TUI did not restore raw-mode VMIN/VTIME after CLI failure")
    tty_log = os.environ.get("NPASS_TTY_LOG")
    if not tty_log or not os.path.exists(tty_log):
        raise Fail("interactive CLI terminal-mode log is missing")
    with open(tty_log, "r", encoding="utf-8") as stream:
        cli_modes = set(stream.read().splitlines())
    expected = {
        "icanon=%d" % int(flag_enabled(s.original_tty, termios.ICANON)),
        "echo=%d" % int(flag_enabled(s.original_tty, termios.ECHO)),
    }
    if not expected.issubset(cli_modes):
        raise Fail("interactive CLI did not receive the original canonical/echo modes")
    quit_tui(s)


def sc_delete(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("d")
    s.read_until('Digite exatamente "sim"')
    s.send("sim\n")
    s.wait_text("Comando npass rm concluído", FOOT_ENTRIES)
    quit_tui(s)


def sc_delete_cancel(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("d")
    s.read_until('Digite exatamente "sim"')
    s.send("nao\n")
    s.wait_text("Exclusão cancelada.", FOOT_ENTRIES)
    quit_tui(s)


def sc_delete_control(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("d")
    s.read_until('Digite exatamente "sim"')
    if s.raw_has("PWNED-PATH") or s.raw_has("PWNED-IDENTITY"):
        raise Fail("untrusted identity/path control sequence reached delete confirmation")
    s.send("nao\n")
    s.wait_text("Exclusão cancelada.", FOOT_ENTRIES)
    quit_tui(s)


def sc_show_fail_secret(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("\r")
    s.wait_text("Erro ao abrir entrada (código 17)")
    if s.raw_has(FAIL_SENTINEL):
        raise Fail("preview failure output leaked into the terminal")
    s.send("x")
    wait_entries(s)
    quit_tui(s)


def sc_clip_fail_secret(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("c")
    s.wait_text("Falha ao copiar (código 17)")
    if s.raw_has(FAIL_SENTINEL):
        raise Fail("clipboard failure output leaked into the terminal")
    s.send("x")
    wait_entries(s)
    quit_tui(s)


def sc_otp_fail_secret(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("o")
    s.wait_text("Falha ao obter OTP (código 17)")
    if s.raw_has(FAIL_SENTINEL) or s.raw_has(SECRET_OTP):
        raise Fail("OTP failure output leaked into the terminal")
    s.send("x")
    wait_entries(s)
    quit_tui(s)


def sc_otp_secret(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("o")
    s.wait_text(SECRET_OTP, "OTP de example/login")
    status_row = next(r for r in range(s.rows) if "OTP de example/login" in s.screen.line(r))
    if SECRET_OTP in s.screen.line(status_row):
        raise Fail("OTP value appeared in the TUI status text")
    s.send("q")
    wait_entries(s)
    if s.screen.has(SECRET_OTP):
        raise Fail("OTP value stayed on screen after leaving the OTP view")
    quit_tui(s)


def sc_control_output(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("\r")
    s.read_until("Conteúdo da entrada")
    content_end = s.read_until("safe-line")
    if s.raw_has("PWNED-TITLE") or s.raw_has("\x1b[?9999h"):
        raise Fail("untrusted CLI control sequence reached the terminal")
    s.send("q")
    wait_entries(s)
    if s.screen.has("safe-line"):
        raise Fail("preview content stayed on screen after leaving the preview")
    if not s.raw_has("\x1b[H\x1b[2J", after=content_end):
        raise Fail("preview screen was not cleared when leaving it")
    quit_tui(s)


def last_row(s):
    return s.screen.line(s.rows - 1).rstrip()


def status_row(s):
    return s.screen.line(s.rows - 2).rstrip()


def count(s, needle):
    return s.screen.text().count(needle)


def need(cond, msg):
    if not cond:
        raise Fail(msg)


def sc_footer_identities(s):
    wait_identities(s)
    foot = last_row(s)
    for key in ("↑↓ Navegar", "Enter Abrir", "Q Sair"):
        need(key in foot, "rodapé de identidades sem %r: %r" % (key, foot))
    for key in ("Excluir", "Filtrar", "Criar", "Editar", "OTP"):
        need(key not in foot, "rodapé de identidades mostra atalho inaplicável %r" % key)
    need(status_row(s) == "", "linha de status deveria estar vazia: %r" % status_row(s))
    need(count(s, "Navegar") == 1, "atalhos duplicados na tela")
    s.send("q")
    check_clean_exit(s, "footer-identities")


def sc_footer_entries(s):
    open_identity(s)
    wait_entries(s)
    foot = last_row(s)
    for key in ("↑↓ Navegar", "Enter Abrir", "/ Filtrar", "A Criar", "E Editar",
                "D Excluir", "C Copiar", "O OTP", "Esc Voltar"):
        need(key in foot, "rodapé de entradas sem %r: %r" % (key, foot))
    need(status_row(s) == "", "linha de status deveria estar vazia: %r" % status_row(s))
    need(count(s, "Navegar") == 1, "atalhos duplicados na tela")
    need(count(s, "Excluir") == 1, "atalhos duplicados na tela")
    quit_tui(s)


def sc_footer_preview(s):
    open_identity(s)
    wait_entries(s)
    s.send("\r")
    s.wait_text("Conteúdo da entrada", "Rolar")
    foot = last_row(s)
    need("Esc Voltar" in foot and "C Copiar" in foot, "rodapé do preview incompleto: %r" % foot)
    for key in ("Filtrar", "Criar", "Excluir", "Navegar"):
        need(key not in foot, "rodapé do preview mostra atalho inaplicável %r" % key)
    need(count(s, "Rolar") == 1, "atalhos duplicados na tela")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_footer_otp(s):
    open_identity(s)
    wait_entries(s)
    s.send("o")
    s.wait_text("Código OTP", SECRET_OTP, "Qualquer tecla Voltar")
    need("Filtrar" not in last_row(s), "rodapé do OTP mostra atalhos de entradas")
    s.send("x")
    wait_entries(s)
    need(not s.screen.has(SECRET_OTP), "OTP continuou na tela depois de voltar")
    quit_tui(s)


def sc_footer_narrow(s):
    open_identity(s)
    wait_entries(s)
    foot = last_row(s)
    need(len(foot) <= s.cols, "rodapé passou da largura do terminal")
    for key in ("↑↓ Navegar", "Enter Abrir", "Esc Voltar"):
        need(key in foot, "atalho essencial %r sumiu no terminal estreito: %r" % (key, foot))
    need("Excluir" not in foot, "atalho de baixa prioridade deveria ter caído: %r" % foot)
    need(not s.screen.overflow, "texto passou da última coluna: %r" % s.screen.overflow)
    quit_tui(s)


def sc_status_replace(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("e")
    s.wait_text("Edição concluída: example/login", FOOT_ENTRIES)
    s.send("a")
    s.read_until("Caminho da nova entrada")
    s.send("\n")
    s.wait_text("Criação cancelada.", FOOT_ENTRIES)
    row = status_row(s)
    need(row.strip() == "Criação cancelada.", "resto do status antigo na linha: %r" % row)
    quit_tui(s)


def sc_status_transient(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("a")
    s.read_until("Caminho da nova entrada")
    s.send("\n")
    s.wait_text("Criação cancelada.", FOOT_ENTRIES)
    s.send("j")
    s.wait_screen(lambda sc: sc.line(sc.rows - 2).strip() == "", "status limpo na tecla seguinte")
    quit_tui(s)


SCENARIOS = {
    "footer-identities": sc_footer_identities,
    "footer-entries": sc_footer_entries,
    "footer-preview": sc_footer_preview,
    "footer-otp": sc_footer_otp,
    "footer-narrow": sc_footer_narrow,
    "status-replace": sc_status_replace,
    "status-transient": sc_status_transient,
    "identities-empty": sc_identities_empty,
    "identities-fail": sc_identities_fail,
    "signal-term": sc_signal(signal.SIGTERM, 143, "SIGTERM"),
    "signal-int": sc_signal(signal.SIGINT, 130, "SIGINT"),
    "signal-hup": sc_signal(signal.SIGHUP, 129, "SIGHUP"),
    "exit-cleanup": sc_exit_cleanup,
    "ls-fail": sc_ls_fail,
    "path-control": sc_path_control,
    "path-spaces": sc_path_spaces,
    "create": sc_create,
    "cancel": sc_cancel,
    "edit": sc_edit,
    "edit-fail": sc_edit_fail,
    "delete": sc_delete,
    "delete-cancel": sc_delete_cancel,
    "delete-control": sc_delete_control,
    "show-fail-secret": sc_show_fail_secret,
    "clip-fail-secret": sc_clip_fail_secret,
    "otp-fail-secret": sc_otp_fail_secret,
    "otp-secret": sc_otp_secret,
    "control-output": sc_control_output,
}


def main():
    if len(sys.argv) != 3:
        print("usage: pty_driver.py SCENARIO TUI_PATH", file=sys.stderr)
        return 2
    scenario, tui_path = sys.argv[1:]
    if scenario not in SCENARIOS:
        print("PTY test driver: unknown scenario: " + scenario, file=sys.stderr)
        return 2
    rows = int(os.environ.get("PTY_ROWS", "24"))
    cols = int(os.environ.get("PTY_COLS", "100"))
    s = Session(tui_path, rows, cols)
    try:
        SCENARIOS[scenario](s)
        s.settle(0.02)
        if b"sed: -e expression" in s.output:
            print("sanitizer emitted a sed expression error", file=sys.stderr)
            return 1
        return 0
    except Fail as exc:
        print(str(exc), file=sys.stderr)
        sys.stderr.write("--- tela ---\n" + s.screen.text() + "\n")
        return 1
    except (TimeoutError, ValueError, OSError, subprocess.TimeoutExpired) as exc:
        print("PTY test driver:", exc, file=sys.stderr)
        try:
            s.proc.kill()
            s.proc.wait(timeout=1)
        except Exception:
            pass
        s.settle(0.02)
        # Tela final e saída bruta ajudam a diagnosticar a renderização.
        sys.stderr.write("--- tela ---\n" + s.screen.text() + "\n--- bruto ---\n")
        sys.stderr.write(s.output.decode("utf-8", errors="replace"))
        return 1
    finally:
        s.close()


if __name__ == "__main__":
    raise SystemExit(main())
