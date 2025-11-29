# DistributeX CLI & SDK

**One command. Two modes. Infinite possibilities.**

Share your computing resources OR run your code on a global pool of CPU, RAM, GPU, and Storage.

---

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

### Mode 2: Developer (Use Resources)

After installing, get your API key at:
```
https://distributex-cloud-network.pages.dev/api-docs
```

#### Python SDK

```bash
pip install distributex
```

```python
from distributex import DistributeX

dx = DistributeX(api_key="your_api_key")

# Run any Python function
def train_model(data, epochs=10):
    # Your ML training code
    return model

result = dx.run(train_model, args=(data,), gpu=True, workers=4)
```

#### JavaScript/Node.js SDK

```bash
npm install distributex
```

```javascript
const DistributeX = require('distributex');

const dx = new DistributeX('your_api_key');

// Run any script
const result = await dx.runScript('process.js', {
  workers: 2,
  cpuPerWorker: 4,
  ramPerWorker: 8192
});
```

#### Docker Execution

```python
# Python
dx.runDocker('tensorflow/tensorflow:latest-gpu', 
  command='python train.py',
  gpu=True
)
```

```javascript
// JavaScript
dx.runDocker('python:3.11', {
  command: 'python script.py',
  cpuPerWorker: 4
})
```

---

## 📦 What's Included

### For Contributors

```
public/
├── install.sh          # One-command installer
├── uninstall.sh        # Clean uninstaller
└── manage.sh           # Management commands
```

**Management:**
```bash
# Check status
~/.distributex/manage.sh status

# View logs
~/.distributex/manage.sh logs

# Restart worker
~/.distributex/manage.sh restart

# Stop temporarily
~/.distributex/manage.sh stop

# Uninstall
~/.distributex/manage.sh uninstall
```

### For Developers

#### Python SDK
```
python/distributex/
├── __init__.py         # Package init
├── client.py           # Main SDK
├── examples.py         # Usage examples
└── setup.py            # Package setup
```

#### JavaScript SDK
```
javascript/distributex/
├── src/
│   └── index.js        # Main SDK
├── examples.js         # Usage examples
└── package.json        # NPM config
```

#### Docker Worker
```
docker/
├── Dockerfile          # Worker image
└── worker-agent.js     # Agent script
```

---

## 💻 Developer Guide

### Installation

**Python:**
```bash
pip install distributex
```

**JavaScript:**
```bash
npm install distributex
```

**From source:**
```bash
# Python
cd python/distributex
pip install -e .

# JavaScript
cd javascript/distributex
npm install
npm link
```

### Basic Usage

#### Python

```python
from distributex import DistributeX

# Initialize
dx = DistributeX(api_key="your_api_key")

# Example 1: Run Python function
def process_data(data):
    # Your processing logic
    return result

result = dx.run(process_data, args=(my_data,), workers=4)

# Example 2: Run Python script
result = dx.run_script('analyze.py', 
    runtime='python',
    gpu=True,
    inputFiles=['data.csv'],
    outputFiles=['results.json']
)

# Example 3: Run Docker container
result = dx.run_docker('tensorflow/tensorflow:latest-gpu',
    command='python train.py',
    gpu=True,
    ramPerWorker=16384
)
```

#### JavaScript

```javascript
const DistributeX = require('distributex');

// Initialize
const dx = new DistributeX('your_api_key');

// Example 1: Run JavaScript function
const result = await dx.run((n) => {
  let sum = 0;
  for (let i = 0; i < n; i++) sum += i;
  return sum;
}, { args: [1000000], cpuPerWorker: 4 });

// Example 2: Run Node.js script
const result = await dx.runScript('process.js', {
  workers: 2,
  ramPerWorker: 4096
});

// Example 3: Run Docker container
const result = await dx.runDocker('python:3.11', {
  command: 'python script.py',
  cpuPerWorker: 4
});
```

### Advanced Examples

#### Video Processing
```python
dx.run_script('process_video.py',
    workers=8,
    cpuPerWorker=4,
    gpu=True,
    inputFiles=['video.mp4'],
    outputFiles=['output/'],
    timeout=7200
)
```

#### ML Training
```python
dx.run_script('train.py',
    workers=1,
    cpuPerWorker=16,
    ramPerWorker=32768,
    gpu=True,
    cuda=True,
    timeout=86400  # 24 hours
)
```

