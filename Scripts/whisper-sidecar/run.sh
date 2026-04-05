#!/bin/bash
# VoxOps whisper.cpp sidecar
# Reads WAV file paths from stdin (one per line), outputs JSON transcripts to stdout.
# Environment: WHISPER_MODEL (required), WHISPER_CLI (default: whisper-cli)

set -euo pipefail

WHISPER_CLI="${WHISPER_CLI:-whisper-cli}"
WHISPER_MODEL="${WHISPER_MODEL:?WHISPER_MODEL environment variable required}"

while IFS= read -r wav_path; do
    if [ -z "$wav_path" ]; then continue; fi
    transcript=$("$WHISPER_CLI" --model "$WHISPER_MODEL" --file "$wav_path" --output-json --no-timestamps --language en 2>/dev/null)
    text=$(echo "$transcript" | python3 -c "
import sys, json
data = json.load(sys.stdin)
segments = data.get('transcription', [])
text = ' '.join(s.get('text', '').strip() for s in segments).strip()
print(json.dumps({'text': text, 'confidence': 0.9}))
" 2>/dev/null || echo '{"text": "", "confidence": 0.0}')
    echo "$text"
done
