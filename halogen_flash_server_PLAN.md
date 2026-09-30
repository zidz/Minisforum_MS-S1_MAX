# halogen-flash-server on this Strix Halo — implementation plan

> **READ THIS FILE AFTER THE REBOOT.** It is the resume point for this task.
> Written 2026-09-29 by opencode. Phase 0 was executed in the same session; the
> outcome is recorded in the "Phase 0 log" section at the bottom.

---

## Goal

Replace the llama.cpp/Vulkan `Qwen3.8-27B` main model with the
[halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) serving
`Qwen3.8-Flash-Next` UD-Q4_K_XL on the **same OpenAI port 8080**, so it is a drop-in
replacement. The `Qwen3-Embedding-8B` embedding model on **8081 must keep running**
uninterrupted for Agent Zero (a0).

---

## Current machine state (measured 2026-09-29, pre-reboot)

| Item | Value |
|---|---|
| Host | Minisforum MS-S1 MAX, AMD Ryzen AI Max+ 395, gfx1151 |
| OS | Ubuntu 24.04.4 LTS (noble), kernel `6.19.8-061908-generic` |
| RAM | `MemTotal: 130494856 kB` = **124.45 GiB** visible; 8x16 GB installed |
| UMA carve-out | `mem_info_vram_total` = 1073741824 = **1 GiB** (already minimal ✅) |
| GTT in use | 54,356,211,512 = **54.3 GiB** while llama.cpp is running |
| `/proc/cmdline` | `amd_iommu=off ttm.pages_limit=33554432 ttm.page_pool_size=33554432 amdgpu.lockup_timeout=60000 vt.handoff=7 quiet splash` |
| memlock hard limit | 16311856 KB ≈ **15.5 GiB** (NOT unlimited) |
| Container runtime | Docker (no podman) |
| Docker group for Vulkan | `video`(44), `render`(993), user `zidz` in both |
| Models root | `/mnt/llm/models` → symlinked as `./models` in this repo |
| Disk free | 440 GB on `/mnt/llm`, 437 GB on `/` |
| Apt sources | `noble`, `noble-updates`, `noble-security`, + `ppa:cappelikan` |

### Running containers (pre-reboot)

| Name | Image | Port | Role |
|---|---|---|---|
| `llama-server-qwen-first-vulkan` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | 8080 | Qwen3.8-27B UD-Q6_K_XL + mmproj (to be replaced) |
| `llama-server-qwen-embed-vulkan` | `ghcr.io/ggml-org/llama.cpp:server-vulkan` | 8081 | Qwen3-Embedding-8B-Q8_0 (**must survive**) |
| `llama-server-qwen-second-vulkan` | same | — | Exited 2 weeks ago, ignore |

Note: the embed container reports `unhealthy` in `docker ps`, but that is a
**cosmetic healthcheck bug** — its HEALTHCHECK curls `localhost:8080` instead of
8081. It is genuinely serving. Verified: `curl localhost:8081/v1/models` returns
`Qwen3-Embedding-8B`.

### The GGUF we will use

`/mnt/llm/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/`

```
Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf   10,946,624
Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf  49,859,583,136
Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf  49,376,141,504
Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf  12,087,983,520
```

**unsloth's `UD-Q4_K_XL` is an explicitly supported and benchmarked GGUF for
halogen** (README section "Bring your own GGUF", since 0.11.6):
104 GiB on disk, **79.6 GiB resident in RAM** after the startup repack,
perplexity 0.020 nats *better* than `UD-IQ4_XS`, prefill within 2%,
serial decode ~3% slower. It is one of the two files the upstream author
specifically measured. No conversion step needed.

---

## Constraints and risks discovered

### BLOCKER — kernel version (resolved in Phase 0)

halogen requires **kernel 7.0+**. Upstream: *"on 6.18.6 the driver refuses every
read-only mapping with `invalid argument` and the server cannot pin the weights.
We have not bisected the exact kernel that added it; 7.0 is the oldest we have
seen work."* We were on **6.19.8** — in the untested gap between a known-bad
(6.18.6) and a known-good (7.0.0).

**Solution: no distro upgrade required.** Canonical backports kernel 7.0 to 24.04
as HWE. `linux-generic-hwe-24.04` version `7.0.0-34.34~24.04.1` is in
`noble-updates` today. The local apt lists were simply stale (which is why
`apt-cache search '^linux-image-7'` only showed cloud flavours).

Residual risk: the upstream reference machine runs 7.1.8. 7.0.0-34 is in range
but is not the exact tested point.

### Issue #80 — the exact quant we chose crash-looped on a 128 GB box

Upstream: for `UD-Q4_K_XL` the startup pre-flight fit check **under-estimates the
weight size by ~7.6 GiB** (72 GiB estimated vs 79.6 GiB actual). The check waves
the boot through, then the pin guard correctly refuses to go below its 16 GiB
safety floor, the engine exits, systemd restarts it, and it crash-loops — each
retry repacking 78 GiB from disk.

**Mitigation:** `HALOGEN_MAX_TOK=16384` (gives back ~8.8 GiB of working memory
for ~9% prefill speed) plus an explicitly pinned smaller pool. This is exactly
the row the upstream README names for a 122 GiB box.

