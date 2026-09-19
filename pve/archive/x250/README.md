# x250 - AI/ML Services

**AI/ML workloads** powered by AMD ROCm for GPU acceleration.

## Services

**LLM**:
- ollama - LLM runtime (ROCm)
- open-webui - Web interface for Ollama

**Stable Diffusion**:
- sd-rocm-comfyui - ComfyUI with ROCm support
- sd-rocm-webui - Automatic1111 WebUI with ROCm support

## Operations

```bash
docker compose up -d
docker compose down
```

## Configuration

**ROCm Setup**:
- GPU device access via `/dev/kfd` and `/dev/dri`
- GFX version override: `HSA_OVERRIDE_GFX_VERSION=10.3.0`
- Visible devices: `HIP_VISIBLE_DEVICES=0`

**Ports**:
- Ollama: 11434
- Open WebUI: 3000
- ComfyUI: 31488 (configurable)
- SD WebUI: 31489 (configurable)

## Structure

```
docker/
├── config/sd-rocm/conf/   # Startup scripts
│   ├── startup-comfyui.sh
│   ├── startup-webui.sh
│   └── functions.sh
├── data/                  # Persistent data
│   ├── ollama/
│   ├── open-webui/
│   └── sd-rocm/
│       ├── home-comfyui/
│       ├── home-webui/
│       └── checkpoints/
```

## Notes

- Requires AMD GPU with ROCm support
- Shared `/checkpoints` volume for SD models
- All containers use ROCm-optimized base images
