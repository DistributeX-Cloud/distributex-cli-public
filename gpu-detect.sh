#!/bin/bash
# gpu-detect.sh - GPU detection stub
# This file is not currently used but kept for backward compatibility
# GPU detection is now handled directly in distributex-worker.js

echo '{
  "gpuAvailable": false,
  "gpuModel": "None",
  "gpuMemoryGb": 0,
  "gpuCount": 0,
  "gpuVendor": "none"
}'
