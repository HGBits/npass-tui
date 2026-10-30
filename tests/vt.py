#!/usr/bin/env python3
"""Emulador mínimo de terminal para os testes do npass-tui (sem dependências).

Entende só o que a TUI emite via terminfo do xterm: CUP, ED, EL, SGR, DECAWM,
DECTCEM e movimentos simples. Serve para afirmar sobre o que está *na tela*
(texto por linha, atributos por célula), não só sobre os bytes enviados.

Registra o que seria um defeito de renderização:
  overflow  caractere imprimível escrito com a quebra de linha pendente
            (texto passando da última coluna);
  scrolled  rolagem do terminal (a TUI nunca deve rolar a tela);
  colors    qualquer SGR de cor (a TUI herda as cores do terminal);
  unknown   sequências que o emulador não conhece.
"""
import codecs
import unicodedata


class Screen:
    COLOR_SGR = set(range(30, 38)) | {38} | set(range(40, 48)) | {48} \
        | set(range(90, 98)) | set(range(100, 108))

    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.state = "ground"
        self.buf = ""
        self.grid = [[" "] * cols for _ in range(rows)]
        self.attr = [[()] * cols for _ in range(rows)]
        self.r = self.c = 0
        self.pending = False
        self.autowrap = True
        self.cursor_visible = True
        self.cur_attr = set()
        self.overflow = []
        self.scrolled = 0
        self.clears = 0
        self.colors = set()
        self.unknown = []
        self.cells_written = 0

    # ---- consulta -------------------------------------------------------
    def line(self, row):
        return "".join(self.grid[row])

    def text(self):
        return "\n".join(self.line(r).rstrip() for r in range(self.rows))

    def has(self, needle):
        return needle in self.text()

    def attrs_at(self, row, col):
        return self.attr[row][col]

    def find(self, needle):
        for r in range(self.rows):
            c = self.line(r).find(needle)
            if c >= 0:
                return r, c
        return None

    def resize(self, rows, cols):
        self.__init__(rows, cols)

    # ---- escrita --------------------------------------------------------
    def feed(self, data):
        for ch in self.decoder.decode(data):
            self._char(ch)

    def _scroll(self):
        self.scrolled += 1
        self.grid.pop(0)
        self.attr.pop(0)
        self.grid.append([" "] * self.cols)
        self.attr.append([()] * self.cols)

    def _linefeed(self):
        if self.r == self.rows - 1:
            self._scroll()
        else:
            self.r += 1

    def _put(self, ch):
        if self.pending:
            self.overflow.append((self.r, ch))
            if self.autowrap:
                self.c = 0
                self._linefeed()
            self.pending = False
        width = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
        if width == 2 and self.c + 1 >= self.cols:
            self.overflow.append((self.r, ch))
            return
        self.grid[self.r][self.c] = ch
        self.attr[self.r][self.c] = tuple(sorted(self.cur_attr))
        self.cells_written += 1
        if width == 2:
            self.grid[self.r][self.c + 1] = ""
            self.attr[self.r][self.c + 1] = tuple(sorted(self.cur_attr))
        self.c += width
        if self.c >= self.cols:
            self.c = self.cols - 1
            self.pending = True

    def _char(self, ch):
        st = self.state
        if st == "ground":
            if ch == "\x1b":
                self.state = "esc"
            elif ch == "\r":
                self.c, self.pending = 0, False
            elif ch == "\n":
                self.pending = False
                self._linefeed()
            elif ch == "\b":
                self.c = max(0, self.c - 1)
                self.pending = False
            elif ch == "\t":
                self.c = min(self.cols - 1, (self.c // 8 + 1) * 8)
                self.pending = False
            elif ch < " " or ch == "\x7f":
                pass
            else:
                self._put(ch)
        elif st == "esc":
            if ch == "[":
                self.state, self.buf = "csi", ""
            elif ch == "]":
                self.state, self.buf = "osc", ""
            elif ch in "()*+":
                self.state = "charset"
            elif ch in "=>78":
                self.state = "ground"
            else:
                self.unknown.append("ESC " + ch)
                self.state = "ground"
        elif st == "charset":
            self.state = "ground"
        elif st == "osc":
            if ch == "\x07":
                self.state = "ground"
                self.unknown.append("OSC " + self.buf)
            else:
                self.buf += ch
        elif st == "csi":
            if "\x40" <= ch <= "\x7e":
                self._csi(self.buf, ch)
                self.state = "ground"
            else:
                self.buf += ch

    def _csi(self, raw, final):
        private = raw.startswith("?")
        nums = []
        for part in raw.lstrip("?").split(";"):
            try:
                nums.append(int(part))
            except ValueError:
                nums.append(None)

        def n(i, default):
            return nums[i] if i < len(nums) and nums[i] is not None else default

        if final in "Hf" and not private:
            self.r = min(max(n(0, 1), 1), self.rows) - 1
            self.c = min(max(n(1, 1), 1), self.cols) - 1
            self.pending = False
        elif final == "J":
            mode = n(0, 0)
            if mode == 2:
                self.clears += 1
                for r in range(self.rows):
                    self.grid[r] = [" "] * self.cols
                    self.attr[r] = [()] * self.cols
            elif mode == 0:
                for c in range(self.c, self.cols):
                    self.grid[self.r][c], self.attr[self.r][c] = " ", ()
                for r in range(self.r + 1, self.rows):
                    self.grid[r] = [" "] * self.cols
                    self.attr[r] = [()] * self.cols
            elif mode != 3:
                self.unknown.append("CSI %sJ" % raw)
        elif final == "K":
            mode = n(0, 0)
            lo, hi = {0: (self.c, self.cols), 1: (0, self.c + 1), 2: (0, self.cols)}.get(mode, (0, 0))
            for c in range(lo, hi):
                self.grid[self.r][c], self.attr[self.r][c] = " ", ()
        elif final == "m" and not private:
            for p in (nums if raw else [0]):
                p = 0 if p is None else p
                if p == 0:
                    self.cur_attr.clear()
                elif p in (1, 2, 4, 5, 7):
                    self.cur_attr.add({1: "bold", 2: "dim", 4: "ul", 5: "blink", 7: "rev"}[p])
                elif p in (21, 22):
                    self.cur_attr.discard("bold")
                    self.cur_attr.discard("dim")
                elif p == 24:
                    self.cur_attr.discard("ul")
                elif p == 27:
                    self.cur_attr.discard("rev")
                elif p in self.COLOR_SGR:
                    self.colors.add(p)
                elif p not in (39, 49):
                    self.unknown.append("SGR %d" % p)
        elif final in "hl" and private:
            on = final == "h"
            for p in nums:
                if p == 25:
                    self.cursor_visible = on
                elif p == 7:
                    self.autowrap = on
                elif p not in (12, 1049, 1, 1000):
                    self.unknown.append("CSI ?%dl/h" % p)
        elif final in "ABCD" and not private:
            d = n(0, 1)
            if final == "A":
                self.r = max(0, self.r - d)
            elif final == "B":
                self.r = min(self.rows - 1, self.r + d)
            elif final == "C":
                self.c = min(self.cols - 1, self.c + d)
            else:
                self.c = max(0, self.c - d)
            self.pending = False
        else:
            self.unknown.append("CSI %s%s" % (raw, final))