### Issue #79 / #95 — GTT leak makes the server refuse to start

Currently **54.3 GiB of GTT is in use** by the running llama.cpp containers. After
an unclean exit the amdgpu driver can keep 35–45 GiB allocated with nothing alive,
after which every later start either refuses at the pin guard or hangs at
`reserving the KV pool` until the host reboots. Issue #95 shows the failure is at
least *legible* — halogen prints a named refusal and exits rather than wedging.

**Mitigation:** reboot before first start, then check
`cat /sys/class/drm/card0/device/mem_info_gtt_used` — should read near 0.
Do this **after** stopping the llama.cpp containers, not before.

### Memory is the scarce resource

`UD-Q4_K_XL` holds **79.6 GiB pinned**. Upstream's "If you must share it" table,
plus the documented +12 GiB for the K-quant:

| configuration | halogen takes |
|---|---|
| Quickstart defaults (pool 524288, 4 slots, MAX_TOK 32768) | ~115 GiB → **refuses on a 124 GiB box** |
| pool 262144, 2 slots, MAX_TOK 32768 | ~108 GiB |
| **pool 262144, 2 slots, MAX_TOK 16384 (CHOSEN)** | **~99 GiB** |
| ctx 131072, pool 131072, 2 slots, MAX_TOK 16384 | ~96 GiB |

Plus the vision tower (~0.9–2 GiB RAM) and the 8 GB embed model. ~124 GiB total
box ⇒ ~14–16 GiB left. Above the ~10 GiB floor where the README says prefill
starts paging the lookup table from disk and the watchdog can read the stall as a
wedge. Tight but workable. `HALOGEN_HOST_RESERVE_GIB=30` tells the fit checker
to be conservative about this.

### Things deliberately NOT done

- `HALOGEN_WEIGHTS_LOCK=1` — opt-in mlock. Needs the memlock *hard* limit to be
  `unlimited`; ours is 15.5 GiB. Would need a `/etc/security/limits.d/` entry.
  Not required for this deployment.
- `HALOGEN_FLASH_PIN_TRUNK=0` — last resort, costs several times the decode speed.
- `amdgpu.gttsize` / `ttm.pages_limit` changes — upstream says *"Do not paste
  ours. Neither flag is required."* Ours already has `ttm.pages_limit` at 128 GiB
  worth of pages, so the default GTT (~half of RAM ≈ 62 GiB) is ample for the
  ~19 GiB device-side footprint of the chosen config.
- `amdgpu.noretry=0`, `amdgpu.vm_update_mode=0`, `amdgpu.sg_display=0` — upstream
  says leave them off; we have them off. Good.
- BIOS change — **none needed.** UMA is already at 1 GiB, and `amd_iommu=off` is
  already in GRUB (worth 13–16% of prefill).

### Upstream open issues worth knowing about

- **#89** — the *shipped .hgn* checkpoint predicts `<|im_end|>` mid-prose past
  ~96k tokens. Partly mitigated here: we run a GGUF trunk, and the quality sidecar
  is not loaded over a GGUF trunk anyway.
- **#115** — long-document translation stops mid-sentence with
  `finish_reason: stop` on 0.14.2. Not fixed as of 2026-09-29.
- **#85** — tracking issue for stalls/wedges under host memory pressure. Relevant
  to us *because* we are deliberately sharing the machine. Read the watchdog's
  lines before trusting a restart policy to recover anything.
- **#112** — garbled output at temperature >= 1.0, open.
- Note `free` and `MemAvailable` will **overstate** available memory by the 79.6 GiB
  of locked weights. The startup line `host memory left for everything else` is the
  number to believe.

---

## Phase 0 — Install kernel 7.0 (BLOCKING)

Canonical ships kernel 7.0 to 24.04 as an HWE backport. No distro upgrade.

```bash
sudo apt update
sudo apt install -y linux-generic-hwe-24.04     # → linux-image-7.0.0-34-generic
sudo reboot
```

Keep the existing kernels as fallbacks — 6.19.8, 6.18.12 and the 6.8.0 series all
remain installed, and `GRUB_DEFAULT=0` in `/etc/default/grub` boots the newest.
If the new kernel fails to boot, select an older one from the GRUB menu.

**Post-reboot verification:**

```bash
uname -r                                     # expect 7.0.0-34-generic
cat /proc/cmdline                            # amd_iommu=off must still be there
ls -l /dev/kfd /dev/dri/renderD128            # must still exist
```

GRUB config needs no change; `GRUB_CMDLINE_LINUX_DEFAULT` is per-distro and is
untouched by a kernel install. The copy in this repo (`./grub`) stays accurate.

---

## Phase 1 — Write `halogen_flash_next.sh`

New file in this repo, alongside the existing `llama_cpp_vulkan_*.sh` scripts.
Follows the established house style: `#!/bin/bash`, `MODEL_DIR="$(pwd)/models"`,
`RENDER_GID=$(getent group render | cut -d: -f3)`, `docker run -d`, Swedish
`echo` status lines, commented-out alternative flags at the top.

### Structure

