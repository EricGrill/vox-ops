#!/usr/bin/env python3
"""VoxOps MLX Whisper sidecar server. Unix domain socket, receives WAV paths, returns JSON transcripts."""
import json, os, socket, sys
import mlx_whisper

def main():
    socket_path = os.environ.get("VOXOPS_SOCKET")
    if not socket_path:
        print("VOXOPS_SOCKET environment variable required", file=sys.stderr)
        sys.exit(1)
    model_name = os.environ.get("WHISPER_MODEL", "mlx-community/whisper-small-mlx")
    initial_prompt = os.environ.get("WHISPER_PROMPT", "") or None
    language = os.environ.get("WHISPER_LANG", "en")
    if os.path.exists(socket_path): os.unlink(socket_path)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(socket_path)
    sock.listen(1)
    print(f"MLX Whisper sidecar listening on {socket_path}", file=sys.stderr)
    while True:
        conn, _ = sock.accept()
        try: handle_connection(conn, model_name, initial_prompt, language)
        except Exception as e: print(f"Connection error: {e}", file=sys.stderr)
        finally: conn.close()

def handle_connection(conn, model_name, initial_prompt=None, language="en"):
    buf = b""
    while True:
        data = conn.recv(4096)
        if not data: break
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            wav_path = line.decode("utf-8").strip()
            if not wav_path: continue
            try:
                kwargs = {"path_or_hf_repo": model_name, "language": language}
                if initial_prompt:
                    kwargs["initial_prompt"] = initial_prompt
                result = mlx_whisper.transcribe(wav_path, **kwargs)
                text = result.get("text", "").strip()
                response = json.dumps({"text": text, "confidence": 0.9})
            except Exception as e:
                response = json.dumps({"text": "", "confidence": 0.0, "error": str(e)})
            conn.sendall((response + "\n").encode("utf-8"))

if __name__ == "__main__": main()
