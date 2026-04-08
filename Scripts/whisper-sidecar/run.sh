#!/bin/bash
# VoxOps whisper.cpp sidecar
# Reads WAV file paths from stdin (one per line), outputs JSON transcripts to stdout.
# Environment: WHISPER_MODEL (required), WHISPER_CLI (default: whisper-cli)

set -euo pipefail

WHISPER_CLI="${WHISPER_CLI:-whisper-cli}"
WHISPER_MODEL="${WHISPER_MODEL:?WHISPER_MODEL environment variable required}"
WHISPER_PROMPT="${WHISPER_PROMPT:-}"
WHISPER_LANG="${WHISPER_LANG:-en}"

while IFS= read -r wav_path; do
    if [ -z "$wav_path" ]; then continue; fi

    # whisper-cli writes JSON to a file, not stdout — discard all stdout/stderr
    output_base="/tmp/voxops-whisper-$$"
    prompt_args=()
    if [ -n "$WHISPER_PROMPT" ]; then
        prompt_args=(--prompt "$WHISPER_PROMPT")
    fi
    "$WHISPER_CLI" --model "$WHISPER_MODEL" --file "$wav_path" \
        --output-json --no-timestamps --language "$WHISPER_LANG" \
        ${prompt_args[@]+"${prompt_args[@]}"} \
        --output-file "$output_base" >/dev/null 2>/dev/null || true

    json_file="${output_base}.json"
    if [ -f "$json_file" ]; then
        text=$(python3 -c "
import sys, json
with open(sys.argv[1]) as f:
    data = json.load(f)
segments = data.get('transcription', [])
text = ' '.join(s.get('text', '').strip() for s in segments).strip()
print(json.dumps({'text': text, 'confidence': 0.9}))
" "$json_file" 2>/dev/null || echo '{"text": "", "confidence": 0.0}')
        rm -f "$json_file"
        echo "$text"
    else
        echo '{"text": "", "confidence": 0.0}'
    fi
done
