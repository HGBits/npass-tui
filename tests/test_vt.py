#!/usr/bin/env python3
"""Testes do emulador de terminal usado pelos testes PTY."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from vt import Screen  # noqa: E402


class ScreenTest(unittest.TestCase):
    def test_cup_and_text(self):
        s = Screen(5, 10)
        s.feed(b"\x1b[3;4Hab")
        self.assertEqual(s.line(2), "   ab     ")
        self.assertEqual(s.find("ab"), (2, 3))

    def test_el_and_ed(self):
        s = Screen(3, 6)
        s.feed(b"\x1b[1;1Habcdef\x1b[1;3H\x1b[K")
        self.assertEqual(s.line(0).rstrip(), "ab")
        s.feed(b"\x1b[H\x1b[2J")
        self.assertEqual(s.text().strip(), "")
        self.assertEqual(s.clears, 1)

    def test_sgr_attrs_and_colors(self):
        s = Screen(2, 8)
        s.feed(b"\x1b[7mA\x1b[m\x1b[1mB\x1b[m\x1b[31mC")
        self.assertEqual(s.attrs_at(0, 0), ("rev",))
        self.assertEqual(s.attrs_at(0, 1), ("bold",))
        self.assertIn(31, s.colors)

    def test_exact_width_is_not_overflow(self):
        s = Screen(2, 5)
        s.feed(b"\x1b[1;1Habcde\x1b[2;1Hfghij")
        self.assertEqual(s.overflow, [])
        self.assertEqual(s.scrolled, 0)

    def test_overflow_is_recorded(self):
        s = Screen(2, 5)
        s.feed(b"\x1b[?7l\x1b[1;1Habcdefg")
        self.assertTrue(s.overflow)

    def test_scroll_is_recorded(self):
        s = Screen(2, 5)
        s.feed(b"\x1b[2;1Hab\n")
        self.assertEqual(s.scrolled, 1)

    def test_utf8_split_across_chunks(self):
        s = Screen(1, 6)
        data = "ção".encode("utf-8")
        s.feed(data[:2])
        s.feed(data[2:])
        self.assertEqual(s.line(0).rstrip(), "ção")

    def test_cursor_visibility_and_unknown(self):
        s = Screen(2, 5)
        s.feed(b"\x1b[?25l")
        self.assertFalse(s.cursor_visible)
        s.feed(b"\x1b[?25h\x1b(B\x1b[m")
        self.assertTrue(s.cursor_visible)
        self.assertEqual(s.unknown, [])
        s.feed(b"\x1b[5z")
        self.assertEqual(len(s.unknown), 1)


if __name__ == "__main__":
    unittest.main()
