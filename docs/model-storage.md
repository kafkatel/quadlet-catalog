# Shared Model Storage

This guide documents the host-level model storage layout for AI/ML containers. The goal is a single location for large model files that multiple containers can access without duplicating storage.

## Why Shared Storage?

AI model files are large (2-200+ GB each) and frequently used by multiple services:

- **ComfyUI** loads Stable Diffusion checkpoints, LoRAs, and HuggingFace models
- **vLLM** serves LLM inference from HuggingFace model snapshots
- **Text Generation Inference (TGI)** uses the same HuggingFace cache
- **Ollama** can import from HuggingFace format

Without shared storage, each container downloads and stores its own copy. A single Llama 3.1 70B model is ~140 GB — duplicating that across two services wastes 140 GB of disk.

## Layout

```
/srv/models/                              # Host-level shared model storage
├── huggingface/                          # $HF_HOME — HuggingFace cache root
│   └── hub/                              # Actual model cache
│       ├── models--stabilityai--sdxl-base-1.0/
│       │   ├── blobs/                    # Large tensor files (deduplicated)
│       │   ├── refs/                     # Branch/tag references
│       │   └── snapshots/                # Versioned model checkpoints
│       ├── models--meta-llama--Llama-3.1-8B-Instruct/
│       └── ...
├── torch/                                # $TORCH_HOME — PyTorch hub cache
│   └── hub/
│       ├── checkpoints/
│       └── ...
└── comfyui/                              # ComfyUI-specific model types
    ├── checkpoints/                      # Base models (SD 1.5, SDXL, Flux)
    ├── clip/                             # Text encoders (CLIP, T5)
    ├── clip_vision/                      # Vision encoders
    ├── controlnet/                       # ControlNet models
    ├── embeddings/                       # Textual inversions
    ├── loras/                            # LoRA adapters
    ├── style_models/                     # Style transfer models
    ├── unet/                             # UNet models (Flux, etc.)
    ├── upscale_models/                   # Super-resolution models
    └── vae/                              # VAE decoders
```

### Why `/srv/models/` (not `/srv/containers/models/`)?

Models are a host resource shared across containers, not scoped to any single application. `/srv/containers/` implies per-application ownership. `/srv/models/` makes the intent clear — this is a shared library.

Like `/srv/containers/`, `/srv/models/` inherits the `var_t` SELinux context from `/srv`, so container bind mounts work without manual relabeling on Fedora/RHEL.

### What stays per-application?

Application-specific data stays under `/srv/containers/{appname}/`:

| Shared (`/srv/models/`) | Per-App (`/srv/containers/{appname}/`) |
|------------------------|----------------------------------------|
| Model weights | Configuration files |
| HuggingFace cache | User inputs and outputs |
| PyTorch hub cache | Saved workflows |
| ComfyUI model types | Custom nodes / plugins |
| | Logs |
| | Database files |

## Creating the Directory Structure

```bash
# Shared model storage
sudo mkdir -p /srv/models/huggingface/hub
sudo mkdir -p /srv/models/torch/hub
sudo mkdir -p /srv/models/comfyui/{checkpoints,clip,clip_vision,controlnet,embeddings,loras,style_models,unet,upscale_models,vae}
```

### Verify SELinux Context

```bash
ls -Zd /srv/models/
# Expected: system_u:object_r:var_t:s0

# If wrong:
sudo restorecon -Rv /srv/models/
```

## Mounting Into Containers

### The `:z` Rule

When multiple containers access the same host path, use the lowercase `:z` (shared) SELinux suffix — **not** uppercase `:Z` (private).

| Suffix | Meaning | Use When |
|--------|---------|----------|
| `:z` | Shared SELinux label | **Multiple containers** access this path |
| `:Z` | Private SELinux label | **One container only** owns this path |

Using `:Z` on a shared path causes the second container to lose access — SELinux relabels the directory exclusively for the first container.

