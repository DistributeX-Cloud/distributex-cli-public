## 🚀 Quick Start

### Mode 1: Contributor (Share Resources)

**One command to start contributing:**

```bash
curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/public/install.sh | bash
```

**What this does:**
1. ✅ Auto-detects your system (CPU, RAM, GPU, Storage)
2. ✅ Creates account or logs you in
3. ✅ Registers your device
4. ✅ Starts sharing resources
5. ✅ Sets up auto-start on boot

**Resource sharing is intelligent:**
- 30-50% of CPU cores (based on total)
- 20-30% of available RAM
- 50% of GPU when idle
- 10-20% of free storage
- **Zero impact** on your daily use with smart throttling

---

# 🎉 Awesome! Now let's use the network!

## Python - Complete Usage Guide

### 1. Install & Setup

```bash
# Install SDK
pip3 install distributex-cloud

# Set your API key (permanent)
echo 'export DISTRIBUTEX_API_KEY="dx_your_key_here"' >> ~/.bashrc
source ~/.bashrc

# Or set for current session only
export DISTRIBUTEX_API_KEY="dx_your_key_here"
```

### 2. Simple Function Execution

```python
from distributex import DistributeX

# Initialize
dx = DistributeX()

# Define any Python function
def calculate_pi(iterations):
    """Monte Carlo Pi estimation"""
    import random
    inside = 0
    for _ in range(iterations):
        x, y = random.random(), random.random()
        if x*x + y*y <= 1:
            inside += 1
    return 4 * inside / iterations

# Run on distributed network
result = dx.run(
    calculate_pi,
    args=(1000000,),
    workers=4,
    cpu_per_worker=2,
    ram_per_worker=2048
)

print(f"Pi ≈ {result}")
```

### 3. Run Python Script File

```python
from distributex import DistributeX

dx = DistributeX()

# Run any Python script on the network
result = dx.run_script(
    'train_model.py',
    runtime='python',
    workers=2,
    cpu_per_worker=4,
    ram_per_worker=8192,
    gpu=True,              # Require GPU
    cuda=True,             # Require CUDA
    timeout=7200,          # 2 hours
    input_files=['data.csv'],
    output_files=['model.pkl', 'results/'],
    env={'BATCH_SIZE': '32'}
)

print(f"Training complete: {result}")
```

### 4. Machine Learning Training

```python
from distributex import DistributeX

dx = DistributeX()

# Train ML model with GPU acceleration
def train_neural_network(data, epochs=10):
    import torch
    import torch.nn as nn
    
    model = nn.Sequential(
        nn.Linear(784, 128),
        nn.ReLU(),
        nn.Linear(128, 10)
    )
    
    optimizer = torch.optim.Adam(model.parameters())
    # ... training loop ...
    
    return model.state_dict()

# Execute on 4 GPU workers
model = dx.run(
    train_neural_network,
    args=(training_data,),
    kwargs={'epochs': 50},
    workers=4,
    cpu_per_worker=8,
    ram_per_worker=16384,
    gpu=True,
    cuda=True,
    timeout=3600
)
```

### 5. Parallel Data Processing

```python
from distributex import DistributeX

dx = DistributeX()

# Process multiple files in parallel
files = ['data1.csv', 'data2.csv', 'data3.csv', 'data4.csv']

tasks = []
for file in files:
    task = dx.run_script(
        'process.py',
        input_files=[file],
        output_files=['processed/'],
        workers=1,
        cpu_per_worker=4,
        wait=False  # Don't wait, submit all at once
    )
    tasks.append(task)

# Wait for all to complete
results = [dx.get_result(t.id) for t in tasks]
print(f"Processed {len(results)} files")
```

### 6. Docker Container Execution

```python
from distributex import DistributeX

dx = DistributeX()

# Run TensorFlow in Docker with GPU
result = dx.run_docker(
    image='tensorflow/tensorflow:latest-gpu',
    command='python /workspace/train.py',
    workers=2,
    cpu_per_worker=8,
    ram_per_worker=32768,
    gpu=True,
    volumes={
        '/local/data': '/workspace/data',
        '/local/output': '/workspace/output'
    },
    env={
        'EPOCHS': '100',
        'BATCH_SIZE': '64'
    }
)

print(f"Docker training complete: {result}")
```

### 7. Video Processing

```python
from distributex import DistributeX

dx = DistributeX()

# Process video with FFmpeg
result = dx.run_script(
    'process_video.py',
    runtime='python',
    workers=1,
    cpu_per_worker=8,
    ram_per_worker=8192,
    gpu=True,  # Use GPU for encoding
    input_files=['input.mp4'],
    output_files=['output.mp4', 'thumbnail.jpg'],
    timeout=3600
)
```

