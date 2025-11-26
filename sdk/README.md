# DistributeX Developer Quick Start

## 🚀 Run ANY Script on the Distributed Network

DistributeX now lets you run **any script or Docker container** on the global computing pool. No infrastructure setup needed!

---

## Installation

### NPM Package (Recommended)

```bash
npm install -g distributex-cli
```

Or use directly with npx:

```bash
npx distributex-cli login
```

### Manual Installation

```bash
# Clone the SDK
git clone https://github.com/distributex/distributex-sdk
cd distributex-sdk
npm install
npm link

# Now you can use 'distributex' command globally
```

---

## Quick Start

### 1. Login

```bash
distributex login
# Enter your email and password
# API key will be saved to ~/.distributex/config.json
```

Or set API key manually:

```bash
export DISTRIBUTEX_API_KEY="your_api_key_here"
```

### 2. Run Your First Script

```bash
# Run a Python script
distributex run train.py --gpu

# Run with specific resources
distributex run process.py --workers 4 --cpu 8 --ram 16384

# Run a Node.js script
distributex run analyze.js --input ./data --output ./results
```

### 3. Check Status

```bash
# Get task status
distributex status task_abc123

# Download results
distributex results task_abc123 ./my-results
```

---

## 📚 Examples

### Python ML Training

```bash
# Run TensorFlow training with GPU
distributex run train.py \
  --gpu \
  --cuda \
  --workers 2 \
  --cpu 8 \
  --ram 16384 \
  --input ./dataset \
  --output ./models \
  --env EPOCHS=100
```

**train.py:**
```python
import tensorflow as tf
import os

epochs = int(os.getenv('EPOCHS', 10))

# Your training code here
model = tf.keras.models.Sequential([...])
model.compile(...)
model.fit(train_data, epochs=epochs)
model.save('/results/model.h5')
```

### Node.js Data Processing

```bash
# Process large dataset in parallel
distributex run process.js \
  --workers 10 \
  --input ./data/large_dataset.csv \
  --output ./processed
```

**process.js:**
```javascript
const fs = require('fs');
const csv = require('csv-parser');

// Your processing code
fs.createReadStream('/input/large_dataset.csv')
  .pipe(csv())
  .on('data', (row) => {
    // Process each row
  })
  .on('end', () => {
    fs.writeFileSync('/output/results.json', JSON.stringify(results));
  });
```

### Video Processing

```bash
# Transcode video with FFmpeg
distributex run "ffmpeg -i input.mp4 -c:v h264 output.mp4" \
  --workers 1 \
  --gpu \
  --input ./videos/input.mp4 \
  --output ./videos/output.mp4
```

### Scientific Simulation

```bash
# Run MATLAB/Octave simulation
distributex run simulation.m \
  --runtime octave \
  --workers 20 \
  --cpu 4 \
  --ram 8192 \
  --timeout 7200
```

---

## 🐳 Docker Execution

Run **any Docker container** on the network!

### Basic Docker Run

```bash
# Run Python container
distributex docker run python:3.11 \
  --command "python -c 'print(2+2)'"

# Run with GPU
distributex docker run tensorflow/tensorflow:latest-gpu \
  --command "python train.py" \
  --gpu \
  --volume ./data:/data
```

### Complex Docker Example

```bash
# Run PyTorch training
distributex docker run pytorch/pytorch:2.0.0-cuda11.7-cudnn8-runtime \
  --command "python /app/train.py --epochs 100" \
  --gpu \
  --workers 2 \
  --volume ./code:/app \
  --volume ./data:/data \
  --volume ./models:/models \
  --env CUDA_VISIBLE_DEVICES=0 \
  --env WANDB_API_KEY=$WANDB_KEY
```

### Custom Docker Image

```bash
# Build and run your own image
docker build -t myusername/myapp:latest .
docker push myusername/myapp:latest

distributex docker run myusername/myapp:latest \
  --command "npm start" \
  --workers 5 \
  --env NODE_ENV=production
```

---

## 🎯 Use Cases

### 1. Machine Learning Training

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

