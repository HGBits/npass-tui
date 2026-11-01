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
        # Sessão e backend de clipboard determinísticos, não os da máquina de quem testa.
        env["XDG_SESSION_TYPE"] = os.environ.get("MOCK_SESSION", "wayland")
        for var in ("DISPLAY", "WAYLAND_DISPLAY", "NPASS_TUI_CLIP"):
            env.pop(var, None)
        if os.environ.get("MOCK_SESSION") == "x11" and os.environ.get("MOCK_DISPLAY"):
            env["DISPLAY"] = os.environ["MOCK_DISPLAY"]
        if os.environ.get("MOCK_CLIP_OVERRIDE"):
            env["NPASS_TUI_CLIP"] = os.environ["MOCK_CLIP_OVERRIDE"]
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
        """Muda o tamanho do pty e avisa a TUI como o kernel faria: SIGWINCH para
        o grupo de processos (sem terminal de controle ele não entrega sozinho)."""
        self.set_size(rows, cols)
        self.rows, self.cols = rows, cols
        self.screen.resize(rows, cols)
        os.killpg(self.proc.pid, signal.SIGWINCH)

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
        try:
            os.killpg(self.proc.pid, signal.SIGKILL)  # inclui o vigia de resize
        except (ProcessLookupError, PermissionError):
            pass
        self.proc.wait()


def flag_enabled(attrs, flag):
    return bool(attrs[3] & flag)


def cc_value(attrs, index):
    value = attrs[6][index]
    return value[0] if isinstance(value, bytes) else int(value)


# ---------------------------------------------------------------------------
# Marcadores da UI. Ficam num só lugar: quando a tela muda, muda aqui.
# ---------------------------------------------------------------------------
IDENTITIES_TITLE = "IDENTIDADES"
FOOT_IDENTITIES = "Q Sair"
FOOT_ENTRIES = "Esc Voltar"
FOOT_PREVIEW = "V Revelar"


def wait_identities(s):
    s.wait_text(IDENTITIES_TITLE, FOOT_IDENTITIES)


def wait_entries(s):
    s.wait_text("ENTRADAS", "Enter Abrir", FOOT_ENTRIES)


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
    s.send("z")
    wait_entries(s)
    quit_tui(s)


def sc_control_output(s):
    open_identity(s)
    s.read_until("example/login")
    s.send("\r")
    s.read_until("CONTEÚDO")
    s.send("v")
    s.read_until("safe-line")
    if s.raw_has("PWNED-TITLE") or s.raw_has("\x1b[?9999h"):
        raise Fail("untrusted CLI control sequence reached the terminal")
    s.send("q")
    wait_entries(s)
    if s.screen.has("safe-line") or s.screen.has("still-safe"):
        raise Fail("preview content stayed on screen after leaving the preview")
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
    for key in ("↑↓ Navegar", "Enter Abrir", "X Extensões", "Q Sair"):
        need(key in foot, "rodapé de identidades sem %r: %r" % (key, foot))
    for key in ("Excluir", "Filtrar", "Criar", "Editar", "OTP", "Copiar"):
        need(key not in foot, "rodapé de identidades mostra atalho inaplicável %r" % key)
    need(status_row(s) == "", "linha de status deveria estar vazia: %r" % status_row(s))
    need(count(s, "Navegar") == 1, "atalhos duplicados na tela")
    s.send("q")
    check_clean_exit(s, "footer-identities")


def sc_footer_preview(s):
    open_identity(s)
    wait_entries(s)
    s.send("\r")
    s.wait_text("CONTEÚDO", "V Revelar")
    foot = last_row(s)
    need("Esc Voltar" in foot and "C Copiar" in foot, "rodapé do preview incompleto: %r" % foot)
    need("Rolar" not in foot, "rolagem não se aplica com o conteúdo oculto")
    for key in ("Filtrar", "Criar", "Excluir", "Navegar"):
        need(key not in foot, "rodapé do preview mostra atalho inaplicável %r" % key)
    s.send("v")
    s.wait_text("V Ocultar", "Rolar")
    need(count(s, "Rolar") == 1 and count(s, "Ocultar") == 1, "atalhos duplicados na tela")
    s.send("q")
    wait_entries(s)
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


import re  # noqa: E402

CUP_RE = re.compile(rb"\x1b\[\d+;\d+H")
CLEAR_SEQ = b"\x1b[H\x1b[2J"


def selected_rows(screen):
    """Linhas do corpo (entre as duas réguas) desenhadas em vídeo reverso."""
    return [r for r in range(3, screen.rows - 3) if "rev" in screen.attrs_at(r, 0)]


def sent_since(s, mark):
    s.settle(0.1)
    return bytes(s.output[mark:])


def at_entries_many(s):
    open_identity(s)
    wait_entries(s)
    s.wait_text("entry-01", "entry-18")


