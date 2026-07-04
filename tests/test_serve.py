import unittest

from serve import valid_scribble


class ValidScribbleTest(unittest.TestCase):
    def test_accepts_valid_line_stamp_and_tombstone(self):
        self.assertTrue(valid_scribble({"t": "s", "id": "abcd1234", "c": "#e91e63", "h": "Ada", "pts": [[1, 2], [3, 4]]}))
        self.assertTrue(valid_scribble({"t": "s", "id": "pin", "c": "#2196f3", "h": "Grace", "g": "📍", "pts": [[1, 2]]}))
        self.assertTrue(valid_scribble({"t": "e", "id": "abcd1234"}))

    def test_rejects_bad_ids(self):
        base = {"t": "s", "c": "#e91e63", "pts": [[1, 2], [3, 4]]}
        self.assertFalse(valid_scribble(base))
        self.assertFalse(valid_scribble({**base, "id": ""}))
        self.assertFalse(valid_scribble({**base, "id": "x" * 33}))

    def test_rejects_bad_color_and_handle(self):
        base = {"t": "s", "id": "a", "pts": [[1, 2], [3, 4]]}
        self.assertFalse(valid_scribble({**base, "c": 1}))
        self.assertFalse(valid_scribble({**base, "c": "x" * 17}))
        self.assertFalse(valid_scribble({**base, "c": "#e91e63", "h": "x" * 25}))

    def test_rejects_bad_points(self):
        base = {"t": "s", "id": "a", "c": "#e91e63"}
        self.assertFalse(valid_scribble({**base, "pts": "bad"}))
        self.assertFalse(valid_scribble({**base, "pts": [[1], [2, 3]]}))
        self.assertFalse(valid_scribble({**base, "pts": [[1, True], [2, 3]]}))
        self.assertFalse(valid_scribble({**base, "pts": [[1, float("inf")], [2, 3]]}))

    def test_rejects_wrong_line_lengths(self):
        base = {"t": "s", "id": "a", "c": "#e91e63"}
        self.assertFalse(valid_scribble({**base, "pts": [[1, 2]]}))
        self.assertFalse(valid_scribble({**base, "pts": [[1, 2]] * 2001}))

    def test_rejects_wrong_stamp_shape_or_glyph(self):
        base = {"t": "s", "id": "a", "c": "#e91e63"}
        self.assertFalse(valid_scribble({**base, "g": "✅", "pts": [[1, 2], [3, 4]]}))
        self.assertFalse(valid_scribble({**base, "g": 7, "pts": [[1, 2]]}))
        self.assertFalse(valid_scribble({**base, "g": "", "pts": [[1, 2]]}))
        self.assertFalse(valid_scribble({**base, "g": "x" * 9, "pts": [[1, 2]]}))
        # any short string passes — the glyph set is a client-side decision
        self.assertTrue(valid_scribble({**base, "g": "🌀", "pts": [[1, 2]]}))

    def test_rejects_wrong_type(self):
        self.assertFalse(valid_scribble({"t": "x", "id": "a", "c": "#e91e63", "pts": [[1, 2], [3, 4]]}))


if __name__ == "__main__":
    unittest.main()
