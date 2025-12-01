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

# DistributeX Developer Guide

**Run your code on a global pool of CPU, RAM, GPU, and Storage**

> **New to DistributeX?** This is the developer guide.

---

## 🚀 Quick Start (2 minutes)

### Step 1: Get Your API Key

1. Sign up at [distributex-cloud-network.pages.dev](https://distributex-cloud-network.pages.dev)
2. Select **"Developer"** role during signup
3. Copy your API key (shown only once!)

### Step 2: Install SDK

**Python:**
```bash
pip install distributex-cloud
```

**JavaScript:**
```bash
npm install distributex-cloud
```

### Step 3: Run Your First Task

**Python:**
```python
from distributex import DistributeX

# Initialize with your API key
dx = DistributeX(api_key="dx_your_api_key_here")

# Run any Python function
def process_data(data):
    # Your code here
    result = sum(data)
    return result

# Execute on the network
result = dx.run(process_data, args=([1, 2, 3, 4, 5],))
print(f"Result: {result}")  # Output: 15
```

**JavaScript:**
```javascript
const DistributeX = require('distributex-cloud');

// Initialize with your API key
const dx = new DistributeX('dx_your_api_key_here');

// Run any function
const result = await dx.run((data) => {
  return data.reduce((a, b) => a + b, 0);
}, { args: [[1, 2, 3, 4, 5]] });

console.log(`Result: ${result}`); // Output: 15
```

---

## 📦 What Can You Run?

### Python Scripts
```python
dx.run_script('train.py', 
    gpu=True,
    workers=4,
    cpuPerWorker=8,
    ramPerWorker=16384  # MB
)
```

### JavaScript/Node.js
```javascript
await dx.runScript('process.js', {
  workers: 2,
  cpuPerWorker: 4
});
```

### Docker Containers
```python
# Python
dx.run_docker('tensorflow/tensorflow:latest-gpu',
    command='python train.py',
    gpu=True,
    ramPerWorker=32768
)
```

```javascript
// JavaScript
await dx.runDocker('python:3.11', {
  command: 'python script.py',
  cpuPerWorker: 4
});
```

### Any Runtime
- Python (2.x, 3.x)
- Node.js
- Java
- Go
- Rust
- Ruby
- PHP
- Docker containers

---

## 💡 Real-World Examples

### 1. Machine Learning Training
```python
from distributex import DistributeX

dx = DistributeX(api_key="your_key")

# Train model on 4 GPUs
result = dx.run_script('train_model.py',
    workers=4,
    gpu=True,
    cuda=True,
    cpuPerWorker=16,
    ramPerWorker=32768,
    timeout=7200  # 2 hours
)
```

### 2. Video Processing
```python
# Process multiple videos in parallel
files = ['video1.mp4', 'video2.mp4', 'video3.mp4']

for video in files:
    dx.run_script('process_video.py',
        inputFiles=[video],
        outputFiles=['output/'],
        workers=1,
        cpuPerWorker=8,
        gpu=True,
        wait=False  # Don't block
    )
```

### 3. Data Analysis
```javascript
const DistributeX = require('distributex-cloud');
const dx = new DistributeX('your_key');

// Analyze large dataset
const result = await dx.runScript('analyze.py', {
  inputFiles: ['data.csv'],
  outputFiles: ['results.json'],
  workers: 4,
  cpuPerWorker: 8,
  ramPerWorker: 16384
});
```

### 4. Parallel Processing
```python
# Process 100 items in parallel
items = range(100)
tasks = []

for item in items:
    task = dx.run(process_item, 
        args=(item,), 
        wait=False
    )
    tasks.append(task)

# Wait for all
results = [dx.get_result(t.id) for t in tasks]
```

---

## 🎯 Resource Allocation

### CPU & RAM
```python
# Light task
dx.run_script('light.py',
    cpuPerWorker=2,
    ramPerWorker=2048  # 2 GB
)

# Heavy task
dx.run_script('heavy.py',
    cpuPerWorker=16,
    ramPerWorker=32768  # 32 GB
)
```

### GPU Acceleration
```python
# Require GPU
dx.run_script('train.py',
    gpu=True,           # Any GPU
    cuda=True,          # CUDA required
    ramPerWorker=16384
)
```

### Multiple Workers
```python
# Split work across 8 workers
dx.run_script('distributed.py',
    workers=8,
    cpuPerWorker=4,
    ramPerWorker=8192
)
```

---

## 📊 API Reference

### Initialize Client
```python
from distributex import DistributeX

dx = DistributeX(
    api_key="your_api_key",
    base_url="https://distributex-cloud-network.pages.dev"  # Optional
)
```

### Run Function
```python
result = dx.run(
    func,                    # Function to run
    args=(),                 # Positional arguments
    kwargs={},               # Keyword arguments
    workers=1,               # Number of parallel workers
    cpuPerWorker=2,          # CPU cores per worker
    ramPerWorker=2048,       # RAM in MB per worker
    gpu=False,               # Require GPU
    cuda=False,              # Require CUDA
    timeout=3600,            # Timeout in seconds
    wait=True                # Wait for completion
)
```

### Run Script
```python
result = dx.run_script(
    'script.py',             # Script path
    runtime='auto',          # Auto-detect or specify
    workers=1,
    cpuPerWorker=2,
    ramPerWorker=2048,
    gpu=False,
    cuda=False,
    inputFiles=[],           # Files to upload
    outputFiles=[],          # Files to collect
    env={},                  # Environment variables
    timeout=3600,
    wait=True
)
```

### Run Docker
```python
result = dx.run_docker(
    'image:tag',             # Docker image
    command=None,            # Command to run
    workers=1,
    cpuPerWorker=2,
    ramPerWorker=2048,
    gpu=False,
    volumes={},              # Volume mappings
    env={},                  # Environment variables
    ports={},                # Port mappings
    timeout=3600,
    wait=True
)
```

### Task Management
```python
# Get task status
task = dx.get_task('task-id')
print(task.status, task.progress)

# Get result
result = dx.get_result('task-id')

# Network statistics
stats = dx.network_stats()
print(f"Available: {stats.availableCpuCores} cores")
```

---

## 🔒 Security

- ✅ All data encrypted in transit (HTTPS)
- ✅ Private execution environments
- ✅ Isolated Docker containers
- ✅ API key authentication (JWT)
- ✅ No data persistence on workers

### Store Your API Key Safely

**Environment Variable (Recommended):**
```bash
export DISTRIBUTEX_API_KEY="dx_your_key"
```

```python
# Automatically uses env var
dx = DistributeX()
```

**Config File:**
```python
# ~/.distributex/config.json
{
  "api_key": "dx_your_key"
}
```

---

## 💰 Pricing

Pay only for what you use:

- **CPU:** $0.10 per core-hour
- **RAM:** $0.02 per GB-hour
- **GPU:** $0.50 per GPU-hour
- **Storage:** $0.01 per GB-hour

**Example:** Running a 4-core, 8GB RAM task for 1 hour:
- CPU: 4 cores × $0.10 = $0.40
- RAM: 8 GB × $0.02 = $0.16
- **Total: $0.56/hour**

---

## 📈 Dashboard

Monitor your usage at:
**[distributex-cloud-network.pages.dev/dashboard](https://distributex-cloud-network.pages.dev/dashboard)**

- View active tasks
- Check resource usage
- Monitor spending
- Download results
- Manage API keys

---

## 🆘 Troubleshooting

### "Authentication required"
```bash
# Check API key
echo $DISTRIBUTEX_API_KEY

# Test connection
python -c "from distributex import DistributeX; dx = DistributeX(); print(dx.network_stats())"
```

### "No workers available"
The network may be at capacity. Your task will queue and execute when workers become available.

### Task timeout
Increase timeout for long-running tasks:
```python
dx.run_script('long_task.py', timeout=86400)  # 24 hours
```

### View logs
```python
task = dx.get_task('task-id')
print(task.errorMessage)
```

---

---

**Built with ❤️ by the DistributeX Team**
