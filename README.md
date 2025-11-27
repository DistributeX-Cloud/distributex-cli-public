# DistributeX Cloud Network 🚀

> **Free, open-source distributed computing platform**  
> Share your unused computing resources or run your code on a global pool of CPU, RAM, GPU, and Storage.

[![Contributors](https://img.shields.io/badge/contributors-2800%2B-blue)]()
[![Uptime](https://img.shields.io/badge/uptime-99.9%25-green)]()
[![Total Resources](https://img.shields.io/badge/pool-156TB-purple)]()

---

## 🎯 Two Ways to Use DistributeX

### 1️⃣ **For Contributors** (Share Your Resources)
Get your idle computer working for you! Contribute CPU, RAM, GPU, or storage and support developers worldwide.

### 2️⃣ **For Developers** (Use the Resource Pool)
Run your scripts, train ML models, process data, or render videos using pooled resources from thousands of devices.

---

## 🤝 For Contributors (Share Resources)

### Quick Start - One Command Install

```bash
curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
```

**That's it!** The installer will:
- ✅ Auto-detect your system (CPU, RAM, GPU, Storage)
- ✅ Register your device securely
- ✅ Start sharing resources intelligently
- ✅ Set up auto-start on boot

### What Gets Shared?

The agent automatically shares **only what's safe**:

| Resource | Default Share | Your System Impact |
|----------|---------------|-------------------|
| **CPU** | 30-50% of cores | Zero slowdown with smart throttling |
| **RAM** | 20-30% of available | Only unused memory |
| **GPU** | 50% when idle | Uses GPU only when you're not |
| **Storage** | 10-20% of free space | Never touches your files |

### Example: What You Contribute

```
Your Desktop PC:
├── CPU: 8 cores → Shares 3-4 cores (40%)
├── RAM: 16GB → Shares 4-5GB (30%)
├── GPU: NVIDIA RTX 3060 → Shares 50% when idle
└── Storage: 512GB free → Shares 50GB (10%)

Result: Zero impact on your daily use!
```

### Management Commands

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

### System Requirements

**Minimum:**
- 2 CPU cores
- 2GB RAM
- 10GB free disk space
- 1 Mbps internet

**Recommended:**
- 4+ CPU cores
- 8GB+ RAM
- 50GB+ free disk space
- GPU (optional, for GPU tasks)

---

## 👨‍💻 For Developers (Use the Resource Pool)

### Quick Start - 3 Steps

#### Step 1: Create Free Account

Visit [https://distributex-cloud-network.pages.dev](https://distributex-cloud-network.pages.dev) and sign up.

#### Step 2: Install the SDK

```bash
npm install -g @distributex/cli
```

Or use directly with npx:

```bash
npx @distributex/cli login
```

#### Step 3: Login

```bash
distributex login
# Enter your email and password
# ✓ API key saved automatically
```

---

## 🎮 Running Your Scripts - Super Easy!

### Example 1: Run a Python Script

**Your script (`train.py`):**
```python
import time
print("Training model...")
for i in range(10):
    print(f"Epoch {i+1}/10")
    time.sleep(1)
print("Training complete!")
```

**Run it on the network:**
```bash
distributex run train.py
```

**With GPU:**
```bash
distributex run train.py --gpu
```

**With custom resources:**
```bash
distributex run train.py \
  --workers 4 \
  --cpu 8 \
  --ram 16384 \
  --gpu
```

### Example 2: Machine Learning Training

```bash
# Run PyTorch training with GPU and CUDA
distributex run train_model.py \
  --gpu \
  --cuda \
  --workers 2 \
  --cpu 8 \
  --ram 16384 \
  --input ./dataset \
  --output ./models \
  --env EPOCHS=100 \
  --env BATCH_SIZE=32
```

### Example 3: Data Processing

```bash
# Process large CSV files in parallel
distributex run process_data.py \
  --workers 10 \
  --cpu 4 \
  --ram 8192 \
  --input ./data/large_dataset.csv \
  --output ./processed
```

### Example 4: Video Processing

```bash
# Transcode video with FFmpeg
distributex run "ffmpeg -i input.mp4 -c:v h264 output.mp4" \
  --gpu \
  --input ./videos/input.mp4 \
  --output ./videos/output.mp4
```

### Example 5: Run Any Command

```bash
# Run shell commands
distributex run "pip install pandas && python analyze.py"

# Node.js script
distributex run analyze.js --input ./data

# Ruby script
distributex run process.rb --workers 5
```

---

## 🐳 Docker Execution

Run **any Docker container** on the network!

### Basic Docker Example

```bash
distributex docker run python:3.11 \
  --command "python -c 'import torch; print(torch.cuda.is_available())'"
```

### Advanced Docker Example

```bash
# Run TensorFlow training container
distributex docker run tensorflow/tensorflow:latest-gpu \
  --command "python /app/train.py --epochs 100" \
  --gpu \
  --workers 2 \
  --volume ./code:/app \
  --volume ./data:/data \
  --volume ./models:/models \
  --env CUDA_VISIBLE_DEVICES=0
```

### Custom Docker Images

```bash
# Use your own image
distributex docker run myusername/my-ml-app:latest \
  --command "python train.py" \
  --gpu \
  --workers 4
```

---

## 📊 Monitoring Your Tasks

### Check Task Status

```bash
# View status
distributex status task_abc123

# Live tail of task execution
distributex status task_abc123 --follow
```

### Download Results

```bash
# Download to current directory
distributex results task_abc123

# Download to specific directory
distributex results task_abc123 ./my-results
```

### View Network Stats

```bash
distributex network

# Output:
# 🌍 Network Statistics
#    Total Workers: 2847
#    Active Workers: 1234
#    Total CPU Cores: 18562
#    Total RAM: 144 GB
#    GPU Devices: 456
#    Active Tasks: 89
```

---

## 🎯 Real-World Use Cases

### 1. **Machine Learning Training**

```bash
# Distributed hyperparameter search
for lr in 0.001 0.01 0.1; do
  distributex run train.py \
    --gpu \
    --env LEARNING_RATE=$lr \
    --env EXPERIMENT_NAME="lr_${lr}" &
done
wait
```

### 2. **Video Rendering Pipeline**

```bash
# Render video segments in parallel
distributex run render_pipeline.py \
  --workers 10 \
  --gpu \
  --input ./scenes \
  --output ./rendered \
  --timeout 7200
```

### 3. **Big Data Analysis**

```bash
# Process massive dataset
distributex run analyze.py \
  --workers 20 \
  --cpu 4 \
  --ram 8192 \
  --input ./data/billion_rows.csv \
  --output ./analysis
```

### 4. **Scientific Computing**

```bash
# Run molecular dynamics simulation
distributex docker run gromacs/gromacs:latest \
  --command "gmx mdrun -s simulation.tpr" \
  --gpu \
  --workers 4 \
  --volume ./simulations:/workspace
```

---

## 📖 Available Options

### Script Execution Options

```bash
distributex run <script> [options]

Options:
  --workers <n>         Number of parallel workers (default: 1)
  --cpu <cores>         CPU cores per worker (default: 2)
  --ram <mb>            RAM per worker in MB (default: 2048)
  --gpu                 Require GPU
  --cuda                Require CUDA-capable GPU
  --input <path>        Upload input file/directory
  --output <path>       Expected output file/directory
  --env KEY=VALUE       Set environment variable
  --timeout <seconds>   Max execution time (default: 3600)
  --runtime <type>      Force runtime (python|node|ruby|go|rust|java|cpp|bash)
```

### Docker Options

```bash
distributex docker run <image> [options]

Options:
  --command, -c         Command to run in container
  --workers <n>         Number of parallel workers
  --gpu                 Request GPU access
  --volume, -v          Mount volume (host:container)
  --env, -e             Environment variable
  --port, -p            Port mapping (host:container)
  --timeout <seconds>   Max execution time
```

---

## 💡 Pro Tips

### 1. **Optimize for Parallel Execution**

**❌ Bad - Sequential:**
```python
for item in all_items:
    process_item(item)  # Can't parallelize
```

**✅ Good - Parallel:**
```python
# Split work into chunks
chunk_size = len(items) // num_workers
for i in range(num_workers):
    process_chunk(items[i*chunk_size:(i+1)*chunk_size])
```

### 2. **Handle Output Properly**

```python
import os

# Always write to /output directory
output_dir = '/output'
os.makedirs(output_dir, exist_ok=True)

# Save results
with open(f'{output_dir}/results.json', 'w') as f:
    json.dump(results, f)
```

### 3. **Use Environment Variables**

```bash
distributex run train.py \
  --env LEARNING_RATE=0.001 \
  --env BATCH_SIZE=32 \
  --env MODEL_TYPE=resnet50
```

In your script:
```python
import os
learning_rate = float(os.getenv('LEARNING_RATE', 0.001))
batch_size = int(os.getenv('BATCH_SIZE', 32))
```

### 4. **Error Handling**

```python
import sys
import traceback

try:
    result = train_model()
    save_results(result)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    traceback.print_exc()
    sys.exit(1)  # Exit with error code
```

---

## 🐛 Troubleshooting

### Task Stuck in "Pending"?

```bash
# Check available workers
distributex network

# Reduce resource requirements
distributex run script.py --cpu 2 --ram 2048
```

### "No GPU Available"?

```bash
# Check if GPUs are in the pool
distributex network | grep "GPU Devices"

# Wait for GPU workers or run without GPU
distributex run script.py  # Will run on CPU
```

### Large Files Not Uploading?

```bash
# Split large files (>100MB)
split -b 50M large_file.dat chunk_

# Upload chunks separately
for chunk in chunk_*; do
  distributex run process.py --input $chunk &
done
```

### Results Not Appearing?

Make sure you're writing to the correct path:

```python
# ✅ Correct
with open('/output/result.txt', 'w') as f:
    f.write(result)

# ❌ Wrong - won't be captured
with open('~/results/result.txt', 'w') as f:
    f.write(result)
```

---

## 📚 API Documentation

### Quick API Example (JavaScript)

```javascript
const DistributeX = require('@distributex/cli');

const client = new DistributeX('your-api-key');

async function runTask() {
  // Submit task
  const task = await client.runScript({
    script: './train.py',
    workers: 4,
    gpu: true,
    env: { EPOCHS: '100' }
  });

  console.log('Task submitted:', task.id);

  // Wait for completion
  const result = await client.waitForTask(task.id);
  console.log('Complete!', result);

  // Download results
  await client.downloadResults(task.id);
}
```

---

## 💰 Pricing

### **It's FREE!** 🎉

- ✅ No credit card required
- ✅ No usage limits
- ✅ No hidden fees
- ✅ Unlimited tasks
- ✅ Full access to all features

DistributeX is powered by contributors who share their resources voluntarily.

---

## 🔐 Security & Privacy

### For Contributors
- ✅ **Docker isolated** - All tasks run in isolated containers
- ✅ **No file access** - Tasks can't access your personal files
- ✅ **Encrypted communication** - All data is encrypted in transit
- ✅ **Open source** - Audit our code anytime
- ✅ **Auto-throttling** - Automatically reduces load if you need resources

### For Developers
- ✅ **Data encryption** - Your code and data are encrypted
- ✅ **Private execution** - Workers can't see your code or data
- ✅ **Secure authentication** - JWT-based API access
- ✅ **HTTPS only** - All communication encrypted

---
[Get Started Now →](https://distributex-cloud-network.pages.dev/auth)

</div>