### 2. Video Rendering Pipeline

```bash
# Render multiple video segments in parallel
distributex run render_pipeline.py \
  --workers 10 \
  --gpu \
  --input ./scenes \
  --output ./rendered \
  --timeout 14400
```

### 3. Data Analysis

```bash
# Process massive CSV dataset
distributex run analyze.py \
  --workers 20 \
  --cpu 4 \
  --ram 8192 \
  --input ./data/billion_rows.csv \
  --output ./analysis
```

### 4. Scientific Computing

```bash
# Run molecular dynamics simulation
distributex docker run gromacs/gromacs:latest \
  --command "gmx mdrun -s simulation.tpr" \
  --gpu \
  --workers 4 \
  --volume ./simulations:/workspace
```

### 5. Blockchain Processing

```bash
# Process blockchain data
distributex run process_blocks.js \
  --workers 50 \
  --cpu 2 \
  --ram 4096 \
  --env START_BLOCK=0 \
  --env END_BLOCK=1000000
```

---

## 📖 API Reference

### CLI Commands

```bash
# Run script
distributex run <script|command> [options]

# Run Docker
distributex docker run <image> [options]

# Check status
distributex status <task-id>

# Get results
distributex results <task-id> [output-dir]

# View workers
distributex workers

# Login
distributex login
```

### Run Options

```
--workers <n>          Number of parallel workers (default: 1)
--cpu <cores>          CPU cores per worker (default: 2)
--ram <mb>             RAM per worker in MB (default: 2048)
--gpu                  Require GPU
--cuda                 Require CUDA-capable GPU
--input <path>         Upload input file/directory
--output <path>        Expected output file/directory
--env KEY=VALUE        Set environment variable
--timeout <seconds>    Max execution time (default: 3600)
--runtime <lang>       Runtime (auto|python|node|ruby|go|rust|java|cpp|bash)
```

### Docker Options

```
--command, -c          Command to run in container
--volume, -v           Mount volume (host:container)
--env, -e              Environment variable
--port, -p             Port mapping (host:container)
--gpu                  Request GPU access
```

---

## 🔧 Advanced Usage

### Programmatic API (JavaScript/Node.js)

```javascript
const DistributeX = require('distributex-cli');

const client = new DistributeX('your-api-key');

async function runTraining() {
  // Submit task
  const task = await client.runScript({
    script: './train.py',
    runtime: 'python',
    workers: 4,
    gpu: true,
    cuda: true,
    cpuPerWorker: 8,
    ramPerWorker: 16384,
    inputFiles: ['./dataset'],
    outputFiles: ['./models'],
    env: {
      EPOCHS: '100',
      BATCH_SIZE: '32'
    }
  });

  console.log('Task submitted:', task.id);

  // Wait for completion with progress updates
  const result = await client.waitForTask(task.id, (status) => {
    console.log(`Progress: ${status.progressPercent}%`);
  });

  // Download results
  await client.downloadResults(task.id, './my-results');
  
  console.log('Training complete!');
}

runTraining().catch(console.error);
```

### Python SDK (Coming Soon)

```python
from distributex import Client

client = Client('your-api-key')

# Submit task
task = client.run_script(
    script='train.py',
    workers=4,
    gpu=True,
    cuda=True,
    input_files=['./dataset'],
    output_files=['./models']
)

# Wait for completion
result = task.wait()
result.download_results('./my-results')
```

### REST API

```bash
# Submit script execution
curl -X POST https://distributex-cloud-network.pages.dev/api/tasks/execute \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Train ML Model",
    "taskType": "script_execution",
    "runtime": "python",
    "codeUrl": "https://storage.distributex.io/uploads/user123/code.tar.gz",
    "workers": 4,
    "cpuPerWorker": 8,
    "ramPerWorker": 16384,
    "gpuRequired": true,
    "requiresCuda": true
  }'

# Check status
curl https://distributex-cloud-network.pages.dev/api/tasks/task_abc123 \
  -H "Authorization: Bearer YOUR_API_KEY"
```

---