def sc_render_nav(s):
    at_entries_many(s)
    need(selected_rows(s.screen) == [3], "seleção inicial fora da primeira linha")
    m = s.mark()
    s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [4], "seleção desceu uma linha")
    chunk = sent_since(s, m)
    need(CLEAR_SEQ not in chunk, "a tela foi limpa ao mover a seleção")
    # duas linhas da lista + contador no título + linhas do contexto que mudam
    need(len(CUP_RE.findall(chunk)) <= 8,
         "mover a seleção sem rolar deveria redesenhar só seleção e contexto: %r" % chunk)
    for stale in (b"npass-tui", b"Navegar", b"Esc Voltar", b"\xe2\x94\x80"):
        need(stale not in chunk, "região que não mudou foi redesenhada: %r" % stale)
    need(len(chunk) < 900, "atualização grande demais para mover a seleção: %d bytes" % len(chunk))
    m = s.mark()
    s.send("k")
    s.wait_screen(lambda sc: selected_rows(sc) == [3], "seleção subiu uma linha")
    chunk = sent_since(s, m)
    need(CLEAR_SEQ not in chunk and len(CUP_RE.findall(chunk)) <= 8, "subir redesenhou demais")
    need(not s.screen.scrolled and not s.screen.overflow, "tela rolou ou passou da coluna")
    quit_tui(s)


def sc_render_scroll(s):
    at_entries_many(s)
    body_last = s.rows - 4
    for _ in range(17):
        s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [body_last], "cursor na última linha visível")
    need(s.screen.has("entry-01"), "rolou antes da hora")
    m = s.mark()
    s.send("j")
    s.wait_screen(lambda sc: sc.has("entry-19") and not sc.has("entry-01 "), "lista rolou uma linha")
    need(selected_rows(s.screen) == [body_last], "seleção deveria ficar na última linha visível")
    chunk = sent_since(s, m)
    need(CLEAR_SEQ not in chunk, "a tela foi limpa ao rolar")
    for stale in (b"npass-tui", b"Navegar", b"Esc Voltar", b"\xe2\x94\x80"):
        need(stale not in chunk, "header/rodapé/réguas redesenhados ao rolar: %r" % stale)
    need(b"entry-19" in chunk, "a linha nova não foi desenhada")
    need(len(CUP_RE.findall(chunk)) <= s.rows, "rolagem redesenhou mais que lista, título e contexto")
    for _ in range(17):
        s.send("k")
    s.wait_screen(lambda sc: sc.has("entry-02") and selected_rows(sc) == [3], "voltou ao topo da janela")
    need(not s.screen.scrolled and not s.screen.overflow, "tela rolou ou passou da coluna")
    quit_tui(s)


def sc_render_resize(s):
    at_entries_many(s)
    for rows, cols in ((30, 80), (12, 50), (40, 120)):
        m = s.mark()
        s.resize(rows, cols)
        s.wait_screen(lambda sc: "Esc Voltar" in sc.line(rows - 1) or "Voltar" in sc.line(rows - 1),
                      "rodapé na última linha de %dx%d" % (cols, rows))
        s.settle(0.1)
        need(CLEAR_SEQ in bytes(s.output[m:]), "redimensionar deveria repintar do zero")
        need(s.screen.line(0).startswith(" npass-tui"), "cabeçalho ausente em %dx%d" % (cols, rows))
        need(not s.screen.overflow and not s.screen.scrolled,
             "texto passou da coluna ou a tela rolou em %dx%d" % (cols, rows))
        need(selected_rows(s.screen) == [3], "seleção perdida depois de redimensionar")
    quit_tui(s)


def sc_render_too_small(s):
    s.wait_text("Terminal pequeno demais")
    for key in "deao\rcj/":
        s.send(key)
    s.settle(0.2)
    need(s.screen.has("Terminal pequeno demais"), "mensagem de terminal pequeno sumiu")
    need(not s.screen.overflow and not s.screen.scrolled, "tela rolou ou passou da coluna")
    s.resize(24, 100)
    wait_identities(s)
    need(not s.screen.has("Terminal pequeno demais"), "mensagem ficou na tela depois de crescer")
    s.send("q")
    check_clean_exit(s, "terminal pequeno")


def sc_render_external(s):
    open_identity(s)
    wait_entries(s)
    s.read_until("example/login")
    m = s.mark()
    s.send("e")
    s.wait_text("Edição concluída: example/login", FOOT_ENTRIES, "example/login")
    need(not s.screen.has("NOISE-FROM-CLI"), "saída do comando externo ficou na tela")
    need(CLEAR_SEQ in sent_since(s, m), "depois de um comando externo a tela deveria ser repintada")
    need(s.screen.line(0).startswith(" npass-tui") and selected_rows(s.screen) == [3],
         "tela não voltou ao normal depois do comando externo")
    quit_tui(s)


def sc_render_attrs(s):
    open_identity(s)
    wait_entries(s)
    s.read_until("second/entry")
    need("rev" in s.screen.attrs_at(0, 0) and "bold" in s.screen.attrs_at(0, 0), "cabeçalho sem bold+reverse")
    need(selected_rows(s.screen) == [3], "linha selecionada sem vídeo reverso")
    s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [4], "seleção desceu")
    s.send("\r")
    s.wait_text("CONTEÚDO", "V Revelar")
    s.send("c")
    s.wait_text("O que copiar?")
    s.send("\x1b")
    s.wait_text("Cópia cancelada.", "V Revelar")
    s.send("q")
    wait_entries(s)
    s.send("x")
    s.wait_text("EXTENSÕES")
    s.send("q")
    wait_entries(s)
    need(not s.screen.colors, "a TUI impôs cores (SGR %s); deve herdar as do terminal" % sorted(s.screen.colors))
    need(not s.screen.unknown, "sequências desconhecidas emitidas: %r" % s.screen.unknown)
    quit_tui(s)