1. Stop the old main model:
   ```bash
   docker rm -f llama-server-qwen-first-vulkan 2>/dev/null
   ```
2. `docker rm -f halogen-flash-server 2>/dev/null` — idempotent re-runs.
3. Start halogen on 8080.
4. Embed model: `docker start llama-server-qwen-embed-vulkan` if it already exists;
   only fall back to the full `docker run` block from `llama_cpp_vulkan_qwen3.8_27b.sh`
   when the container is absent. **8081 is never recreated when it is already up.**
5. Print post-start diagnostics.

### Step 3 — the `docker run`

**Differences from the existing Vulkan scripts (these matter):**

- `--device=/dev/kfd` is **new and required**. halogen is a ROCm/HIP engine, not
  Vulkan. It runs on the amdgpu/KFD stack. `/dev/dri` is still passed.
- Upstream compose notes `seccomp=unconfined` is measured to be a no-op, but the
  existing scripts here all use it; keep it for consistency.
- `--ipc=host` is load-bearing (not a `shm_size` substitute).
- `--ulimit memlock=-1:-1` is on every upstream run line. It will clamp to our
  15.5 GiB hard limit, which is fine since we are not using `HALOGEN_WEIGHTS_LOCK`.
- No `--cap-add=SYS_PTRACE`; not a halogen requirement.
- Container name `halogen-flash-server` (NOT reusing
  `llama-server-qwen-first-vulkan`, so the two `--restart` policies never fight).

**Environment:**