### Container Mount Reference

Each service mounts the shared directories at the paths its software expects:

**HuggingFace cache** — most AI services use `$HF_HOME` or `$HUGGING_FACE_HUB_CACHE`:

```ini
# In any .container file:
Volume=/srv/models/huggingface:/root/.cache/huggingface:z
```

The HuggingFace libraries (`transformers`, `diffusers`, `huggingface_hub`) automatically use `~/.cache/huggingface/` as the default cache directory. Mounting `/srv/models/huggingface` there means all downloads land on the shared host path.

**PyTorch hub cache** — used by torch.hub.load() and some model downloaders:

```ini
Volume=/srv/models/torch:/root/.cache/torch:z
```

**ComfyUI models** — ComfyUI has its own model directory structure:

```ini
Volume=/srv/models/comfyui:/root/ComfyUI/models:z
```

### Full Example: Multiple Services Sharing Models

```ini
# comfyui.container
Volume=/srv/models/huggingface:/root/.cache/huggingface:z
Volume=/srv/models/torch:/root/.cache/torch:z
Volume=/srv/models/comfyui:/root/ComfyUI/models:z

# vllm.container
Volume=/srv/models/huggingface:/root/.cache/huggingface:z

# tgi.container
Volume=/srv/models/huggingface:/root/.cache/huggingface:z
```

All three containers read/write to the same `/srv/models/huggingface/hub/` on the host. When ComfyUI downloads a model from HuggingFace, vLLM can use it immediately without re-downloading.

## Host-Side Configuration

By default, HuggingFace tools (`huggingface-cli`, `transformers`, `diffusers`) download models to `~/.cache/huggingface/`. To make them use `/srv/models/` instead — so downloads from the host and from inside containers all land in the same place — set these environment variables in your shell profile:

```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export HF_HOME=/srv/models/huggingface
export TORCH_HOME=/srv/models/torch
```

After sourcing the profile, all HuggingFace commands use the shared location:

```bash
source ~/.bashrc

# Downloads to /srv/models/huggingface/hub/models--meta-llama--...
huggingface-cli download meta-llama/Llama-3.1-8B-Instruct

# Verify
ls /srv/models/huggingface/hub/
```

### System-Wide Configuration

To set this for all users on the system, create an environment file that's loaded by all login shells:

```bash
# Create system-wide environment configuration
cat <<'EOF' | sudo tee /etc/profile.d/model-storage.sh
# Shared AI model storage — see /srv/models/
export HF_HOME=/srv/models/huggingface
export TORCH_HOME=/srv/models/torch
EOF

sudo chmod 644 /etc/profile.d/model-storage.sh
```

This is loaded by bash, zsh, and other POSIX shells on login. For systemd services that don't source login profiles, use a systemd environment generator or set the variables in each service's `.env` file.

This means `huggingface-cli download` on the host and a container mounting `/srv/models/huggingface` both read and write the same files. Download a model once from either side and it's available everywhere.

## Environment Variables Reference