GLYPHS_UNICODE = "─│┬┴…↑↓"


def col_of(screen, row, ch):
    return [c for c in range(screen.cols) if screen.grid[row][c] == ch]


def sc_layout_split(s):
    wait_identities(s)
    s.wait_text("CONTEXTO", "Contagem:")
    need(col_of(s.screen, 1, "┬") == [40], "junção superior fora da coluna 40: %r" % col_of(s.screen, 1, "┬"))
    need(col_of(s.screen, s.rows - 3, "┴") == [40], "junção inferior fora da coluna 40")
    for r in range(2, s.rows - 3):
        need(s.screen.grid[r][40] == "│", "separador vertical ausente na linha %d" % r)
    need(s.screen.line(2).startswith(" IDENTIDADES"), "título do Explorer ausente")
    need(s.screen.line(2)[41:].startswith(" CONTEXTO"), "título do Contexto ausente")
    need("personal" in s.screen.line(3)[41:], "contexto não mostra a identidade selecionada")
    need("2 senhas (segundo o npass)" in s.screen.text(), "contagem do npass ausente")
    need(not s.screen.overflow and not s.screen.scrolled, "tela rolou ou passou da coluna")
    s.send("q")
    check_clean_exit(s, "layout-split")


def sc_layout_compact(s):
    wait_identities(s)
    need("CONTEXTO" not in s.screen.text(), "modo compacto não deveria mostrar o Contexto")
    need("│" not in s.screen.text(), "modo compacto não deveria ter separador vertical")
    s.send("\r")
    s.wait_text("ENTRADAS", "example/login")
    s.send("\r")
    s.wait_text("CONTEÚDO", "V Revelar")
    need("ENTRADAS" not in s.screen.text(), "no preview compacto o Contexto ocupa a largura toda")
    need(s.screen.line(2).startswith(" CONTEÚDO"), "título do preview deveria começar na coluna 0")
    s.send("q")
    s.wait_text("ENTRADAS", "Enter Abrir")
    need("CONTEÚDO" not in s.screen.text(), "preview ficou na tela depois de voltar")
    need(not s.screen.overflow and not s.screen.scrolled, "tela rolou ou passou da coluna")
    quit_tui(s)


def sc_layout_boundary(s):
    s.wait_text("CONTEXTO")
    s.resize(24, 48)
    s.wait_screen(lambda sc: "IDENTIDADES" in sc.text() and "CONTEXTO" not in sc.text(), "compacto em 48 colunas")
    s.resize(24, 49)
    s.wait_text("CONTEXTO")
    need(not s.screen.overflow and not s.screen.scrolled, "tela rolou ou passou da coluna")
    s.send("q")
    check_clean_exit(s, "layout-boundary")


def sc_layout_ascii(s):
    wait_identities(s)
    s.wait_text("CONTEXTO", "Up/Dn Navegar")
    for glyph in GLYPHS_UNICODE:
        need(not s.raw_has(glyph), "glifo Unicode %r emitido no modo ASCII" % glyph)
    need(col_of(s.screen, 1, "+") == [40] and col_of(s.screen, s.rows - 3, "+") == [40],
         "junções ASCII fora do lugar")
    need(s.screen.grid[5][40] == "|", "separador ASCII ausente")
    need(s.screen.line(1).replace("+", "-").strip("-") == "", "régua ASCII com caracteres estranhos")
    s.send("\r")
    s.wait_text("ENTRADAS", "example/login")
    for glyph in GLYPHS_UNICODE:
        need(not s.raw_has(glyph), "glifo Unicode %r emitido no modo ASCII" % glyph)
    quit_tui(s)


def sc_layout_identity_cursor(s):
    s.wait_text("personal", "work")
    s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [4] and "work" in sc.line(3)[41:] + sc.line(4)[41:], "work selecionada")
    s.send("\r")
    s.wait_text("ENTRADAS", "example/login")
    need("work" in s.screen.line(0), "cabeçalho deveria nomear a identidade work")
    s.send("q")
    wait_identities(s)
    need(selected_rows(s.screen) == [4], "voltar às identidades perdeu a seleção: %r" % selected_rows(s.screen))
    need("work" in s.screen.line(4), "linha selecionada deveria ser work")
    s.send("q")
    check_clean_exit(s, "layout-identity-cursor")


def sc_layout_accent(s):
    open_identity(s)
    s.wait_text("ENTRADAS", "second/entry")
    row = s.screen.line(3)
    need("\ufffd" not in s.screen.text(), "caractere cortado no meio (UTF-8 inválido)")
    need(row[:40].rstrip().endswith("…") or "…" in row[:25], "caminho longo deveria terminar em reticências: %r" % row)
    need(not s.screen.overflow, "texto passou da coluna: %r" % s.screen.overflow)
    quit_tui(s)


def sc_context_entry(s):
    open_identity(s)
    s.wait_text("ENTRADAS", "CONTEXTO", "login")
    text = s.screen.text()
    for want in ("Pasta:", "example", "Identidade:", "personal", "Posição:", "1 de 2", "conteúdo oculto"):
        need(want in text, "contexto da entrada sem %r" % want)
    s.send("j")
    s.wait_text("2 de 2", "entry")
    need("1 de 2" not in s.screen.text(), "contexto antigo ficou na tela")
    right = "\n".join(s.screen.line(r)[41:] for r in range(s.rows))
    need("login" not in right and "example" not in right, "restos da entrada anterior no contexto")
    quit_tui(s)


