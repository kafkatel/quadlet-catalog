# ComfyUI

[ComfyUI](https://github.com/comfyanonymous/ComfyUI) is a node-based GUI for Stable Diffusion and other generative AI models. It provides a visual workflow editor for building complex image generation pipelines with full control over model loading, sampling, conditioning, and post-processing.

This quadlet deploys ComfyUI with GPU acceleration (AMD ROCm or NVIDIA CUDA).

## Stack Components

| Service | Image | Description |
|---------|-------|-------------|
| comfyui | `docker.io/yanwk/comfyui-boot:rocm7` | ComfyUI with ROCm 7 (AMD) |

Alternative images:

| Tag | GPU | Base |
|-----|-----|------|
| `rocm7` | AMD (ROCm 7, RDNA 3/4, CDNA) | Ubuntu + ROCm 7.x |
| `cu124` | NVIDIA (CUDA 12.4) | Ubuntu + CUDA 12.4 |
| `latest` | NVIDIA (latest CUDA) | Ubuntu + CUDA |

## Architecture

Standalone container with direct GPU access. No pod or network required.

```
  Host :8188 ──► comfyui (:8188)
                   ├─ /dev/kfd + /dev/dri (AMD GPU)
                   ├─ /root/ComfyUI/models  ← /srv/containers/comfyui/models
                   ├─ /root/ComfyUI/input   ← .../input
                   ├─ /root/ComfyUI/output  ← .../output
                   └─ /root/ComfyUI/custom_nodes ← .../custom_nodes
```

## Quadlet Files

| File | Type | Purpose |
|------|------|---------|
| `comfyui.container` | Container | ComfyUI with GPU passthrough |
| `comfyui.env` | Environment | GPU configuration (GFX version, device selection) |

## Prerequisites

- Podman 4.4+ with Quadlet support
- GPU with drivers installed:
  - **AMD:** ROCm 6.x+ (`amdgpu-dkms` + `rocm` packages)
  - **NVIDIA:** NVIDIA driver + `nvidia-container-toolkit`

### Verifying GPU Access

**AMD:**

```bash
# Check GPU is detected
rocminfo | grep gfx
# Expected: e.g., "gfx1100" or "gfx1201"

# Check devices exist
ls -la /dev/kfd /dev/dri/render*
```

**NVIDIA:**

```bash
nvidia-smi
# Should show your GPU model and driver version
```

## Setup

### 1. Create Host Directories

Model storage is shared across AI services (see [docs/model-storage.md](../../docs/model-storage.md)):

```bash
# Shared model storage (used by ComfyUI, vLLM, TGI, etc.)
sudo mkdir -p /srv/models/huggingface/hub
sudo mkdir -p /srv/models/torch/hub
sudo mkdir -p /srv/models/comfyui/{checkpoints,clip,clip_vision,controlnet,embeddings,loras,style_models,unet,upscale_models,vae}

# Per-application data (ComfyUI only)
mkdir -p /srv/containers/comfyui/{custom_nodes,input,output,user}
```

Allocate at least 50 GB for `/srv/models/`, more for SDXL, Flux, or LLM models.

### 2. Configure GPU Environment

Edit `comfyui.env` for your GPU:

```ini
# Find your GFX version
rocminfo | grep gfx

# Set in comfyui.env — use the major.minor.0 format:
#   gfx1100 → HSA_OVERRIDE_GFX_VERSION=11.0.0
#   gfx1201 → HSA_OVERRIDE_GFX_VERSION=12.0.1
HSA_OVERRIDE_GFX_VERSION=11.0.0
```

If your system has multiple GPUs (e.g., integrated + discrete), set `HIP_VISIBLE_DEVICES=0` to target only the discrete GPU. Check ordering with `rocminfo`.

### 3. Choose Your Image Tag

Edit `comfyui.container` line 13:

```ini
# AMD GPU (default)
Image=docker.io/yanwk/comfyui-boot:rocm7

# NVIDIA GPU
Image=docker.io/yanwk/comfyui-boot:cu124
```

For NVIDIA, also swap the GPU device section in `comfyui.container`:

```ini
# Remove these (AMD):
#AddDevice=/dev/kfd
#AddDevice=/dev/dri
#GroupAdd=39
#GroupAdd=105
#SecurityLabelDisable=true
#PodmanArgs=--ipc=host
#PodmanArgs=--cap-add=SYS_PTRACE
#PodmanArgs=--security-opt=seccomp=unconfined

# Add this (NVIDIA):
AddDevice=nvidia.com/gpu=all
```

### 4. Adjust VRAM Settings (Optional)

For GPUs with limited VRAM (< 16 GB) or large models (19B+ parameters), enable low-VRAM mode in `comfyui.container`:

```ini
Environment="CLI_ARGS=--reserve-vram 1 --lowvram --listen 0.0.0.0"
```

| Flag | Effect |
|------|--------|
| `--listen 0.0.0.0` | Bind to all interfaces (required for port publishing) |
| `--lowvram` | Offload model layers to CPU when VRAM is tight |
| `--reserve-vram 1` | Keep 1 GB free for system/display overhead |
| `--highvram` | Keep everything in VRAM (for 24+ GB cards) |
| `--cpu` | CPU-only mode (very slow, for testing only) |

### 5. Install Quadlet Files

This is a user-level service (GPU access comes from group membership, not root):

```bash
mkdir -p ~/.config/containers/systemd
cp comfyui.container comfyui.env ~/.config/containers/systemd/
systemctl --user daemon-reload
```

### 6. Start ComfyUI

```bash
systemctl --user start comfyui.service
```

First start pulls the image (~15 GB for ROCm) and installs ComfyUI dependencies. This takes several minutes. Monitor progress:

```bash
journalctl --user -u comfyui.service -f
```

### 7. Access the Web UI

Open `http://localhost:8188` in a browser.

### 8. Verify GPU is Working

In the ComfyUI web UI, check the system info (bottom status bar) — it should show your GPU name and VRAM. Or check the container logs:

```bash
podman logs comfyui 2>&1 | grep -i "cuda\|rocm\|gpu\|device"
```

## Model Storage

Models use the shared host-level storage at `/srv/models/`. See [docs/model-storage.md](../../docs/model-storage.md) for the full layout and rationale.

**ComfyUI-specific models** (checkpoints, LoRAs, VAEs from CivitAI, etc.) go in `/srv/models/comfyui/`:

```
/srv/models/comfyui/
├── checkpoints/      # Base models (SD 1.5, SDXL, Flux, etc.)
├── clip/             # Text encoders
├── controlnet/       # ControlNet models
├── embeddings/       # Textual inversions
├── loras/            # LoRA adapters
├── upscale_models/   # Upscaler models
├── vae/              # VAE models
└── ...               # Other model types
```

**HuggingFace models** (downloaded by diffusers, transformers, etc.) go in `/srv/models/huggingface/`. These are automatically shared with any other container that mounts the same path (vLLM, TGI, etc.) — no duplication.

Download models from [CivitAI](https://civitai.com/) or [Hugging Face](https://huggingface.co/) and place them in the appropriate directory. ComfyUI scans the model directories at startup.

### Sharing Models with Other Services

All model volume mounts use the `:z` (lowercase, shared) SELinux suffix so multiple containers can access the same paths simultaneously. When ComfyUI downloads a model from HuggingFace, any other container mounting `/srv/models/huggingface` (vLLM, TGI, etc.) can use it immediately without re-downloading.

Do **not** use `:Z` (uppercase, private) on shared model paths — SELinux relabels the directory exclusively for one container, breaking access for all others.

## Custom Nodes

ComfyUI extensions (custom nodes) persist at `/srv/containers/comfyui/custom_nodes/`. Install them via:

1. **ComfyUI Manager** (recommended): Install ComfyUI-Manager first, then use its UI to browse and install nodes
2. **Manual:** Clone node repos directly into the custom_nodes directory:
   ```bash
   cd /srv/containers/comfyui/custom_nodes
   git clone https://github.com/author/ComfyUI-SomeExtension
   ```
   Then restart the container.

## Data Persistence

**Shared model storage** (`:z` — accessible by multiple containers):

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/models/comfyui` | `/root/ComfyUI/models` | ComfyUI checkpoints, LoRAs, VAEs, etc. |
| `/srv/models/huggingface` | `/root/.cache/huggingface` | HuggingFace model cache (shared) |
| `/srv/models/torch` | `/root/.cache/torch` | PyTorch hub cache (shared) |

**Per-application data** (`:Z` — private to this container):

| Host Path | Container Mount | Purpose |
|-----------|----------------|---------|
| `/srv/containers/comfyui/user` | `/root/ComfyUI/user` | Manager cache, workflows, assets DB, log (see below) |
| `/srv/containers/comfyui/custom_nodes` | `/root/ComfyUI/custom_nodes` | Installed extensions |
| `/srv/containers/comfyui/input` | `/root/ComfyUI/input` | Input images for img2img, inpainting |
| `/srv/containers/comfyui/output` | `/root/ComfyUI/output` | Generated images |

### What's in `user/`

The `user/` directory is the most important volume for startup performance. Without it, every restart re-fetches:

| Path | Content | Impact Without Persistence |
|------|---------|---------------------------|
| `__manager/` | ComfyUI-Manager config + cached JSON | Re-downloads 5 GitHub JSON files + 133 pages of ComfyRegistry data on every start |
| `default/workflows/` | Saved workflow files | User workflows lost on restart |
| `comfyui.log` | Application log | No log history |
| `assets.db` | SQLite assets database | Re-scans all models on every start |

## AMD GFX Version Reference

| GPU | Architecture | GFX Version | HSA_OVERRIDE_GFX_VERSION |
|-----|-------------|-------------|--------------------------|
| Radeon RX 7900 XTX / 7900 XT | RDNA 3 | gfx1100 | `11.0.0` |
| Radeon RX 7800 XT / 7700 XT | RDNA 3 | gfx1101 | `11.0.1` |
| Radeon RX 7600 | RDNA 3 | gfx1102 | `11.0.2` |
| Radeon AI PRO R9700 | RDNA 4 | gfx1201 | `12.0.1` |
| Instinct MI300X | CDNA 3 | gfx942 | `9.4.2` |
| Instinct MI250X | CDNA 2 | gfx90a | `9.0.10` |
| Instinct MI100 | CDNA 1 | gfx908 | `9.0.8` |

Find yours with: `rocminfo | grep gfx`

## ROCm Security Settings Explained

The AMD ROCm runtime requires several security relaxations to function inside a container:

| Setting | Why |
|---------|-----|
| `AddDevice=/dev/kfd` | HSA kernel fusion driver — ROCm compute interface |
| `AddDevice=/dev/dri` | Direct Rendering Infrastructure — GPU enumeration and memory mapping |
| `--ipc=host` | Shared memory for GPU inter-process communication |
| `--cap-add=SYS_PTRACE` | ROCm debugger and profiler support |
| `--security-opt=seccomp=unconfined` | ROCm uses syscalls (e.g., `perf_event_open`) blocked by the default seccomp profile |
| `SecurityLabelDisable=true` | SELinux blocks device access patterns ROCm needs |

These settings are NOT needed for NVIDIA — the `nvidia-container-toolkit` handles device isolation.

## Day-2 Operations

### Updating ComfyUI

```bash
# Pull the latest image
podman pull docker.io/yanwk/comfyui-boot:rocm7

# Restart to pick up the new image
systemctl --user restart comfyui.service
```

Models, custom nodes, and user data persist across updates.

### Viewing Logs

```bash
journalctl --user -u comfyui.service -f
```

### Stopping

```bash
systemctl --user stop comfyui.service
```

### Enable on Login

```bash
systemctl --user enable comfyui.service
```

For the service to start at boot without logging in, enable lingering:

```bash
loginctl enable-linger $USER
```