### 8. Scientific Computing

```python
from distributex import DistributeX
import numpy as np

dx = DistributeX()

# Distributed matrix multiplication
def matrix_multiply(matrix_a, matrix_b):
    import numpy as np
    return np.dot(matrix_a, matrix_b)

A = np.random.rand(1000, 1000)
B = np.random.rand(1000, 1000)

result = dx.run(
    matrix_multiply,
    args=(A, B),
    workers=1,
    cpu_per_worker=16,
    ram_per_worker=16384
)

print(f"Result shape: {result.shape}")
```

### 9. Monitor Task Progress

```python
from distributex import DistributeX
import time

dx = DistributeX()

# Submit task without waiting
task = dx.run_script(
    'long_running.py',
    workers=1,
    wait=False
)

print(f"Task ID: {task.id}")

# Poll for status
while True:
    status = dx.get_task(task.id)
    print(f"Status: {status.status} - Progress: {status.progress}%")
    
    if status.status == 'completed':
        result = dx.get_result(task.id)
        print(f"Result: {result}")
        break
    
    if status.status == 'failed':
        print(f"Error: {status.error}")
        break
    
    time.sleep(5)
```

### 10. Network Statistics

```python
from distributex import DistributeX

dx = DistributeX()

# Check network availability
stats = dx.network_stats()

print(f"Active Workers: {stats['activeWorkers']}")
print(f"Available CPU: {stats['availableCpuCores']} cores")
print(f"Available RAM: {stats['availableRam'] // 1024} GB")
print(f"Available GPUs: {stats['availableGpus']}")
print(f"Active Tasks: {stats['activeTasks']}")
```

---

## JavaScript/Node.js - Complete Usage Guide

### 1. Install & Setup

```bash
# Install SDK
npm install -g distributex-cloud

# Set your API key (permanent)
echo 'export DISTRIBUTEX_API_KEY="dx_your_key_here"' >> ~/.bashrc
source ~/.bashrc

# Or set for current session only
export DISTRIBUTEX_API_KEY="dx_your_key_here"
```

### 2. Simple Function Execution

```javascript
const DistributeX = require('distributex-cloud');

// Initialize
const dx = new DistributeX();

// Define any function
const calculatePi = (iterations) => {
  let inside = 0;
  for (let i = 0; i < iterations; i++) {
    const x = Math.random();
    const y = Math.random();
    if (x*x + y*y <= 1) inside++;
  }
  return 4 * inside / iterations;
};

// Run on distributed network
dx.run(calculatePi, {
  args: [1000000],
  workers: 4,
  cpuPerWorker: 2,
  ramPerWorker: 2048
}).then(result => {
  console.log(`Pi ≈ ${result}`);
});
```

### 3. Run JavaScript/Node.js Script

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Run any Node.js script on the network
dx.runScript('process.js', {
  runtime: 'node',
  workers: 2,
  cpuPerWorker: 4,
  ramPerWorker: 8192,
  inputFiles: ['data.json'],
  outputFiles: ['results.json'],
  env: { NODE_ENV: 'production' },
  timeout: 3600
}).then(result => {
  console.log('Processing complete:', result);
});
```

### 4. Web Scraping at Scale

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Scrape multiple websites in parallel
const scraper = (url) => {
  const https = require('https');
  return new Promise((resolve) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data.length));
    });
  });
};

const urls = [
  'https://example.com',
  'https://example.org',
  'https://example.net'
];

// Submit all in parallel
const tasks = urls.map(url => 
  dx.run(scraper, {
    args: [url],
    workers: 1,
    cpuPerWorker: 2,
    wait: false
  })
);

// Wait for all
Promise.all(tasks.map(t => dx.waitForCompletion(t.id)))
  .then(results => {
    console.log('All scraping complete:', results);
  });
```

### 5. Docker Container Execution

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Run Python in Docker
dx.runDocker('python:3.11', {
  command: 'python -c "import numpy; print(numpy.random.rand(5))"',
  workers: 1,
  cpuPerWorker: 4,
  ramPerWorker: 4096,
  env: { PYTHONUNBUFFERED: '1' }
}).then(result => {
  console.log('Docker result:', result);
});
```

### 6. Image Processing

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Process images in batch
dx.runScript('resize_images.js', {
  runtime: 'node',
  workers: 4,
  cpuPerWorker: 2,
  ramPerWorker: 4096,
  inputFiles: ['images/*.jpg'],
  outputFiles: ['thumbnails/'],
  timeout: 1800
}).then(() => {
  console.log('All images processed!');
});
```