SAFE = "safe-line"


def sc_preview_protected(s):
    at_entries_many(s)
    s.send("\r")
    s.wait_text("CONTEÚDO  [oculto]", "Conteúdo protegido.", "Pressione V para revelar.")
    s.settle(0.2)
    need(not s.raw_has(SAFE) and not s.raw_has("still-safe"), "conteúdo desenhado antes de revelar")
    need(not s.screen.has(SAFE), "conteúdo na tela antes de revelar")
    s.send("j")
    s.send("k")
    s.settle(0.1)
    need(not s.raw_has(SAFE), "rolar com o conteúdo oculto revelou algo")
    s.send("v")
    s.wait_text("CONTEÚDO  [revelado]", SAFE)
    s.send("v")
    s.wait_screen(lambda sc: not sc.has(SAFE) and sc.has("[oculto]"), "conteúdo oculto de novo")
    s.send("v")
    s.wait_text(SAFE)
    s.send("q")
    s.wait_text("ENTRADAS", "Enter Abrir", "CONTEXTO")
    need(not s.screen.has(SAFE) and not s.screen.has("still-safe"), "conteúdo ficou na tela ao sair")
    s.send("\r")
    s.wait_text("[oculto]")
    need(not s.screen.has(SAFE), "reabrir deveria começar oculto de novo")
    s.send("q")
    s.wait_text("ENTRADAS", "Enter Abrir", "CONTEXTO")
    quit_tui(s)


def sc_preview_scroll(s):
    open_identity(s)
    wait_entries(s)
    s.send("\r")
    s.wait_text("[oculto]")
    s.send("j")
    s.send("v")
    s.wait_text("line-01", "line-18")
    need(not s.screen.has("line-19"), "janela do preview maior que o painel")
    for _ in range(5):
        s.send("j")
    s.wait_text("line-06", "line-23")
    need(not s.screen.has("line-01 "), "linha antiga ficou depois de rolar")
    for _ in range(80):
        s.send("j")
    s.wait_text("line-60")
    s.settle(0.1)
    need(s.screen.has("line-43") and not s.screen.has("line-42 "), "rolagem não parou no fim")
    s.send("k")
    s.wait_text("line-42")
    s.send("v")
    s.wait_text("[oculto]")
    s.send("v")
    s.wait_text("line-01", "line-18")
    need(not s.screen.scrolled and not s.screen.overflow, "tela rolou ou passou da coluna")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_preview_keeps_selection(s):
    open_identity(s)
    wait_entries(s)
    s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [4], "segunda entrada selecionada")
    s.send("\r")
    s.wait_text("[oculto]")
    need("second/entry" in s.screen.line(0), "preview da entrada errada")
    need("bold" in s.screen.attrs_at(4, 0) and "rev" not in s.screen.attrs_at(4, 0),
         "com o foco no preview a seleção do Explorer deveria ser só bold")
    s.send("q")
    wait_entries(s)
    need(selected_rows(s.screen) == [4], "voltar do preview perdeu a seleção")
    s.send("e")
    s.wait_text("Edição concluída: second/entry", FOOT_ENTRIES)
    need(selected_rows(s.screen) == [4], "editar perdeu a seleção")
    quit_tui(s)


def sc_filter(s):
    open_identity(s)
    s.wait_text("example/login", "second/entry")
    s.send("/")
    s.read_until("Filtro (vazio remove)")
    s.send("second\n")
    s.wait_text("Filtro aplicado: second", "filtro: second", "1/1")
    need(not s.screen.has("example/login"), "entrada fora do filtro continua visível")
    s.send("q")
    s.wait_text("IDENTIDADES")
    s.send("\r")
    s.wait_text("example/login", "second/entry")
    need("filtro" not in s.screen.line(2), "filtro deveria ser limpo ao reabrir a identidade")
    s.send("/")
    s.read_until("Filtro (vazio remove)", after=s.mark())
    s.send("zzz\n")
    s.wait_text("Nenhuma entrada corresponde ao filtro")
    s.send("/")
    s.read_until("Filtro (vazio remove)", after=s.mark())
    s.send("\n")
    s.wait_text("example/login", "second/entry")
    need("filtro" not in s.screen.line(2), "filtro vazio deveria remover o filtro")
    quit_tui(s)


def log_lines():
    with open(os.environ["NPASS_LOG"], "r", encoding="utf-8") as stream:
        return stream.read().splitlines()


def sc_copy_no_otp_key(s):
    open_identity(s)
    wait_entries(s)
    s.read_until("example/login")
    s.send("o")
    s.settle(0.2)
    need(not s.screen.has("OTP"), "a tecla O não deveria fazer nada")
    need(selected_rows(s.screen) == [3] and s.screen.has("ENTRADAS"), "a tela mudou com a tecla O")
    quit_tui(s)


def cursor_pos(screen):
    m = re.search(r"ENTRADAS\s+(\d+)/", screen.text())
    return int(m.group(1)) if m else -1


