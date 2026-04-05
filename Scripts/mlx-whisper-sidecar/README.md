# MLX Whisper Sidecar

## Requirements
- Python 3.10+
- Apple Silicon Mac

## Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Test manually
```bash
export VOXOPS_SOCKET=/tmp/voxops-mlx.sock
python3 server.py &
echo "/path/to/test.wav" | socat - UNIX-CONNECT:/tmp/voxops-mlx.sock
```
