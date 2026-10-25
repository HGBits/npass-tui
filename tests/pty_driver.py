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

    def read_until(marker, timeout=3):
        end = min(time.monotonic() + timeout, deadline)
        needle = marker.encode("utf-8")
        while needle not in output:
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
        if needle not in output:
            raise TimeoutError("child exited before prompt: " + marker)

    def send(data):
        os.write(master, data.encode("utf-8"))

    try:
        read_until("personal")
        send("\r")
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
        else:
            raise ValueError("unknown scenario: " + scenario)

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
