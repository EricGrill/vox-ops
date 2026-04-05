# whisper.cpp Sidecar

## Requirements
- whisper-cli: `brew install whisper-cpp` or build from source
- A Whisper model file (.bin format)

## Download a model
```bash
curl -L -o ~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

## Test manually
```bash
WHISPER_MODEL=~/Library/Application\ Support/VoxOps/Models/ggml-small.bin \
echo "/path/to/test.wav" | ./run.sh
```
