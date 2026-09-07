#!/usr/bin/env python3
"""Measure native speech turns, including audio produced AFTER text SSE ends.

Only the Python standard library and curl are required. All traffic is loopback;
all artifacts, including private test prompts, stay under the ignored run folder.
"""

import argparse
import array
import json
import math
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time
import urllib.request
import wave


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def read_pcm(path):
    with path.open("rb") as raw:
        header = raw.read(12)
        if len(header) != 12 or header[:4] != b"RIFF" or header[8:] != b"WAVE":
            raise ValueError("Incomplete/invalid RIFF header: " + str(path))
        if path.stat().st_size != struct.unpack("<I", header[4:8])[0] + 8:
            raise ValueError("Incomplete RIFF payload: " + str(path))
    with wave.open(str(path), "rb") as source:
        if source.getsampwidth() != 2 or source.getnchannels() != 1 or source.getframerate() <= 0:
            raise ValueError("Expected mono PCM16: " + str(path))
        frames = source.readframes(source.getnframes())
        if not frames or len(frames) != source.getnframes() * 2:
            raise ValueError("Incomplete/empty WAV: " + str(path))
        return source.getframerate(), frames


def transcript_from_sse(path):
    fragments = []
    done_count = 0
    turns = 0
    for line in path.read_text().splitlines():
        if not line.startswith("data: "):
            continue
        if done_count:
            raise RuntimeError("Unexpected SSE data after [DONE]")
        body = line[6:]
        if body == "[DONE]":
            if turns != 1:
                raise RuntimeError("SSE ended before the assistant turn completed")
            done_count += 1
            continue
        event = json.loads(body)
        if not isinstance(event, dict):
            raise RuntimeError("Expected an SSE JSON object")
        if "error" in event:
            raise RuntimeError("Native decode failed: " + str(event["error"]))
        if turns:
            raise RuntimeError("Unexpected SSE event after the assistant turn completed")
        fragments.append(event.get("content", ""))
        turns += bool(event.get("end_of_turn"))
    if done_count != 1 or turns != 1 or not "".join(fragments).strip():
        raise RuntimeError("Expected exactly one nonempty, complete assistant turn")
    return "".join(fragments).strip()


