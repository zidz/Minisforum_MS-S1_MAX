#!/bin/bash
# ==============================================================================
# GLM-5.2 (744B MoE) Deployment Script via Colibri Engine
# Target: Minisforum MS-S1 Max (AMD Strix Halo, 128GB LPDDR5x, Ubuntu 24.04.4)
# ==============================================================================

set -e # Enforce strict execution; exit immediately on non-zero status

# Global Directory and Repository Definitions
#MODEL_DIR="./models/glm-5.2"
MODEL_DIR="./models/DeepSeek-V4-Flash-0731"
#REPO_ID="mastouri/GLM-5.2-colibri-int4-g64-with-int8-mtp"
REPO_ID="deepseek-ai/DeepSeek-V4-Flash-0731"
COLIBRI_DIR="./colibri"

# ==============================================================================
# Function: Initialize System, Download Model, and Compile Engine
# ==============================================================================
init_system() {
    echo ">>> [1/5] Tuning Ubuntu Linux Kernel Parameters..."
    # Increase maximum memory-mapped areas for huge safetensors allocations.
    # Essential for loading 21,504 MoE experts without kernel panic.
    sudo sysctl -w vm.max_map_count=2097152
    
    # Persist the setting across system reboots
    if ! grep -q "vm.max_map_count=2097152" /etc/sysctl.conf; then
        echo "vm.max_map_count=2097152" | sudo tee -a /etc/sysctl.conf > /dev/null
    fi

    echo ">>> [2/5] Installing Build Dependencies..."
    # Install GCC, OpenMP, and Python requirements
    sudo apt-get update
    sudo apt-get install -y build-essential git python3 python3-pip python3-venv libgomp1

    echo ">>> [3/5] Configuring Hugging Face CLI and Xet Backend..."
    # Install the CLI and the high-performance Xet rust binary
    pip3 install -U "huggingface_hub[cli]" hf_xet --break-system-packages

    echo ">>> [4/5] Downloading GLM-5.2 MoE Container (~372 GB)..."
    # Enable high-performance concurrent chunk downloading to saturate bandwidth
    export HF_XET_HIGH_PERFORMANCE=1
    
    # Download the specific INT4-g64 container with the INT8 MTP head
    # The --local-dir flag ensures the model is placed precisely at the user's request
    hf download "$REPO_ID" --local-dir "$MODEL_DIR"

    echo ">>> [5/5] Cloning and Compiling the Colibri Engine..."
    if [ ! -d "$COLIBRI_DIR" ]; then
        git clone https://github.com/JustVugg/colibri.git "$COLIBRI_DIR"
    fi
    
    # Compile the engine from source
    # ARCH=native is strictly required to unlock AVX-512 VNNI instructions on Zen 5
    cd "$COLIBRI_DIR/c"
    make glm ARCH=native
    #make glm VK=1                # needs libvulkan + glslc (shaderc) for the shaders
    #make deepseek-v4
    cd ../..

    echo ">>> Initialization Complete. You can now run the script with no arguments to start."
}

# ==============================================================================
# Function: Start the Colibri Inference Engine
# ==============================================================================
start_engine() {
    echo ">>> Configuring Runtime Environment Variables..."
    
    # 1. I/O Optimizations for NVMe
    export DIRECT=1     # Bypass Linux page cache (O_DIRECT) to prevent memory thrashing
    export PIPE=1       # Enable overlapping of expert disk-loads with mathematical compute
    export URING=1      # Enable Linux io_uring for async queue depth saturation
    export MLOCK=-1     # Wire the expert cache into physical RAM, dodging memory compression
    
    # 2. CPU and Thread Affinity Optimizations (Strix Halo - 16 Cores)
    export OMP_PROC_BIND=spread  # Distribute threads evenly across physical cores
    export OMP_PLACES=cores      # Lock threads to physical cores, preventing OS context switching
    export OMP_NUM_THREADS=32
    
    # 3. Model Path
    export COLI_MODEL="$MODEL_DIR"

    # 4. Allow listening from host IP
    export COLI_ALLOW_INSECURE_BIND=1

    # 5. Set context size
    export CTX=16000

    # 6. Restore mangled output automatically
    export COLI_TOOL_SALVAGE=1
    
    # Enable Vulkan
    export COLI_VULKAN=1
    export COLI_VK_DENSE=1
    export COLI_VK_ATTN=1
    export PIN=models/glm-5.2/.coli_usage
    export PIN_GB=0
    export COLI_NO_OMP_TUNE=1

    # Other
    export DRAFT=1
    #export KVSAVE=0
    export THINK=1
    export PILOT=1
    

    echo ">>> Booting GLM-5.2 via Colibri Chat Interface..."
    # Launch the python wrapper which executes the compiled C engine
    # --topp 0.7 reduces the sampling nucleus, mathematically decreasing the number 
    # of experts required per token without degrading quality, saving NVMe bandwidth.
    #./colibri/c/coli serve --model models/glm-5.2/ --ram 40 --host 10.99.7.1 --port 8088 --topp 0.7
    #./colibri/c/coli serve --model models/glm-5.2/ --host 10.99.7.1 --port 8088 --topp 0.7 --ram 100
    ./colibri/c/coli serve --model models/glm-5.2/ --host 10.99.7.1 --port 8088 #--temp 0
    #./colibri/c/coli serve --model models/DeepSeek-V4-Flash-0731/ --host 10.99.7.1 --port 8088
    #refusing to bind 10.99.7.1 beyond localhost without COLI_API_KEY set (set COLI_ALLOW_INSECURE_BIND=1 to override)
    #python3 "$COLIBRI_DIR/coli" chat --topp 0.7
}

# ==============================================================================
# Script Execution Router
# ==============================================================================
if [ "$1" == "--init" ]; then
    init_system
else
    # The user requested that --start be the default execution path
    start_engine
fi