#### Parallel Data Processing
```python
# Process multiple files in parallel
files = ['data1.csv', 'data2.csv', 'data3.csv']
tasks = [
    dx.run_script('process.py', 
        inputFiles=[f], 
        wait=False
    ) for f in files
]

# Wait for all
results = [dx.get_result(t.id) for t in tasks]
```

---

## 🔧 Configuration

### Environment Variables

```bash
# API Key (required for developers)
export DISTRIBUTEX_API_KEY="your_api_key"

# API URL (optional, defaults to production)
export DISTRIBUTEX_API_URL="https://distributex-cloud-network.pages.dev"
```

### Resource Limits

Contributors can customize resource sharing:

```bash
# Edit ~/.distributex/config.json
{
  "cpuSharePercent": 40,
  "ramSharePercent": 30,
  "gpuSharePercent": 50,
  "storageSharePercent": 20
}

# Restart to apply
~/.distributex/manage.sh restart
```

---

## 🌐 API Reference

### Python SDK

```python
class DistributeX:
    def __init__(api_key, base_url=...):
        """Initialize client"""
    
    def run(func, args=(), kwargs={}, workers=1, gpu=False, ...):
        """Run Python function"""
    
    def run_script(script_path, runtime='auto', workers=1, ...):
        """Run any script file"""
    
    def run_docker(image, command=None, gpu=False, ...):
        """Run Docker container"""
    
    def get_task(task_id):
        """Get task status"""
    
    def network_stats():
        """Get network statistics"""
```

### JavaScript SDK

```javascript
class DistributeX {
    constructor(apiKey, baseUrl)
    
    async run(func, options)
    
    async runScript(scriptPath, options)
    
    async runDocker(image, options)
    
    async getTask(taskId)
    
    async networkStats()
}
```

### Task Options

```javascript
{
  workers: 1,              // Number of parallel workers
  cpuPerWorker: 2,         // CPU cores per worker
  ramPerWorker: 2048,      // RAM in MB per worker
  gpu: false,              // Require GPU
  cuda: false,             // Require CUDA
  inputFiles: [],          // Input files to upload
  outputFiles: [],         // Output paths to collect
  env: {},                 // Environment variables
  timeout: 3600,           // Timeout in seconds
  wait: true               // Wait for completion
}
```

---

## 🎯 Use Cases

### AI/ML
- Model training
- Inference/prediction
- Hyperparameter tuning
- Data preprocessing

### Video Processing
- Transcoding
- Rendering
- Effects processing
- Format conversion

### Data Analysis
- Large dataset processing
- Statistical analysis
- Report generation
- ETL pipelines

### Scientific Computing
- Simulations
- Complex calculations
- Physics computations
- Numerical analysis

### General Computing
- Batch processing
- Parallel algorithms
- Custom computations
- Any distributed task

---

## 📊 Network Statistics

View live network stats at:
```
https://distributex-cloud-network.pages.dev/stats
```

Or programmatically:

```python
# Python
stats = dx.network_stats()
print(f"Active Workers: {stats['activeWorkers']}")
print(f"Total CPU Cores: {stats['totalCpuCores']}")
```

```javascript
// JavaScript
const stats = await dx.networkStats();
console.log(`Active Workers: ${stats.activeWorkers}`);
console.log(`Total CPU Cores: ${stats.totalCpuCores}`);
```

---

## 🔐 Security

### For Contributors
- ✅ Docker isolated execution
- ✅ No file system access
- ✅ Encrypted communication
- ✅ Open source code
- ✅ Auto-throttling

### For Developers
- ✅ Data encryption
- ✅ Private execution
- ✅ Secure JWT authentication
- ✅ HTTPS only

---

## 🐛 Troubleshooting

### Worker not starting

```bash
# Check status
~/.distributex/manage.sh status

# View logs
~/.distributex/manage.sh logs

# Restart
~/.distributex/manage.sh restart
```

### Connection issues

```bash
# Test connection
curl https://distributex-cloud-network.pages.dev/api/health

# Verify API key
distributex config --verify
```

### High resource usage

```bash
# Reduce limits
distributex config --cpu-limit 30 --ram-limit 20

# Enable aggressive throttling
distributex config --throttle-mode aggressive
```

### SDK errors

```python
# Python - Enable debug logging
import logging
logging.basicConfig(level=logging.DEBUG)
```

```javascript
// JavaScript - Check for errors
try {
  await dx.run(func);
} catch (error) {
  console.error('Error:', error.message);
}
```

---
---

**Made with ❤️ by the DistributeX Team**