## 💡 Best Practices

### 1. Optimize for Parallel Execution

```python
# Good: Split work into independent chunks
for i in range(workers):
    process_chunk(i, total_chunks=workers)

# Bad: Sequential processing
for item in all_items:
    process_item(item)  # Can't parallelize
```

### 2. Handle Output Properly

```python
# Always write to /output directory
import os

output_dir = '/output'
os.makedirs(output_dir, exist_ok=True)

# Save results
with open(f'{output_dir}/results.json', 'w') as f:
    json.dump(results, f)
```

### 3. Use Environment Variables

```bash
# Pass configuration via env vars
distributex run train.py \
  --env LEARNING_RATE=0.001 \
  --env BATCH_SIZE=32 \
  --env MODEL_TYPE=resnet50
```

### 4. Error Handling

```python
import sys
import traceback

try:
    # Your code here
    result = train_model()
    save_results(result)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    traceback.print_exc()
    sys.exit(1)  # Exit with error code
```

### 5. Progress Reporting

```python
import json

def report_progress(percent):
    # Write to special file that worker monitors
    with open('/tmp/progress.json', 'w') as f:
        json.dump({'progress': percent}, f)

for epoch in range(total_epochs):
    train_epoch()
    progress = (epoch + 1) / total_epochs * 100
    report_progress(progress)
```

---

## 🐛 Troubleshooting

### Task Stuck in "Pending"

```bash
# Check available workers
distributex workers

# Check if workers meet requirements
# You may need to reduce resource requirements
distributex run script.py --cpu 2 --ram 2048  # Lower requirements
```

### "No GPU Available"

```bash
# Check GPU workers
distributex workers | grep "GPU Devices"

# Use --gpu only if GPUs are available
# Or wait for GPU workers to come online
```

### Large Files Not Uploading

```bash
# Files >100MB may be slow
# Consider splitting into smaller chunks
split -b 50M large_file.dat chunk_

# Upload chunks separately
for chunk in chunk_*; do
  distributex run process.py --input $chunk &
done
```

### Results Not Downloaded

```bash
# Make sure outputs are written to correct paths
# In your script:
mkdir -p /output
echo "result" > /output/result.txt

# Not: ~/results/result.txt (wrong path)
```

---

## 📊 Monitoring & Debugging

### Check Task Logs

```bash
# Get detailed task status
distributex status task_abc123

# The response includes:
# - Current status
# - Progress percentage
# - Worker ID
# - Error messages if failed
# - Execution time
```

### View Worker Stats

```bash
distributex workers

# Shows:
# - Total and active workers
# - Available CPU cores
# - Available RAM
# - Available GPUs
# - Docker-enabled workers
```

### Debug Failed Tasks

```bash
# Check task error message
distributex status task_abc123 | grep error

# Common errors:
# - "Worker disconnected" - Worker went offline during execution
# - "Timeout exceeded" - Task took longer than --timeout
# - "Out of memory" - Increase --ram value
# - "Exit code 1" - Your script had an error
```

---

## 🚀 Next Steps

1. **Install the CLI**: `npm install -g distributex-cli`
2. **Login**: `distributex login`
3. **Run your first script**: `distributex run script.py --gpu`
4. **Join the community**: [Discord](https://discord.gg/distributex)
5. **Share your experience**: Tweet with #DistributeX

---

## 📝 Package.json for SDK

```json
{
  "name": "distributex-cli",
  "version": "1.0.0",
  "description": "Run any script on the DistributeX distributed computing network",
  "main": "index.js",
  "bin": {
    "distributex": "./index.js"
  },
  "scripts": {
    "test": "jest"
  },
  "keywords": [
    "distributed-computing",
    "cloud",
    "parallel",
    "docker",
    "gpu",
    "ml"
  ],
  "author": "DistributeX Team",
  "license": "MIT",
  "dependencies": {
    "archiver": "^6.0.0",
    "tar": "^6.2.0"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/distributex/distributex-sdk"
  }
}
```

---

**Happy Computing! 🎉**

For questions or support: support@distributex.io