def benchmark_turn(url, run_dir, prompt, index):
    turn_dir = run_dir / ("round_%03d" % index)
    turn_dir.mkdir(exist_ok=True)
    wav_dir = turn_dir / "tts_wav"
    first_chunk = wav_dir / ("wav_%d.wav" % (index * 1000))
    done_flag = wav_dir / "generation_done.flag"
    stream_path = turn_dir / "response.sse"
    if stream_path.exists() or done_flag.exists() or any(wav_dir.glob("wav_*.wav")):
        raise RuntimeError("Refusing to measure a turn containing previous results: " + str(turn_dir))
    started = time.monotonic()
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(
        url + "/v1/stream/prefill",
        data=json.dumps({"audio_path_prefix": "", "text": prompt, "cnt": index + 1}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with opener.open(request, timeout=30) as response:
        prefill = json.load(response)
    save_json(turn_dir / "prefill.json", prefill)
    if not prefill.get("success"):
        raise RuntimeError("Text prefill failed: " + str(prefill))

    first_audio_ms = None
    text_done_ms = None
    with stream_path.open("wb") as stream_file:
        process = subprocess.Popen([
            "curl", "--noproxy", "*", "--max-time", "90", "--no-buffer",
            "--fail-with-body", "--silent", "--show-error",
            "-H", "Content-Type: application/json",
            "-d", json.dumps({"debug_dir": str(turn_dir), "stream": True, "round_idx": index}),
            url + "/v1/stream/decode",
        ], stdout=stream_file)
        try:
            while True:
                elapsed = time.monotonic() - started
                if elapsed > 120:
                    raise TimeoutError("Audio completion timed out: " + str(turn_dir))
                if first_audio_ms is None and first_chunk.exists():
                    try:
                        read_pcm(first_chunk)
                        first_audio_ms = (time.monotonic() - started) * 1000
                    except (EOFError, wave.Error, ValueError):
                        pass  # A WAV header can appear before its PCM is written.
                return_code = process.poll()
                if return_code is not None:
                    if return_code:
                        raise RuntimeError("Decode request failed (curl %d)" % return_code)
                    if text_done_ms is None:
                        text_done_ms = elapsed * 1000
                    if done_flag.exists() and done_flag.read_text().strip():
                        break
                time.sleep(0.02)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    total_ms = (time.monotonic() - started) * 1000
    transcript = transcript_from_sse(stream_path)
    last_index = int(done_flag.read_text().strip())
    if not index * 1000 <= last_index < (index + 1) * 1000:
        raise RuntimeError("Audio chunks have an unexpected turn index")
    chunks = [wav_dir / ("wav_%d.wav" % i) for i in range(index * 1000, last_index + 1)]
    if set(wav_dir.glob("wav_*.wav")) != set(chunks):
        raise RuntimeError("Missing, duplicated or unexpected audio chunks")
    pcm = bytearray()
    sample_rate = None
    for path in chunks:
        rate, frames = read_pcm(path)
        if sample_rate is not None and sample_rate != rate:
            raise RuntimeError("Sample rate changed between chunks")
        sample_rate = rate
        pcm.extend(frames)
    if first_audio_ms is None:
        raise RuntimeError("No complete first audio chunk was observed")
    samples = array.array("h", pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
    if rms < 0.0001:
        raise RuntimeError("Generated audio is silent")
    combined = turn_dir / "reply.wav"
    with wave.open(str(combined), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(sample_rate)
        target.writeframes(pcm)
    duration = len(samples) / sample_rate
    result = {
        "turn": index, "prompt": prompt, "transcript": transcript,
        "warm": index > 0, "first_audio_ms": round(first_audio_ms, 1),
        "text_complete_ms": round(text_done_ms, 1), "total_ms": round(total_ms, 1),
        "audio_seconds": round(duration, 3), "real_time_factor": round(total_ms / 1000 / duration, 3),
        "pcm_rms": round(rms, 5),
        "clipped_sample_ratio": sum(abs(v) >= 32760 for v in samples) / len(samples),
        "chunk_count": len(chunks), "audio_file": str(combined.relative_to(run_dir)),
    }
    save_json(turn_dir / "benchmark.json", result)
    return result


def main():
    # The shell owns this client. A stop must unwind benchmark_turn's finally
    # block so its in-flight curl is also terminated and reaped.
    def terminate(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--initialization-ms", type=float, required=True)
    parser.add_argument("prompts", nargs="*")
    args = parser.parse_args()
    if not args.url.startswith("http://127.0.0.1:"):
        parser.error("Only local loopback servers are supported")
    prompts = args.prompts or [
        "今天发生了件挺好笑的事。",
        "我出门忘了带钥匙，结果发现钥匙一直在我手上。",
        "不过今天还是有点累，你陪我聊两句吧。",
    ]
    results = []
    try:
        for index, prompt in enumerate(prompts):
            result = benchmark_turn(args.url, args.run_dir, prompt, index)
            results.append(result)
            print(json.dumps(result, ensure_ascii=False), flush=True)
        log = (args.run_dir / "server.log").read_text(errors="replace")
        for failure in ("feed_window 失败", "failed to load system prompt ref_audio", "Token limit reached"):
            if failure in log:
                raise RuntimeError("Runtime reported: " + failure)
    except Exception as error:
        save_json(args.run_dir / "failure.json", {"error": str(error), "completed_turns": results})
        raise
    rss_kb = [int(line.strip()) for line in (args.run_dir / "memory-kb.log").read_text().splitlines() if line.strip()]
    save_json(args.run_dir / "benchmark.json", {
        "status": "generated", "initialization_ms": round(args.initialization_ms, 1),
        "peak_process_rss_gib": round(max(rss_kb, default=0) / 1024**2, 3),
        "measurement": "Host-side completed WAV detection at 20ms intervals; RSS is not total system memory.",
        "listening_quality": "not_evaluated", "turns": results,
    })
    print("Benchmark artifacts: " + str(args.run_dir))


if __name__ == "__main__":
    main()