| Variable | Value | Why |
|---|---|---|
| `HALOGEN_API_PORT` | `8080` | must be changed together with `-p 8080:8080` |
| `HALOGEN_CHECKPOINT` | `/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf` | any shard; siblings found by name |
| `HALOGEN_DOWNLOAD` | `peonist-ai/halogen-qwen3.8-flash-next` | first start fetches ONLY the 1.4 GiB `qwen38-flash-next-mtp.hgn` draft head + `tokenizer/` + vision sidecar. Never downloads a GGUF. Needs the volume writable — it is. |
| `HALOGEN_VISION_TOWER` | explicit path | see below |
| `HALOGEN_TOKENIZER` | explicit path | see below |
| `HALOGEN_KV_POOL_POSITIONS` | `262144` | the memory knob (issue #80 mitigation) |
| `HALOGEN_KV_SLOTS` | `2` | ~115 MiB each; not the memory knob |
| `HALOGEN_MAX_TOK` | `16384` | **the critical issue #80 fix**; 21.3 → 12.5 GiB working memory for ~9% prefill |
| `HALOGEN_HOST_RESERVE_GIB` | `30` | makes the fit checker budget for the embed model |
| `HALOGEN_MODEL_ID` | `Qwen3.8-Flash-Next` | top-of-file variable; a0/opencode reference the model id by name |

**On `HALOGEN_VISION_TOWER` / `HALOGEN_TOKENIZER`:** upstream allows
`HALOGEN_VISION_TOWER=1` ("find the sidecar beside the checkpoint") and falls back
to the weights repo's own `tokenizer/`. But the sidecars download into `/models`
root while our GGUF sits four levels down at
`/models/unsloth/Qwen3.8-Flash-Next-GGUF/UD-Q4_K_XL/`, so "beside the checkpoint"
may not resolve. **Resolve the real paths by listing `/models` after the first
`HALOGEN_DOWNLOAD` start, then pin them explicitly.** Known filenames from
upstream issues: `qwen38-flash-next-mtp.hgn` (1.4 GiB draft head),
`qwen38-flash-next-vision.hgn` (~857 MiB tower), `tokenizer/`.

**NOT set:** `HALOGEN_WEIGHTS_LOCK`, `HALOGEN_FLASH_PIN_TRUNK`, `HALOGEN_CTX`
(leave the 262144 native default), `HALOGEN_MTP_HEAD` (the head lands beside the
GGUF / is auto-found), `HALOGEN_KV_POOL_FIT=0`.

### Step 5 — diagnostics to print

- `cat /sys/class/drm/card*/device/mem_info_gtt_used` before starting (must be low)
- a hint to grep the log for `host memory left for everything else`
- `curl -s localhost:8080/health`
- `curl -s localhost:8080/v1/models`

---

## Phase 2 — Verify before cutover

```bash
docker logs -f halogen-flash-server
```

Checklist:
- First log line is the version.
- `checkpoint_format` on `/health` is `gguf`.
- `chat_template.probe` is `ok` (a template without a working `enable_thinking`
  branch refuses to start — ours comes from the weights repo, so it should pass).
- `vision.enabled` is `true` with the right `max_pixels`.
- The `host memory left for everything else: N contiguous 2 MiB blocks (X GiB
  total)` line. **If this is under ~10 GiB, we are too tight** — drop to
  `HALOGEN_CTX=131072` / `HALOGEN_KV_POOL_POSITIONS=131072` (recipe 3).
- No `WARNING ... no process holds the GPU` line (that means leaked GTT → reboot).
- A real `/v1/chat/completions` call returns content plus a `timings` object and
  a `serve_api:` log line.

---

## Phase 3 — Cutover

`current.sh` is currently a symlink → `llama_cpp_vulkan_qwen3.8_27b.sh`.
Repoint it at the new script. Rollback = run `llama_cpp_vulkan_qwen3.8_27b.sh`
again, **but** per issue #79 expect to need a reboot if you switch back within
the same boot.

**OPEN QUESTION (not yet answered by the user):** a separate `flash.sh` symlink
instead of repointing `current.sh`. Default if unstated: repoint `current.sh`,
since the ask was "a full replacement of the old Qwen3.8 27B model".

**OPEN QUESTION (not yet answered by the user):** hard-pin
`--restart unless-stopped`, or run the first attempt with no restart policy to
avoid a repack-churn crash loop if the sizing is wrong. Default if unstated:
`--restart unless-stopped` to match every other script in this repo, **with**
`MAX_TOK=16384` which is the mitigation for the crash-loop. If the first start
fails, `docker rm -f halogen-flash-server` before adjusting anything.

---

## Files touched

| File | Action |
|---|---|
| `halogen_flash_server_PLAN.md` | created (this file) |
| `halogen_flash_next.sh` | to create (Phase 1) |
| `current.sh` | symlink to be repointed (Phase 3, pending) |
| `/etc/default/grub` | **no change** — verified already correct |
| repo `./grub` copy | **no change** — stays in sync |

Nothing is committed to git unless asked.

---

## Phase 0 log

- 2026-09-29 — Plan written. Kernel `6.19.8-061908-generic` confirmed running.
- 2026-09-29 — **DEPLOYED.** Kernel 7.0.0-34 confirmed after reboot, server up and
  serving on 8080. See "Execution log" at the bottom for the full record.
- 2026-09-29 — `sudo apt update` run. `noble-updates` now lists
  `linux-generic-hwe-24.04` = `7.0.0-34.34~24.04.1` and
  `linux-image-7.0.0-34-generic` = `7.0.0-34.34~24.04.1`.
  (Confirms the earlier `apt-cache search '^linux-image-7'` result showing only
  cloud flavours was a stale-lists artifact, not a genuine absence.)
- 2026-09-29 — **Dry run first:** `apt-get install -s` showed **0 removals**,
  purely additive. Proceeded.
- 2026-09-29 — `sudo DEBIAN_FRONTEND=noninteractive apt-get install -y
  linux-generic-hwe-24.04` run. Installed:
  `linux-image-7.0.0-34-generic`, `linux-modules-7.0.0-34-generic`,
  `linux-headers-7.0.0-34-generic`, `linux-hwe-7.0-headers-7.0.0-34`,
  `linux-tools-7.0.0-34-generic`, `linux-hwe-7.0-tools-7.0.0-34`,
  `linux-generic-hwe-24.04`, `linux-image-generic-hwe-24.04`,
  `linux-headers-generic-hwe-24.04`, plus `libllvm19` / `libdebuginfod*`.
  initrd generated at `/boot/initrd.img-7.0.0-34-generic` (82.8 MB).
  The processor microcode was already up to date.
- 2026-09-29 — **GRUB verified.** The first menuentry (`GRUB_DEFAULT=0` in
  `/etc/default/grub`) loads `/boot/vmlinuz-7.0.0-34-generic`. Fallback kernels
  all still present under "Advanced options for Ubuntu":
  `6.19.8-061908`, `6.18.12-061812`, `6.8.0-142`, `6.8.0-139`.
  **No GRUB config change was needed or made.**
- 2026-09-29 — Reboot issued. **Everything after this line is unverified; resume
  at the Phase 0 post-reboot verification, then Phase 1.**

### Resume checklist after reboot

1. `uname -r` → expect `7.0.0-34-generic`
2. `cat /proc/cmdline` → confirm `amd_iommu=off` survived
3. `ls -l /dev/kfd /dev/dri/renderD128` → both present
4. `systemctl is-active docker` → active
5. `docker ps -a` → both llama.cpp containers are back (they have
   `--restart unless-stopped`, so they will have auto-started and will be holding
   ~54 GiB of GTT again)
6. `curl -s localhost:8081/v1/models` → embedding model alive
7. **Then stop the llama.cpp main model and check GTT** before starting halogen:
   ```
   docker rm -f llama-server-qwen-first-vulkan
   cat /sys/class/drm/card0/device/mem_info_gtt_used
   ```
   If that is still tens of GiB with no container holding it → reboot again, or
   accept the legible refusal at startup.

### Rollback from the kernel step, if 7.0.0-34 does not boot

Hold `Shift` (BIOS) or `Esc` (UEFI) at boot to reach the GRUB menu, then
**Advanced options for Ubuntu → 6.19.8-061908-generic**. That is a stock
configuration this box has been running, and it is what to boot if halogen
misbehaves in a way that looks kernel-related. Nothing was removed, so this is
purely a boot-menu choice.

### One thing the plan is deliberately NOT doing yet

Phase 1 will not touch `/etc/default/grub`. The `amd_iommu=off ttm.pages_limit=
... amdgpu.lockup_timeout=60000` line is already exactly what upstream measured
on, and `ttm.pages_limit=33554432` (4 KiB pages = 128 GiB) already exceeds
installed RAM, so the driver's GTT total will be ~124 GiB — far more than the
~19 GiB device-side footprint the chosen config needs. Upstream is explicit that
`amdgpu.gttsize` and `ttm.pages_limit` should not be pasted from their machine.

---

## Execution log — 2026-09-29

### Post-reboot verification (Phase 0 resume checklist) — all passed

| Check | Result |
|---|---|
| `uname -r` | `7.0.0-34-generic` |
| `amd_iommu=off` in cmdline | present, full line intact |
| `/dev/kfd` + `/dev/dri/renderD128` | both present |
| docker | active |
| 8081 embedding | alive, `Qwen3-Embedding-8B` |
| GTT before stop | 52,840,833,024 = 49.2 GiB (both llama.cpp containers) |
| GTT after stop | 14,194,606,080 = **13.2 GiB** (the live embed model only — not a leak) |

Upstream's bar verbatim: *"7.0 is the oldest we have seen work."* 7.0.0-34 clears it.

### Three corrections to the plan, made during execution

**1. `HALOGEN_HOST_RESERVE_GIB=30` would have refused to start. Used 16.**
The value is *subtracted from* the budget at the fit check, so raising it makes
the server less generous, not more conservative:

```
MemTotal 124.45 − weights 79.6 = 44.45 GiB available for pool + arena
  reserve 20 → 24.45 avail vs 21.2 needed   ✅ 3.2 GiB margin (upstream default)
  reserve 30 → 14.45 avail vs 21.2 needed   ❌ "refusing to pin … floor is 16.00 GiB"
  reserve 16 → 28.45 avail vs 21.2 needed   ✅ 7.2 GiB margin  ← CHOSEN
```

**2. `HALOGEN_TOKENIZER` does not exist** as a user-facing variable. The image
sets it internally to `/tokenizer`; unset, the entrypoint found the weights
repo's own tokenizer next to the GGUF, exactly as upstream says it should:
`no /tokenizer mount, using …/UD-Q4_K_XL/tokenizer from the models volume`.
The plan's worry about the four-level path was unfounded.

**3. Vision tower dropped (text-only), as decided.** Confirmed at runtime:
`vision.enabled: false`, `disabled_because: [the engine was started without a
vision tower]`. An image request gets a 400 naming the flag. The old 27B ran
with `--mmproj mmproj-BF16.gguf`, so this is a real capability regression.

Also folded in: image pinned to `:0.15.0` (upstream pins in anything durable);
`--restart` deliberately omitted from the first run.

### What actually happened at startup

- Image pull: 3m14s. Repack: **16.2 s for 78.18 GiB at 5.18 GB/s**, 8 threads —
  faster than the 18 s cold reference. Registered Mapped|ReadOnly, device ptr ==
  host ptr. **Engine listening after 22 s.**
- Draft head and tokenizer downloaded on first start into
  `…/UD-Q4_K_XL/` (the entrypoint put them **beside the checkpoint**, so
  `HALOGEN_MTP_HEAD` and `HALOGEN_VISION_TOWER=1` would both have resolved here
  after all — the plan's path concern was over-cautious).
- The GGUF read itself: 1166 tensors repacked into 78.18 GiB, 4 shards,
  1224 tensors total, lookup table read in place. No `affine trunk … staged to
  bf16` line, so no dense-tensor decode penalty.
- **Memory as predicted:** `79.6 GiB weights + 7.2 GiB KV pool + 11.2 GiB
  working memory = 98.0 GiB`. `host memory left for everything else: 252
  contiguous 2 MiB blocks (9.6 GiB total)`.

### Two warnings that are expected, not faults

- `WARNING 13.2 GiB of GTT is in use and no process holds the GPU … /sys/class/kfd/kfd/proc is empty`
  — the embed container is a **Vulkan/llama.cpp** process and is invisible in
  the KFD node list. Verified by hand: 13.2 GiB is exactly the 8 GB embedding
  model plus buffers. Not a leak, and not issue #79.
- `WARNING the host has only 287 contiguous 2 MiB blocks (574 MiB)` before the
  server allocated anything, and `16.5 GiB of host RAM is in use before this
  server starts` — the embed co-tenant. Upstream warns this pushes prompts to
  read the lookup table from disk.

### Verified working

| Check | Result |
|---|---|
| First log line | `halogen-flash-server 0.15.0, mode all` |
| `checkpoint_format` | `gguf` |
| `capability_probe` | `ok` |
| `chat_template.probe` | `passed`, `thinking_control: true` |
| version match | api 0.15.0 / engine 0.15.0, `match: true` |
| short completion | correct, `finish_reason: stop`, 40.8 tok/s decode, 43/38 draft tokens accepted |
| 6,007-token prefill | **1,222 tok/s**, decode 38 tok/s, 7.8 s total |
| 8081 embed after cutover | **still alive**, never recreated |

Decode at 38-41 tok/s beats upstream's 25.2 tok/s figure for `UD-Q4_K_XL`, and
prefill 1,222 tok/s is within 4% of their measured 1,267. The earlier
`host memory left 9.6 GiB` did **not** degrade throughput — the lookup table
stayed in the page cache for both tests.

### Files touched

| File | Action |
|---|---|
| `halogen_flash_next.sh` | **created**, executable |
| `flash.sh` | **created**, symlink → `halogen_flash_next.sh` |
| `current.sh` | untouched (still → `llama_cpp_vulkan_qwen3.8_27b.sh`) |
| `~/.config/opencode/opencode.json` | `limit.output` 131072 → **65536** (above the cap is a 400) |
| `/etc/default/grub` | no change |
| `./grub` | no change |

Nothing committed to git.

### Phase 4 — remaining, not done

1. Flip `--restart unless-stopped` into `halogen_flash_next.sh`.
2. Vision tower: `qwen38-flash-next-vision.hgn` did **not** appear in the
   download (only the draft head and tokenizer), and its filename is not
   published upstream. Needs a `hf download` of the full repo listing to find.
   Cost ~2 GiB → drop `HALOGEN_HOST_RESERVE_GIB` to ~14 to pay for it.
3. `amdgpu.noretry=0` in GRUB — optional, needs a reboot, no change made.
4. `opencode.json:26` still reads `"model": "llama/qwen3.6"` while the `models`
   map only defines `qwen3.8`. Pre-existing, left alone deliberately.

---

## Phase 4 log — vision, restart policy, memory tuning (2026-09-29)

### What changed in `halogen_flash_next.sh`

| Change | Reason |
|---|---|
| `--restart unless-stopped` | First run was proven; a warm restart is only a 16 s repack now |
| `-e HALOGEN_VISION_TOWER=1` | Enable image input |
| `-e HALOGEN_CTX=196608` | **Required** — see below |
| `-e HALOGEN_KV_POOL_POSITIONS=196608` | Buys 1.8 GiB to pay for the tower |
| Auto-download block for the vision file | The entrypoint will not fetch it |

### Finding 1: the entrypoint does not fetch the vision sidecar

`HALOGEN_VISION_TOWER=1` with `HALOGEN_DOWNLOAD` set produced an immediate
crash-loop:

```
halogen: HALOGEN_VISION_TOWER=1 but there is no sidecar at
  /models/.../UD-Q4_K_XL/qwen38-flash-next-vision.hgn
```

The downloader fetches the draft head and tokenizer only. The model card
concedes this ("put it beside the checkpoint"), and the repo listing confirms
the file is there — it just is not on the fetch list. With `--restart` now on,
that loop would never have stopped on its own, so the script now downloads it
with an explicit one-off `hf download` before starting.

The image also bakes in `HF_HUB_OFFLINE=1`; the download needs
`-e HF_HUB_OFFLINE=0` or it fails in one second with "offline mode is enabled".

### Finding 2: KV pool cannot be smaller than the context window

First attempt with `HALOGEN_KV_POOL_POSITIONS=196608` and the default
`HALOGEN_CTX=262144` died 2 s in:

```
flash_serve: --kv-pool 196608: at least --ctx 262144, a multiple of 256
halogen: the engine exited after 2 s without listening.
```

The engine sizes slots against `--ctx`, and the pool is its ceiling. Both must
move together, so `HALOGEN_CTX=196608` was added. Vision itself had loaded fine
by then — `vision ON, tower … (resolved from HALOGEN_VISION_TOWER=1)`.

196608 still covers opencode's worst case: 120000 context + 65536 output =
185536 positions, with 11072 spare. Verified by admitting a `max_tokens:
65536` streaming request and aborting it mid-stream; the slot released cleanly
(`busy: false` afterwards).

### Finding 3: the iGPU reservation is 1.0 GiB, and it is not in /proc/meminfo

```
startup: 1.0 GiB of this machine's RAM is carved out for the iGPU in firmware.
  That is not free memory the OS can lend to the file cache above, and it does
  not appear anywhere in /proc/meminfo: the machine simply reports itself smaller
```

Worth knowing before doing any further arithmetic by hand from `free -h`.

### Final memory state

| | Before (Phase 1-3) | After (Phase 4) |
|---|---|---|
| KV pool (`HALOGEN_CTX=196608`) | 7.2 GiB | 5.4 GiB |
| vision tower | — | +0.84 GiB |
| weights | 79.6 GiB | 79.6 GiB |
| working memory | 11.2 GiB | 11.2 GiB |
| **halogen total** | **98.0 GiB** | **96.2 GiB** |
| **host left for everything else** | 9.6 GiB | **11.0 GiB** |

Net: 1.8 GiB cheaper than before *and* vision on. The 856 MiB tower cost less
than the 2 GiB originally budgeted, and dropping pool+context to 196608 paid
for it with margin to spare. Upstream's bar for the embed co-tenant is met with
~1.4 GiB more room than before.

### Verification

| Check | Result |
|---|---|
| vision in log | `vision ON, tower …/qwen38-flash-next-vision.hgn` |
| `/health` | `vision.enabled: true`, `disabled_because: null` |
| image request | 320x320 PNG, blue square on white → **"Blue"**, correct |
| image cost | 168 prompt tokens (matches the ~1,000 token estimate at 1280x800, scaled) |
| restart policy | `unless-stopped` confirmed on the live container |
| text prefill regression | 1,224 tok/s (was 1,222 — no change) |
| text decode regression | 38 tok/s, 54/27 draft tokens accepted |
| 8081 embed | still up, never recreated, uptime unbroken |
| engine start | 15 s warm (was 22 s cold) |

### Left undone on purpose

- `llama-server-qwen-embed-vulkan` reports `unhealthy` (139 consecutive
  failures). Its healthcheck curls `localhost:8080` but it listens on 8081 —
  a pre-existing bug in `llama_cpp_vulkan_qwen3.8_27b.sh:95`, cosmetic only,
  the model serves fine. Not fixed, because fixing it means recreating a
  container Agent Zero depends on.
- `amdgpu.noretry=0` — not measured to be needed, and it needs a reboot.
- `opencode.json:26` still says `"model": "llama/qwen3.6"`; pre-existing.


---

## Phase 5 log — the 256K attempt, and why the box is full (2026-09-30)

### What was attempted

Raising the pool to the model's full window, per request:
`HALOGEN_CTX=262144`, `HALOGEN_KV_POOL_POSITIONS=262144`,
`HALOGEN_MAX_TOKENS_CAP=131072`, opencode `output: 131072`. Cost: +1.9 GiB of
pool over the working 196608 config. Headroom was measured at 9.6 GiB at boot
and the Phase 1-3 run had used that exact pool for hours without incident.

### It does not fit. The engine refused, correctly.

```
checkpoint: refusing to pin 0.84 GiB, MemAvailable is 13.92 GiB and the floor
is 16.00 GiB: this configuration is 2.92 GiB short on this host.
```

The pin is the **vision tower**, not the pool. Upstream's reasoning is printed
in the log and is the whole story of this box:

> Pinned pages cannot be swapped out, and a task waiting on them cannot be
> killed, so over-pinning wedges the whole machine for minutes at a time
> rather than failing; under 16 GiB left the lookup table pages in from disk on
> every long prompt and prefill takes minutes, which is what the floor refuses.

So the floor is a hard wall, not advice. A server that will not start is the
correct outcome.

### Why this was not visible in Phase 4

Phase 4's start saw `MemAvailable 107.9 GiB` and left `11.0 GiB`. This
afternoon the same config sees `102.8 GiB` pre-start and is `2.80 GiB short` at
the same pin point. The 5 GiB difference is **not** a config change — it is
page cache and session state. The 26.8 GiB lookup table is read through the
file cache, so `MemAvailable` moves with how much cache the box happens to be
holding. The Phase 4 start was lucky, not safe. `buff/cache` is now 5 GiB
against 10 GiB then.

Controlling arithmetic, for the record:

```
MemTotal                              124.4 GiB   (1.0 GiB of it is iGPU
                                                    firmware carve-out,
                                                    invisible in meminfo)
  - weights                            79.6
  - KV pool 196608                      5.4
  - working memory @16384              11.2
  - embed container, 32k ctx q8_0      16.5   <- the co-tenant
  - OS, session, everything else       ~6
  ------------------------------------------
  = halogen total                       96.2
    left for everything else            6.1   (was 11.0 at the Phase 4 start)
```

There is no slack. 96.2 + 16.5 = 112.7 of 124.4 is committed before the OS
takes its share.

### The crash-loop made it much worse, and that is a standing hazard

`--restart unless-stopped` turned one refusal into **12 restarts**, and each new
attempt started while the previous attempt's engine was still dying:

```
PID 181560  flash_serve  RSS 58.16 GiB  355% CPU   <- attempt N-1, still dying
```

Pinned pages are unkillable, so a dying engine holds its arena for tens of
seconds. Every retry therefore measured a *worse* machine than the one that
failed, which is a self-reinforcing spiral: 102 GiB available on a clean slate,
`available=14.04` at the pin point mid-loop.

`--restart unless-stopped` is still set, because the current config does start
reliably and it was asked for. But the pairing is a hazard: any future edit
that pushes the fit over the floor again converts a clean, legible refusal into
a 12-restart thrash that leaves the box degraded long after the failure. Drop
the policy, or run the recovery/verify block below by hand after any memory
knob change, before trusting an auto-restart.

Recovery, once a loop is in progress:

```bash
docker update --restart=no halogen-flash-server   # stop it respawning
docker rm -f halogen-flash-server
while pgrep flash_serve >/dev/null; do sleep 5; done   # let the arena go
free -g                                                  # expect ~102 GiB
```

### Two landmines found

- **`HALOGEN_VISION_TOWER=0` hangs the entrypoint.** `0` is not a valid value;
  the entrypoint prints "does not exist" and then waits on a prompt with no TTY
  attached, forever, with no further log output. Off means *absent*.
- **A `#` comment inside the `docker run` backslash continuation silently eats
  the rest of the command** — the following `-e` flags become part of the
  comment. Verified with a minimal repro; the comment explaining the disabled
  vision flag now lives in the header block instead.

### Current state — working, text-only, no regressions

| | |
|---|---|
| pool / ctx | 196608 (unchanged from Phase 4) |
| output cap | 65536 (opencode `output` reverted to 65536 to match) |
| vision | **off** — the 0.84 GiB pin is ~2.8 GiB over the floor |
| prefill | 1,224 tok/s — identical to Phase 4 |
| embed container | untouched, 15 h uptime |
| host left at boot | 6.1 GiB |

### What it would take to get vision and the full 256K back

Both are blocked by the same 16 GiB pin floor, and the only meaningful source
of slack on this machine is the embed container's 16.5 GiB:

| Action | Frees | Cost |
|---|---|---|
| recreate embed with `-c 8192 -b 4096 -ub 4096` | ~2-3 GiB | ~1 min a0 embedding outage |
| `HALOGEN_MAX_TOK` 16384 → 12288 | ~2.8 GiB | ~5% prefill speed |
| `HALOGEN_KV_POOL_POSITIONS` → 163840 | ~0.9 GiB | context window down |
| `HALOGEN_PROMPT_CACHE=0` | ~1.3 GiB | repeated-prefix prefill, painful for agents |

The first is the only one that pays for both vision and the 262144 pool, and
even then the margin is ~1 GiB against a hard wall. Not taken without a
decision.

---

## Phase 6 log — vision restored by shrinking the co-tenant (2026-09-30)

### First, a hypothesis that was wrong

The refusal said *"the floor is 16.00 GiB"* and we run `HALOGEN_HOST_RESERVE_GIB=16`.
Those looked like the same knob. Tested it: reserve **12**, vision on.

```
checkpoint: refusing to pin 0.84 GiB, MemAvailable is 13.98 GiB and the floor is
16.00 GiB: this configuration is 2.85 GiB short on this host.
```

Floor unmoved at exactly 16.00. The reserve sizes the *pre-flight budget*; the
pin floor is a separate, fixed constant. Worth having ruled out — it would have
been the free fix.

### What actually paid for vision: the embed container

`llama-server-qwen-embed-vulkan` was configured `-c 32768 -b 8192 -ub 8192` and
held **13.2 GiB of GTT** — which is host RAM, the largest reclaimable block on
the machine. Recreated with `-c 8192 -b 4096 -ub 4096`:

| | before | after |
|---|---|---|
| embed GTT | 13.2 GiB | **11.25 GiB** |
| `free` available before halogen | 102 GiB | **109 GiB** |
| host left after halogen boot | 6.1 GiB | **13.0 GiB** |
| vision | refused to start | **on, verified** |

Everything else on that container was preserved byte-for-byte from
`docker inspect`: same image, same model, q8_0 K/V cache, `-ngl 999`,
`--flash-attn on`, `--no-mmap`, `--pooling last`, same alias, same groups and
security opts. 8192 context is ample for a0's chunks. Outage was **6 s** (warm
weights), and embedding output was verified after: 4096-dim, norm 1.000.

Also dropped `--healthcheck` on that container. The image's built-in check
cures `localhost:8080` on a server listening on 8081, which is why it had been
sitting at `unhealthy` for 139 consecutive failures while serving perfectly
well. No code depended on the status; the false signal is gone.

### The preflight guard, and the ordering bug in it

The crash-loop taught the real lesson, so `halogen_flash_next.sh` now refuses to
start rather than thrash:

```
NEEDED_MB = 16 GiB (engine pin floor) + 900 MiB (0.84 GiB vision pin)
if MemAvailable < NEEDED_MB -> print why, print recovery, exit 1
```

**The first version of that guard was wrong and I caught it in testing.** It ran
at the top of the script — before `docker rm -f halogen-flash-server` — so on an
ordinary restart the *old* server was still holding 96 GiB and the guard would
have refused every legitimate restart. It now runs *after* teardown, and after
waiting for the old arena:

```bash
while pgrep flash_serve >/dev/null 2>&1; do sleep 3; done   # pinnade sidor är inte avlivbara
```

That wait is not cosmetic. A dying engine holds its 78 GiB arena for tens of
seconds, and skipping it is exactly what turned one refusal into a spiral.

### Verified final state

| Check | Result |
|---|---|
| boot | clean, **0 restarts**, engine listening after 20 s |
| `host memory left` | 13.0 GiB (was 6.1 without the embed shrink) |
| vision | `enabled: true`, image → **"Blue"**, correct |
| text prefill | **1,221 tok/s** — no regression (1,222/1,224/1,225 across runs) |
| text decode | 38 tok/s |
| 8081 embed | recreated, 4096-dim norm 1.0, 6 s outage |
| WAN `194.68.41.14:8880` | up, vision true |
| `opencode.json` | `output: 65536` on both providers — matches the 196608 pool |

### Still true, unchanged

Context and output are back at the Phase 4 values: **pool/ctx 196608, output cap
65536**. The 262144 pool needs ~1.8 GiB *more* than this, and the headroom above
the pin floor is now roughly 2 GiB. It would go, but not with any margin, and a
refused start on this box is expensive to recover from. Not worth it without
freeing another ~2 GiB somewhere.

Remaining ideas, if a0's context is ever raised again or another model is added:
- `HALOGEN_MAX_TOK` 16384 → 12288: ~2.8 GiB, ~5% prefill
- `HALOGEN_PROMPT_CACHE=0`: ~1.3 GiB, hurts agent repeat-prefix prefill
- embed container to `-c 4096`: another ~0.3 GiB