These variables control where AI libraries store cached models. Inside containers, the bind mounts handle this automatically (the container's default `~/.cache/` path points to the shared host storage). On the host, set `HF_HOME` and `TORCH_HOME` as shown above.

| Variable | Default | Purpose |
|----------|---------|---------|
| `HF_HOME` | `~/.cache/huggingface` | HuggingFace root (contains `hub/`, `datasets/`, etc.) |
| `HUGGING_FACE_HUB_CACHE` | `$HF_HOME/hub` | Model cache specifically |
| `HF_HUB_CACHE` | `$HF_HOME/hub` | Alias for the above |
| `TORCH_HOME` | `~/.cache/torch` | PyTorch hub root |
| `TRANSFORMERS_CACHE` | `$HF_HOME/hub` | Legacy (deprecated, use HF_HOME) |

If a container runs as a non-root user, adjust the mount path accordingly (e.g., `/home/user/.cache/huggingface` instead of `/root/.cache/huggingface`).

## HuggingFace Cache Internals

Understanding the cache structure helps when troubleshooting or manually managing models.

### How Models Are Stored

When you download `meta-llama/Llama-3.1-8B-Instruct`, the cache creates:

```
/srv/models/huggingface/hub/
└── models--meta-llama--Llama-3.1-8B-Instruct/
    ├── blobs/
    │   ├── 5a7a...   # Large tensor shard (deduplicated by content hash)
    │   ├── 8c2b...   # Another shard
    │   └── ...
    ├── refs/
    │   └── main      # Points to the current snapshot hash
    └── snapshots/
        └── a1b2c3.../  # Specific revision
            ├── config.json → ../../blobs/...     (symlink)
            ├── model-00001-of-00004.safetensors → ../../blobs/...
            └── tokenizer.json → ../../blobs/...
```

Key details:
- **Blobs are content-addressed** — if two model revisions share the same file, it's stored once
- **Snapshots use symlinks** — the `snapshots/` directory contains symlinks to blobs, making revisions cheap
- **`refs/main`** points to the latest downloaded revision

### Listing Cached Models

```bash
ls /srv/models/huggingface/hub/ | sed 's/models--//' | tr '--' '/'
```

### Removing a Specific Model

```bash
rm -rf /srv/models/huggingface/hub/models--meta-llama--Llama-3.1-8B-Instruct
```

### Checking Cache Size

```bash
du -sh /srv/models/huggingface/hub/models--* | sort -rh | head -20
```

## Downloading Models

### Via HuggingFace CLI (Recommended)

Install the CLI and download directly to the shared cache:

```bash
pip install huggingface_hub

# Login (required for gated models like Llama)
huggingface-cli login

# Download a model
HF_HOME=/srv/models/huggingface huggingface-cli download meta-llama/Llama-3.1-8B-Instruct

# Download a specific file
HF_HOME=/srv/models/huggingface huggingface-cli download stabilityai/sdxl-base-1.0 sd_xl_base_1.0.safetensors
```

### Via a Running Container

Any container with HuggingFace libraries can download models — they'll land in the shared cache:

```bash
# From inside a container with the shared mount
python -c "from huggingface_hub import snapshot_download; snapshot_download('meta-llama/Llama-3.1-8B-Instruct')"
```

### Manual Download (ComfyUI Models)

For models from CivitAI or other sources that don't use the HuggingFace format:

```bash
# Download directly to the ComfyUI model directory
cd /srv/models/comfyui/checkpoints/
wget https://civitai.com/api/download/models/...  -O model-name.safetensors
```

## Storage Planning

| Model Type | Typical Size | Examples |
|-----------|-------------|---------|
| SD 1.5 checkpoint | 2-4 GB | Realistic Vision, DreamShaper |
| SDXL checkpoint | 6-7 GB | SDXL Base, Juggernaut XL |
| Flux Dev | 12-24 GB | Flux.1-dev |
| LoRA adapter | 50-300 MB | Style LoRAs, character LoRAs |
| LLM 7-8B | 14-16 GB | Llama 3.1 8B, Mistral 7B |
| LLM 70B | 130-140 GB | Llama 3.1 70B |
| LLM 405B | 750+ GB | Llama 3.1 405B |

**Recommendation:** Start with at least 200 GB for `/srv/models/`. For LLM serving, plan for 500 GB+. Use a dedicated disk or partition if possible.

## Backup

Model weights are re-downloadable — they don't need the same backup treatment as user data. Back up the list of models, not the files themselves:

```bash
# Save a manifest of cached models
ls /srv/models/huggingface/hub/ > /srv/models/model-manifest.txt
ls /srv/models/comfyui/checkpoints/ >> /srv/models/model-manifest.txt

# To restore: re-download each model from the manifest
```

For fine-tuned or custom models that can't be re-downloaded, include them in your backup strategy.