def sc_input_no_loss(s):
    """Nenhuma tecla pode se perder, nem a que chega junto do fim de um timeout
    de leitura (o `read -t` do bash descartava teclas nessa fronteira)."""
    s.deadline += 60
    at_entries_many(s)
    for ms in list(range(199, 207)) * 10:
        # j sobe a seleção e k desce de volta: o par nunca chega ao fim da lista
        before = cursor_pos(s.screen)
        s.send("j")
        s.wait_screen(lambda sc: cursor_pos(sc) == before + 1, "primeira tecla", timeout=2)
        t0 = time.monotonic()
        while time.monotonic() - t0 < ms / 1000:
            pass
        s.send("k")
        try:
            s.wait_screen(lambda sc: cursor_pos(sc) == before, "segunda tecla", timeout=1.0)
        except TimeoutError:
            raise Fail("tecla perdida %d ms depois da anterior" % ms)
    quit_tui(s)



def enter_preview(s):
    """Enter na primeira entrada: o preview abre oculto (só aí C copia)."""
    open_identity(s)
    wait_entries(s)
    s.read_until("example/login")
    s.send("\r")
    s.wait_text("[oculto]", FOOT_PREVIEW)


def leave_preview(s):
    s.send("q")
    wait_entries(s)


def at_copy_menu(s):
    enter_preview(s)
    s.send("c")
    s.wait_text("COPIAR", "O que copiar?", "Enter Copiar")


def copy_and_wait(s, status):
    s.send("\r")
    s.wait_text(status, FOOT_PREVIEW)
    s.settle(0.1)


def finish_from_preview(s):
    leave_preview(s)
    quit_tui(s)


def sc_path_spaces(s):
    open_identity(s)
    s.read_until("dir with spaces/login entry")
    s.send("\r")
    s.wait_text("[oculto]", FOOT_PREVIEW)
    s.send("c")
    s.wait_text("O que copiar?")
    s.send("\r")
    s.wait_text("Copiado: Senha de dir with spaces/login entry", FOOT_PREVIEW)
    # The status message lasts until the next key; an unknown key just clears it.
    s.send("z")
    s.wait_screen(lambda sc: sc.line(sc.rows - 2).strip() == "", "status limpo")
    finish_from_preview(s)


def sc_clip_fail_secret(s):
    at_copy_menu(s)
    s.send("\r")
    s.wait_text("Falha ao copiar (código 17)")
    s.settle(0.1)
    if s.raw_has(FAIL_SENTINEL):
        raise Fail("clipboard failure output leaked into the terminal")
    finish_from_preview(s)


def sc_footer_entries(s):
    open_identity(s)
    wait_entries(s)
    foot = last_row(s)
    for key in ("↑↓ Navegar", "Enter Abrir", "/ Filtrar", "A Criar", "E Editar",
                "D Excluir", "X Extensões", "Esc Voltar"):
        need(key in foot, "rodapé de entradas sem %r: %r" % (key, foot))
    need("Copiar" not in foot and "OTP" not in foot,
         "Copiar só aparece depois de abrir a entrada: %r" % foot)
    need(status_row(s) == "", "linha de status deveria estar vazia: %r" % status_row(s))
    need(count(s, "Navegar") == 1, "atalhos duplicados na tela")
    need(count(s, "Excluir") == 1, "atalhos duplicados na tela")
    need("copiar" not in s.screen.text().lower(), "o contexto da lista não deveria oferecer copiar")
    s.send("c")
    s.settle(0.2)
    need(not s.screen.has("O que copiar?"), "C na lista não deveria abrir o menu de cópia")
    quit_tui(s)


def sc_copy_menu_layout(s):
    at_copy_menu(s)
    need("> Senha" in s.screen.text(), "Senha deveria ser o item padrão")
    for label in ("Senha", "Login", "E-mail", "PIN", "Código OTP", "Outro campo...", "Documento inteiro"):
        need(label in s.screen.text(), "menu de cópia sem %r" % label)
    foot = last_row(s)
    for key in ("↑↓ Escolher", "Enter Copiar", "Esc Cancelar"):
        need(key in foot, "rodapé do menu de cópia sem %r: %r" % (key, foot))
    need("Filtrar" not in foot and "Excluir" not in foot, "rodapé do menu mostra atalhos de entradas")
    need([r for r in range(3, s.rows - 3) if "rev" in s.screen.attrs_at(r, 41)] != [], "item selecionado sem reverso")
    s.send("j")
    s.wait_text("> Login")
    need("> Senha" not in s.screen.text(), "seleção antiga ficou na tela")
    s.send("k")
    s.wait_text("> Senha")
    s.send("\x1b")
    s.wait_text("Cópia cancelada.", FOOT_PREVIEW)
    need(not s.screen.has("O que copiar?"), "menu ficou na tela depois de cancelar")
    finish_from_preview(s)


def sc_copy_password(s):
    at_copy_menu(s)
    copy_and_wait(s, "Copiado: Senha de example/login")
    finish_from_preview(s)


def sc_copy_field(s):
    at_copy_menu(s)
    s.send("j")
    s.wait_text("> Login")
    copy_and_wait(s, "Copiado: Login de example/login")
    s.send("c")
    s.wait_text("O que copiar?")
    s.send("jjj")
    s.wait_text("> PIN")
    copy_and_wait(s, "Copiado: PIN de example/login")
    finish_from_preview(s)


def sc_copy_otp(s):
    at_copy_menu(s)
    s.send("jjjj")
    s.wait_text("> Código OTP")
    copy_and_wait(s, "Copiado: Código OTP de example/login")
    need(not s.screen.has(SECRET_OTP) and not s.raw_has(SECRET_OTP), "o código OTP apareceu na tela")
    finish_from_preview(s)


