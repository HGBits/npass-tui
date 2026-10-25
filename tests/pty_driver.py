#!/usr/bin/env python3
"""Deterministic PTY driver for Bats tests of npass-tui.

Uses Python's standard-library PTY support instead of timing-dependent pipelines
through util-linux script(1). Every interaction waits for the prompt it expects,
and the whole child process has a hard timeout.
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


def main():
    if len(sys.argv) != 3:
        print("usage: pty_driver.py SCENARIO TUI_PATH", file=sys.stderr)
        return 2

    scenario, tui_path = sys.argv[1:]
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
    original_tty = termios.tcgetattr(slave)
    original_stty = subprocess.check_output(["stty", "-g"], stdin=slave).strip()
    env = os.environ.copy()
    env["TERM"] = "xterm"
    proc = subprocess.Popen(
        ["bash", tui_path],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
        start_new_session=True,
    )
    os.close(slave)
    output = bytearray()
    deadline = time.monotonic() + 10
    raw_tty_before_action = None

    def read_until(marker, timeout=3, after=0):
        end = min(time.monotonic() + timeout, deadline)
        needle = marker.encode("utf-8")
        while output.find(needle, after) < 0:
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for prompt: " + marker)
            ready, _, _ = select.select([master], [], [], remaining)
            if not ready:
                continue
            try:
                chunk = os.read(master, 8192)
            except OSError:
                chunk = b""
            if not chunk:
                break
            output.extend(chunk)
        position = output.find(needle, after)
        if position < 0:
            raise TimeoutError("child exited before prompt: " + marker)
        return position + len(needle)

    def send(data):
        os.write(master, data.encode("utf-8"))

    try:
        if scenario == "identities-fail":
            identity_error_end = read_until("Erro ao listar identidades (código 17)")
            read_until("Esc voltar", after=identity_error_end)
            if b"FAIL-SECRET-SENTINEL" in output:
                print("identity-list failure output leaked into the terminal", file=sys.stderr)
                return 1
            send("q")
            return_code = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
            if return_code != 0 or termios.tcgetattr(master) != original_tty:
                print("identity-list failure did not exit cleanly and restore the terminal", file=sys.stderr)
                return 1
            return 0

        read_until("personal")

        signal_scenarios = {
            "signal-term": (signal.SIGTERM, 143, "SIGTERM"),
            "signal-int": (signal.SIGINT, 130, "SIGINT"),
            "signal-hup": (signal.SIGHUP, 129, "SIGHUP"),
        }
        if scenario in signal_scenarios or scenario == "exit-cleanup":
            # Wait for a complete frame so cleanup is tested while idle in read_key().
            read_until("Esc voltar")
            if scenario == "exit-cleanup":
                send("q")
                return_code = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
                expected_code = 0
                signal_name = "normal exit"
            else:
                signal_number, expected_code, signal_name = signal_scenarios[scenario]
                os.kill(proc.pid, signal_number)
                return_code = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
            # Drain cleanup output before asserting cursor restoration.
            while select.select([master], [], [], 0.05)[0]:
                try:
                    chunk = os.read(master, 8192)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
            restored_tty = termios.tcgetattr(master)
            if return_code != expected_code:
                print(f"expected exit status {expected_code} after {signal_name}, got {return_code}", file=sys.stderr)
                return 1
            if restored_tty != original_tty:
                print(f"terminal attributes were not restored after {signal_name}", file=sys.stderr)
                return 1
            if b"\x1b[?25h" not in output:
                print(f"cursor-show sequence missing after {signal_name}", file=sys.stderr)
                return 1
            return 0

        send("\r")
        if scenario == "ls-fail":
            path_error_end = read_until("Erro ao listar entradas (código 17)")
            read_until("Esc voltar", after=path_error_end)
            if b"FAIL-SECRET-SENTINEL" in output:
                print("path-list failure output leaked into the terminal", file=sys.stderr)
                return 1
            send("q")
            before_identity = len(output)
            identity_end = read_until("Escolha uma identidade", after=before_identity)
            read_until("Esc voltar", after=identity_end)
            send("q")
            return_code = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
            if return_code != 0:
                print("TUI did not exit after path-list failure", file=sys.stderr)
                return 1
            return 0
        read_until("example/login")

        if scenario == "create":
            send("a")
            read_until("Caminho da nova entrada")
            send("new/site\n")
            read_until("Entrada enviada ao npass")
        elif scenario == "cancel":
            send("a")
            read_until("Caminho da nova entrada")
            send("\n")
            read_until("Criação cancelada.")
        elif scenario == "edit":
            send("e")
            read_until("Edição concluída")
        elif scenario == "edit-fail":
            raw_tty_before_action = termios.tcgetattr(master)
            send("e")
            read_until("npass edit falhou (código 17)")
        elif scenario == "delete":
            send("d")
            read_until('Digite exatamente "sim"')
            send("sim\n")
            read_until("Comando npass rm concluído")
        elif scenario == "delete-cancel":
            send("d")
            read_until('Digite exatamente "sim"')
            send("nao\n")
            read_until("Exclusão cancelada.")
        elif scenario == "show-fail-secret":
            send("\r")
            read_until("Erro ao abrir entrada (código 17)")
            if b"FAIL-SECRET-SENTINEL" in output:
                print("preview failure output leaked into the terminal", file=sys.stderr)
                return 1
            send("x")
            before_entries = len(output)
            entries_end = read_until("Entradas", after=before_entries)
            read_until("Esc voltar", after=entries_end)
        elif scenario == "clip-fail-secret":
            send("c")
            read_until("Falha ao copiar (código 17)")
            if b"FAIL-SECRET-SENTINEL" in output:
                print("clipboard failure output leaked into the terminal", file=sys.stderr)
                return 1
            send("x")
            before_entries = len(output)
            entries_end = read_until("Entradas", after=before_entries)
            read_until("Esc voltar", after=entries_end)
        elif scenario == "otp-fail-secret":
            send("o")
            read_until("Falha ao obter OTP (código 17)")
            if b"FAIL-SECRET-SENTINEL" in output or b"OTP-SENTINEL-123456" in output:
                print("OTP failure output leaked into the terminal", file=sys.stderr)
                return 1
            send("x")
            before_entries = len(output)
            entries_end = read_until("Entradas", after=before_entries)
            read_until("Esc voltar", after=entries_end)
        elif scenario == "otp-secret":
            send("o")
            secret = b"OTP-SENTINEL-123456"
            secret_end = read_until(secret.decode("ascii"))
            status_marker = b"OTP de example/login"
            read_until(status_marker.decode("ascii"), after=secret_end)
            status_start = output.rfind(status_marker)
            if output.find(secret, status_start) >= 0:
                print("OTP value appeared in the TUI status text", file=sys.stderr)
                return 1
            send("q")
            before_entries = len(output)
            entries_end = read_until("Entradas", after=before_entries)
            read_until("Esc voltar", after=entries_end)
        elif scenario == "control-output":
            send("\r")
            read_until("Conteúdo da entrada")
            preview_content_end = read_until("safe-line")
            if b"PWNED-TITLE" in output or b"\x1b[?9999h" in output:
                print("untrusted CLI control sequence reached the terminal", file=sys.stderr)
                return 1
            send("q")
            before_entries = len(output)
            entries_end = read_until("Entradas", after=before_entries)
            if b"\x1b[H\x1b[2J" not in output[preview_content_end:entries_end]:
                print("preview screen was not cleared when leaving it", file=sys.stderr)
                return 1
            read_until("Esc voltar", after=entries_end)
        else:
            raise ValueError("unknown scenario: " + scenario)

        # The status text is printed before the footer; wait for the footer
        # after that status before sending q, so the key cannot race the render.
        status_marker = {
            "create": "Entrada enviada ao npass",
            "cancel": "Criação cancelada.",
            "edit": "Edição concluída",
            "edit-fail": "npass edit falhou (código 17)",
            "otp-secret": "Entradas",
            "show-fail-secret": "Entradas",
            "clip-fail-secret": "Entradas",
            "otp-fail-secret": "Entradas",
            "delete": "Comando npass rm concluído",
            "delete-cancel": "Exclusão cancelada.",
            "control-output": "Entradas",
        }[scenario]
        status_end = output.rfind(status_marker.encode("utf-8"))
        read_until("Esc voltar", after=status_end + len(status_marker.encode("utf-8")))
        if scenario == "edit-fail":
            if termios.tcgetattr(master) != raw_tty_before_action:
                print("TUI terminal mode was not restored after CLI failure", file=sys.stderr)
                return 1
            tty_log = os.environ.get("NPASS_TTY_LOG")
            if not tty_log or not os.path.exists(tty_log):
                print("interactive CLI terminal-mode log is missing", file=sys.stderr)
                return 1
            with open(tty_log, "rb") as stream:
                cli_tty = stream.read().strip()
            if cli_tty != original_stty:
                print("interactive CLI did not receive the original terminal mode", file=sys.stderr)
                return 1
        # In the entries screen, q returns to the identity list; it does not
        # exit the application. Send q once to go back, then once more to exit.
        before_back = len(output)
        send("q")
        identity_title_end = read_until("Escolha uma identidade", after=before_back)
        read_until("Esc voltar", after=identity_title_end)
        send("q")
        remaining = max(0, deadline - time.monotonic())
        try:
            return_code = proc.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            raise TimeoutError("TUI did not exit after receiving q")
        if return_code != 0:
            print("TUI exited with status", return_code, file=sys.stderr)
            return 1
        if b"sed: -e expression" in output:
            print("sanitizer emitted a sed expression error", file=sys.stderr)
            return 1
        return 0
    except (TimeoutError, ValueError, OSError) as exc:
        print("PTY test driver:", exc, file=sys.stderr)
        try:
            proc.kill()
            proc.wait(timeout=1)
        except Exception:
            pass
        # Escape sequences are useful when diagnosing terminal rendering.
        sys.stderr.write(output.decode("utf-8", errors="replace"))
        return 1
    finally:
        os.close(master)
        if proc.poll() is None:
            proc.kill()
            proc.wait()


if __name__ == "__main__":
    raise SystemExit(main())
