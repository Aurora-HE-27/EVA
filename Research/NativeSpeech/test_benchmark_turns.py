"""Fixture-only validation; no model, audio device or network is used."""

import json
from pathlib import Path
import struct
import tempfile
import unittest
import wave

from benchmark_turns import read_pcm, transcript_from_sse


class BenchmarkArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def sse(self, suffix="", repeat=False):
        events = [
            {"content": "听起来", "end_of_turn": False},
            {"content": "挺有趣。", "end_of_turn": False},
            {"content": "", "end_of_turn": True},
        ]
        text = "".join("data: " + json.dumps(event) + "\n\n" for event in events)
        text += "data: [DONE]\n\n"
        path = self.root / "response.sse"
        path.write_text(text * (2 if repeat else 1) + suffix)
        return path

    def wav(self):
        path = self.root / "audio.wav"
        frames = struct.pack("<4h", 120, -240, 360, -480)
        with wave.open(str(path), "wb") as target:
            target.setnchannels(1)
            target.setsampwidth(2)
            target.setframerate(24000)
            target.writeframes(frames)
        return path, frames

    def test_complete_artifacts_parse(self):
        self.assertEqual(transcript_from_sse(self.sse()), "听起来挺有趣。")
        path, frames = self.wav()
        self.assertEqual(read_pcm(path), (24000, frames))

    def test_repeated_sse_is_rejected(self):
        with self.assertRaises(RuntimeError):
            transcript_from_sse(self.sse(repeat=True))

    def test_event_after_done_is_rejected(self):
        with self.assertRaises(RuntimeError):
            transcript_from_sse(self.sse('data: {"content":"重复"}\n\n'))

    def test_done_before_turn_end_is_rejected(self):
        path = self.root / "response.sse"
        path.write_text('data: {"content":"你好"}\n\ndata: [DONE]\n\n')
        with self.assertRaises(RuntimeError):
            transcript_from_sse(path)

    def test_truncated_pcm_is_rejected(self):
        path, _ = self.wav()
        path.write_bytes(path.read_bytes()[:-2])
        with self.assertRaises(ValueError):
            read_pcm(path)

    def test_truncated_data_even_with_updated_riff_size_is_rejected(self):
        path, _ = self.wav()
        raw = bytearray(path.read_bytes()[:-2])
        struct.pack_into("<I", raw, 4, len(raw) - 8)
        path.write_bytes(raw)
        with self.assertRaises(ValueError):
            read_pcm(path)


if __name__ == "__main__":
    unittest.main()