### 7. Data Analysis

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Analyze large dataset
const analyzeData = (data) => {
  const sum = data.reduce((a, b) => a + b, 0);
  const mean = sum / data.length;
  const variance = data.reduce((acc, val) => 
    acc + Math.pow(val - mean, 2), 0) / data.length;
  
  return {
    count: data.length,
    sum,
    mean,
    variance,
    stdDev: Math.sqrt(variance)
  };
};

const bigData = Array.from({length: 1000000}, () => Math.random());

dx.run(analyzeData, {
  args: [bigData],
  workers: 1,
  cpuPerWorker: 8,
  ramPerWorker: 8192
}).then(stats => {
  console.log('Analysis:', stats);
});
```

### 8. Async/Await Pattern

```javascript
const DistributeX = require('distributex-cloud');

async function main() {
  const dx = new DistributeX();
  
  // Check network
  const stats = await dx.networkStats();
  console.log(`Workers available: ${stats.activeWorkers}`);
  
  // Run task
  const result = await dx.run((x, y) => x + y, {
    args: [5, 10],
    cpuPerWorker: 1
  });
  
  console.log(`Result: ${result}`);
}

main().catch(console.error);
```

### 9. Run Python from Node.js

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

// Execute Python code from JavaScript
dx.runScript('analysis.py', {
  runtime: 'python',
  workers: 2,
  cpuPerWorker: 4,
  ramPerWorker: 8192,
  gpu: true,
  inputFiles: ['dataset.csv'],
  outputFiles: ['results.json']
}).then(result => {
  console.log('Python analysis complete:', result);
});
```

### 10. Monitor Progress

```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX();

async function runWithProgress() {
  // Submit without waiting
  const task = await dx.run(() => {
    // Long running task
    let sum = 0;
    for (let i = 0; i < 1e9; i++) sum += i;
    return sum;
  }, {
    workers: 1,
    cpuPerWorker: 4,
    wait: false
  });
  
  console.log(`Task submitted: ${task.id}`);
  
  // Poll for updates
  while (true) {
    const status = await dx.getTask(task.id);
    console.log(`Status: ${status.status} - ${status.progressPercent}%`);
    
    if (status.status === 'completed') {
      const result = await dx.downloadResult(task.id);
      console.log(`Result: ${result}`);
      break;
    }
    
    if (status.status === 'failed') {
      console.error(`Failed: ${status.errorMessage}`);
      break;
    }
    
    await new Promise(r => setTimeout(r, 5000));
  }
}

runWithProgress();
```

---

## Quick Reference Commands

### Python One-Liners

```bash
# Simple calculation
python3 -c "from distributex import DistributeX; dx = DistributeX(); print(dx.run(lambda x: x**2, args=(10,)))"

# Network stats
python3 -c "from distributex import DistributeX; dx = DistributeX(); print(dx.network_stats())"

# Run script
python3 -c "from distributex import DistributeX; dx = DistributeX(); dx.run_script('script.py', workers=2, gpu=True)"
```

### JavaScript One-Liners

```bash
# Simple calculation
node -e "const DX = require('distributex-cloud'); new DX().run(x => x**2, {args: [10]}).then(console.log)"

# Network stats
node -e "const DX = require('distributex-cloud'); new DX().networkStats().then(console.log)"

# Run script
node -e "const DX = require('distributex-cloud'); new DX().runScript('script.js', {workers: 2, gpu: true})"
```

---

## Resource Specifications

### CPU & RAM
- **Light tasks**: 1-2 cores, 1-2 GB RAM
- **Medium tasks**: 4-8 cores, 4-8 GB RAM
- **Heavy tasks**: 8-16 cores, 16-32 GB RAM

### GPU
- Set `gpu=True` for GPU acceleration
- Set `cuda=True` if you need CUDA specifically
- Useful for: ML training, video encoding, rendering

### Workers
- **1 worker**: Single execution
- **Multiple workers**: Parallel processing (split your workload)

### Timeout
- Default: 3600 seconds (1 hour)
- Max: 86400 seconds (24 hours)

---

## Common Use Cases

| Use Case | Workers | CPU/Worker | RAM/Worker | GPU |
|----------|---------|------------|------------|-----|
| Data Analysis | 1-4 | 4-8 | 8 GB | No |
| ML Training | 1-4 | 8-16 | 16-32 GB | Yes |
| Video Processing | 1-2 | 8 | 8 GB | Yes |
| Web Scraping | 4-10 | 2 | 2 GB | No |
| Image Processing | 2-8 | 4 | 4 GB | Optional |
| Scientific Computing | 1-4 | 16 | 16 GB | No |

---