def sc_copy_otp_fail(s):
    at_copy_menu(s)
    s.send("jjjj")
    s.wait_text("> Código OTP")
    s.send("\r")
    s.wait_text("Falha ao copiar (código 17).", FOOT_PREVIEW)
    s.settle(0.1)
    need(not s.raw_has(FAIL_SENTINEL) and not s.raw_has(SECRET_OTP), "saída da CLI vazou para a tela")
    finish_from_preview(s)


def sc_copy_all(s):
    at_copy_menu(s)
    s.send("jjjjjj")
    s.wait_text("> Documento inteiro")
    copy_and_wait(s, "Copiado: Documento inteiro de example/login")
    finish_from_preview(s)


def ask_other_field(s, name):
    s.send("c")
    s.wait_text("O que copiar?")
    s.send("jjjjj")
    s.wait_text("> Outro campo...")
    s.send("\r")
    s.read_until("Nome do campo (vazio cancela)", after=s.mark())
    s.send(name + "\n")


def sc_copy_other(s):
    at_copy_menu(s)
    s.send("jjjjj")
    s.wait_text("> Outro campo...")
    s.send("\r")
    s.read_until("Nome do campo (vazio cancela)")
    s.send("api-key\n")
    s.wait_text("Copiado: api-key de example/login", FOOT_PREVIEW)
    ask_other_field(s, "--help")
    s.wait_text("Nome de campo inválido.", FOOT_PREVIEW)
    ask_other_field(s, "")
    s.wait_text("Cópia cancelada.", FOOT_PREVIEW)
    finish_from_preview(s)


def sc_copy_from_preview(s):
    enter_preview(s)
    s.send("v")
    s.wait_text(SAFE)
    s.send("c")
    s.wait_text("COPIAR", "O que copiar?")
    need(not s.screen.has(SAFE), "conteúdo apareceu no menu de cópia")
    s.send("\x1b")
    s.wait_text("CONTEÚDO  [revelado]", SAFE)
    s.send("c")
    s.wait_text("O que copiar?")
    s.send("j\r")
    s.wait_text("Copiado: Login de example/login", "CONTEÚDO  [revelado]", SAFE)
    finish_from_preview(s)


def sc_copy_backend_note(s):
    at_copy_menu(s)
    want = os.environ["MOCK_EXPECT_NOTE"]
    need("Destino: " + want in s.screen.text(), "menu sem o destino %r" % want)
    s.send("\x1b")
    s.wait_text("Cópia cancelada.")
    finish_from_preview(s)


def sc_copy_no_note(s):
    at_copy_menu(s)
    need("Destino:" not in s.screen.text(), "sessão Wayland não deveria mostrar destino especial")
    s.send("\x1b")
    s.wait_text("Cópia cancelada.")
    finish_from_preview(s)


def sc_copy_x11_missing(s):
    at_copy_menu(s)
    need("Destino: X11 sem a extensão clip-x11" in s.screen.text(), "aviso de X11 sem a extensão")
    s.send("\r")
    s.wait_text("Falha ao copiar (código 17). Em X11 instale a extensão clip-x11.")
    s.settle(0.1)
    need(not s.raw_has(FAIL_SENTINEL), "saída da CLI vazou")
    finish_from_preview(s)


def sc_copy_not_in_list(s):
    open_identity(s)
    wait_entries(s)
    s.send("c")
    s.settle(0.2)
    need(not s.screen.has("O que copiar?"), "menu aberto na lista")
    quit_tui(s)


def ext_screen(s):
    open_identity(s)
    wait_entries(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "> audit", "Enter Executar")


def sc_extensions(s):
    ext_screen(s)
    need("COFRE / EXTENSÕES" in s.screen.line(0), "cabeçalho da tela de extensões")
    for name in ("audit", "import", "clip-x11", "passkey"):
        need(name in s.screen.text(), "extensão %r não listada" % name)
    need("Segundo o npass: audit: ok" in s.screen.text(), "linha original do npass ausente")
    need("Audita as senhas" in s.screen.text(), "descrição do audit ausente")
    s.send("j")
    s.wait_text("> import", "Importa senhas")
    need("Audita as senhas" not in s.screen.text(), "descrição antiga ficou na tela")
    need(not s.screen.overflow and not s.screen.scrolled, "tela rolou ou passou da coluna")
    s.send("\x1b")
    wait_entries(s)
    need("EXTENSÕES" not in s.screen.text(), "tela de extensões ficou depois de voltar")
    s.send("q")
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "audit")
    need("IDENTIDADES" in s.screen.text(), "Explorer deveria continuar mostrando as identidades")
    s.send("q")
    wait_identities(s)
    s.send("q")
    check_clean_exit(s, "extensions")


