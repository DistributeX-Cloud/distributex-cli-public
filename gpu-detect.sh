#!/bin/bash
# gpu-detect.sh - Comprehensive GPU Detection for Docker Worker
# Returns JSON with GPU information

set -e

# Initialize output
GPU_AVAILABLE="false"
GPU_MODEL="None"
GPU_MEMORY_GB=0
GPU_COUNT=0
GPU_VENDOR="none"
GPU_COMPUTE_CAPABILITY=""

# Function to detect NVIDIA GPUs
detect_nvidia() {
    if command -v nvidia-smi &> /dev/null; then
        # Check if GPU is accessible
        if nvidia-smi &> /dev/null; then
            GPU_AVAILABLE="true"
            GPU_VENDOR="nvidia"
            
            # Get GPU count
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader | head -1)
            
            # Get first GPU info
            GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
            
            # Get memory in GB
            MEMORY_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
            GPU_MEMORY_GB=$(echo "scale=2; $MEMORY_MB / 1024" | bc)
            
            # Get compute capability
            GPU_COMPUTE_CAPABILITY=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -1 || echo "")
            
            return 0
        fi
    fi
    return 1
}

# Function to detect AMD GPUs
detect_amd() {
    # Check for ROCm
    if command -v rocm-smi &> /dev/null; then
        if rocm-smi &> /dev/null; then
            GPU_AVAILABLE="true"
            GPU_VENDOR="amd"
            GPU_COUNT=1
            
            # Try to get GPU name
            GPU_MODEL=$(rocm-smi --showproductname 2>/dev/null | grep -oP 'GPU\[\d+\].*:\K.*' | head -1 || echo "AMD GPU (ROCm)")
            
            # Try to get VRAM
            VRAM_INFO=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
            if [ "$VRAM_INFO" -gt 0 ]; then
                GPU_MEMORY_GB=$(echo "scale=2; $VRAM_INFO / 1024 / 1024 / 1024" | bc)
            fi
            
            return 0
        fi
    fi
    
    # Fallback: Check for AMD via lspci
    if command -v lspci &> /dev/null; then
        AMD_GPUS=$(lspci | grep -iE "vga|3d|display" | grep -i "amd\|radeon" || true)
        if [ -n "$AMD_GPUS" ]; then
            GPU_AVAILABLE="true"
            GPU_VENDOR="amd"
            GPU_COUNT=$(echo "$AMD_GPUS" | wc -l)
            GPU_MODEL=$(echo "$AMD_GPUS" | head -1 | grep -oP ':\s*\K.*' || echo "AMD GPU")
            return 0
        fi
    fi
    
    return 1
}

# Function to detect Intel GPUs
detect_intel() {
    if command -v lspci &> /dev/null; then
        INTEL_GPUS=$(lspci | grep -iE "vga|3d|display" | grep -i "intel" || true)
        if [ -n "$INTEL_GPUS" ]; then
            # Check if it's Arc GPU (discrete) or integrated
            if echo "$INTEL_GPUS" | grep -qi "arc"; then
                GPU_AVAILABLE="true"
                GPU_VENDOR="intel"
                GPU_COUNT=1
                GPU_MODEL=$(echo "$INTEL_GPUS" | head -1 | grep -oP ':\s*\K.*' || echo "Intel Arc GPU")
                return 0
            fi
        fi
    fi
    
    return 1
}

# Try detection in order of preference
detect_nvidia || detect_amd || detect_intel

# Output JSON
cat << EOF
{
  "gpuAvailable": $GPU_AVAILABLE,
  "gpuModel": "$GPU_MODEL",
  "gpuMemoryGb": $GPU_MEMORY_GB,
  "gpuCount": $GPU_COUNT,
  "gpuVendor": "$GPU_VENDOR",
  "gpuComputeCapability": "$GPU_COMPUTE_CAPABILITY"
}
EOF