def sc_extensions_fail(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("Extensões indisponíveis (código 17).")
    s.settle(0.1)
    need(not s.raw_has(FAIL_SENTINEL), "saída de erro da CLI vazou para a tela")
    need(s.screen.has("IDENTIDADES") and not s.screen.has("EXTENSÕES"), "deveria continuar nas identidades")
    s.send("q")
    check_clean_exit(s, "extensions-fail")


def sc_extensions_empty(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "Nenhuma extensão instalada.")
    s.send("\r")
    s.settle(0.1)
    s.send("q")
    wait_identities(s)
    s.send("q")
    check_clean_exit(s, "extensions-empty")


def sc_extensions_control(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "safe-ext")
    s.settle(0.1)
    need(not s.raw_has("PWNED-EXT") and not s.raw_has("\x1b[?9999h"), "sequência de controle da CLI chegou ao terminal")
    s.send("q")
    wait_identities(s)
    s.send("q")
    check_clean_exit(s, "extensions-control")


def sc_extensions_odd(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "> zzz", "Extensão sem ação na TUI")
    s.send("\r")
    s.wait_text("Sem ação na TUI para zzz.")
    s.send("q")
    wait_identities(s)
    s.send("q")
    check_clean_exit(s, "extensions-odd")


def sc_ext_no_action(s):
    ext_screen(s)
    s.send("jjjj")
    s.wait_text("> passkey")
    s.send("\r")
    s.wait_text("Sem ação na TUI. Use na CLI: npass passkey.")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_ext_audit(s):
    mode = os.environ["MOCK_AUDIT_ANSWER"]
    ext_screen(s)
    s.send("\r")
    s.read_until("Auditar personal")
    s.send(mode + "\n")
    if mode in ("s", "o"):
        s.read_until("AUDIT-REPORT")
        s.read_until("[Enter para voltar]")
        s.send("\n")
        s.wait_text("Auditoria de personal concluída.", "EXTENSÕES")
    else:
        s.wait_text("Auditoria cancelada.", "EXTENSÕES")
    need(not s.screen.has("AUDIT-REPORT"), "saída do comando externo ficou na tela")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_ext_audit_fail(s):
    ext_screen(s)
    s.send("\r")
    s.read_until("Auditar personal")
    s.send("o\n")
    s.read_until("[Enter para voltar]")
    s.send("\n")
    s.wait_text("npass audit falhou (código 3).", "EXTENSÕES")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_ext_audit_identity(s):
    wait_identities(s)
    s.send("j")
    s.wait_screen(lambda sc: selected_rows(sc) == [4], "work selecionada")
    s.send("x")
    s.wait_text("EXTENSÕES", "> audit")
    s.send("\r")
    s.read_until("Auditar work")
    s.send("o\n")
    s.read_until("[Enter para voltar]")
    s.send("\n")
    s.wait_text("Auditoria de work concluída.")
    s.send("q")
    wait_identities(s)
    need(selected_rows(s.screen) == [4], "a seleção de identidade se perdeu")
    s.send("q")
    check_clean_exit(s, "ext-audit-identity")


def sc_ext_clip_x11(s):
    ext_screen(s)
    s.send("jj")
    s.wait_text("> clip-x11", "copia a senha ou um campo")
    s.send("\r")
    s.read_until("Campo (vazio = senha")
    answer = os.environ.get("MOCK_CLIP_ANSWER", "")
    s.send(answer + "\n")
    if answer.startswith("-"):
        s.wait_text("Nome de campo inválido.")
    elif os.environ.get("MOCK_CLIP_FAIL") == "1":
        s.wait_text("clip-x11 falhou (código 17).")
        need(not s.raw_has(FAIL_SENTINEL), "saída arbitrária da extensão chegou ao terminal")
    elif not answer:
        s.wait_text("Copiado via clip-x11: senha")
    else:
        s.wait_text("Copiado via clip-x11:")
    need(not s.screen.has("not-a-real-secret"), "conteúdo da entrada apareceu na tela")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_ext_clip_x11_without_entry(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "> audit")
    s.send("jj")
    s.wait_text("> clip-x11")
    s.send("\r")
    s.wait_text("Abra uma entrada antes de usar clip-x11.")
    need(not any(line.startswith("extension clip-x11 ") for line in open(os.environ["NPASS_LOG"])), "clip-x11 executada sem entrada")
    s.send("q")
    wait_identities(s)
    quit_tui(s)


def sc_ext_clip_x11_no_session(s):
    ext_screen(s)
    s.send("jj")
    s.wait_text("> clip-x11")
    s.send("\r")
    s.wait_text("clip-x11 requer uma sessão X11 ativa (DISPLAY).")
    need(not any(line.startswith("extension clip-x11 ") for line in open(os.environ["NPASS_LOG"])), "extensão executada fora do X11")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_ext_clip_x11_refused(s):
    ext_screen(s)
    s.send("jj")
    s.wait_text("> clip-x11  (recusada)")
    s.send("\r")
    s.wait_text("clip-x11 foi recusada pelo npass")
    need(not any(line.startswith("extension clip-x11 ") for line in open(os.environ["NPASS_LOG"])), "extensão recusada foi executada")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def import_file():
    import tempfile
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    handle.write("{}")
    handle.close()
    return handle.name


def ask_import(s, fmt, path=None, confirm=None):
    s.send("\r")
    s.read_until("Formato (veja: npass import --list)", after=s.mark())
    s.send(fmt + "\n")
    if path is None:
        return
    s.read_until("Arquivo de origem", after=s.mark())
    s.send(path + "\n")
    if confirm is None:
        return
    s.read_until('Digite "sim"', after=s.mark())
    s.send(confirm + "\n")


def sc_ext_import(s):
    path = import_file()
    try:
        ext_screen(s)
        s.send("j")
        s.wait_text("> import")
        ask_import(s, "bitwarden", path, "sim")
        s.read_until("IMPORT-DONE")
        s.read_until("[Enter para voltar]")
        s.send("\n")
        s.wait_text("Importação concluída em personal.", "EXTENSÕES")
        s.send("q")
        wait_entries(s)
        s.wait_text("example/login")
        quit_tui(s)
    finally:
        os.unlink(path)


def sc_ext_import_invalid(s):
    path = import_file()
    try:
        ext_screen(s)
        s.send("j")
        s.wait_text("> import")
        ask_import(s, "--evil")
        s.wait_text("Formato inválido.", "EXTENSÕES")
        ask_import(s, "bitwarden", "/nao/existe.json")
        s.wait_text("Arquivo não encontrado.")
        ask_import(s, "bitwarden", "-rf")
        s.wait_text("Caminho de arquivo inválido.")
        ask_import(s, "bitwarden", path, "nao")
        s.wait_text("Importação cancelada.")
        ask_import(s, "")
        s.wait_text("Importação cancelada.")
        s.send("q")
        wait_entries(s)
        quit_tui(s)
    finally:
        os.unlink(path)


def sc_extensions_refused(s):
    open_identity(s)
    wait_entries(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "> audit  (recusada)", "Recusada pelo npass: assinatura inválida")
    need("import" in s.screen.text() and "clip-x11  (recusada)" in s.screen.text(), "lista sem os estados")
    s.send("\r")
    s.wait_text("audit foi recusada pelo npass: assinatura inválida.")
    s.send("jj")
    s.wait_text("> clip-x11  (recusada)", "dono ou permissões inseguros")
    s.send("k")
    s.wait_text("> import", "Enter importa um arquivo")
    need("Recusada pelo npass" not in s.screen.text(), "aviso de recusa ficou na extensão aceita")
    s.send("q")
    wait_entries(s)
    quit_tui(s)


def sc_extensions_nodir(s):
    wait_identities(s)
    s.send("x")
    s.wait_text("EXTENSÕES", "Nenhuma extensão instalada.", "Nenhum diretório de extensões encontrado")
    s.send("q")
    wait_identities(s)
    s.send("q")
    check_clean_exit(s, "extensions-nodir")


def sc_copy_x11_refused(s):
    at_copy_menu(s)
    need("Destino: clip-x11 recusada pelo npass" in s.screen.text(), "menu sem o aviso de recusa")
    s.send("\r")
    s.wait_text("Falha ao copiar (código 17). A extensão clip-x11 foi recusada pelo npass (veja X).")
    finish_from_preview(s)


SCENARIOS = {
    "extensions-refused": sc_extensions_refused,
    "extensions-nodir": sc_extensions_nodir,
    "copy-x11-refused": sc_copy_x11_refused,
    "copy-backend-note": sc_copy_backend_note,
    "copy-no-note": sc_copy_no_note,
    "copy-x11-missing": sc_copy_x11_missing,
    "copy-not-in-list": sc_copy_not_in_list,
    "extensions-odd": sc_extensions_odd,
    "ext-no-action": sc_ext_no_action,
    "ext-audit": sc_ext_audit,
    "ext-audit-fail": sc_ext_audit_fail,
    "ext-audit-identity": sc_ext_audit_identity,
    "ext-clip-x11": sc_ext_clip_x11,
    "ext-clip-x11-no-session": sc_ext_clip_x11_no_session,
    "ext-clip-x11-without-entry": sc_ext_clip_x11_without_entry,
    "ext-clip-x11-refused": sc_ext_clip_x11_refused,
    "ext-import": sc_ext_import,
    "ext-import-invalid": sc_ext_import_invalid,
    "input-no-loss": sc_input_no_loss,
    "copy-menu-layout": sc_copy_menu_layout,
    "copy-password": sc_copy_password,
    "copy-field": sc_copy_field,
    "copy-otp": sc_copy_otp,
    "copy-otp-fail": sc_copy_otp_fail,
    "copy-all": sc_copy_all,
    "copy-other": sc_copy_other,
    "copy-from-preview": sc_copy_from_preview,
    "copy-no-otp-key": sc_copy_no_otp_key,
    "extensions": sc_extensions,
    "extensions-fail": sc_extensions_fail,
    "extensions-empty": sc_extensions_empty,
    "extensions-control": sc_extensions_control,
    "preview-protected": sc_preview_protected,
    "preview-scroll": sc_preview_scroll,
    "preview-keeps-selection": sc_preview_keeps_selection,
    "filter": sc_filter,
    "layout-split": sc_layout_split,
    "layout-compact": sc_layout_compact,
    "layout-boundary": sc_layout_boundary,
    "layout-ascii": sc_layout_ascii,
    "layout-identity-cursor": sc_layout_identity_cursor,
    "layout-accent": sc_layout_accent,
    "context-entry": sc_context_entry,
    "render-nav": sc_render_nav,
    "render-scroll": sc_render_scroll,
    "render-resize": sc_render_resize,
    "render-too-small": sc_render_too_small,
    "render-external": sc_render_external,
    "render-attrs": sc_render_attrs,
    "footer-identities": sc_footer_identities,
    "footer-entries": sc_footer_entries,
    "footer-preview": sc_footer_preview,
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
        for noise in (b"sed: -e expression", b"command not found", b"unbound variable",
                      b"bad substitution", b"syntax error"):
            if noise in s.output:
                print("a TUI emitiu erro do shell na tela: %s" % noise.decode(), file=sys.stderr)
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
