# DistributeX Developer Guide

## 🎯 Getting Started as a Developer

After installing DistributeX, you have access to a global pool of computing resources. Here's how to use them.

---

## 📋 Step 1: Get Your API Key

1. Visit: https://distributex-cloud-network.pages.dev/auth
2. Sign up or log in
3. Copy your API key from the dashboard

---

## 🐍 Step 2: Install SDK (Python)

```bash
pip install distributex-cloud
```

### Basic Python Example

```python
from distributex import DistributeX

# Initialize with your API key
dx = DistributeX(api_key="your_api_key_here")

# Example 1: Run a Python function
def calculate_fibonacci(n):
    if n <= 1:
        return n
    a, b = 0, 1
    for _ in range(2, n + 1):
        a, b = b, a + b
    return b

result = dx.run(calculate_fibonacci, args=(100,), cpuPerWorker=2)
print(f"Result: {result}")

# Example 2: Run a Python script
result = dx.run_script('my_script.py', 
    runtime='python',
    workers=2,
    cpuPerWorker=4,
    ramPerWorker=8192
)
print("Script complete!")

# Example 3: Run with GPU
result = dx.run_script('train_model.py',
    runtime='python',
    gpu=True,
    cuda=True,
    ramPerWorker=16384
)
```

---

## 📦 Step 3: Install SDK (JavaScript/Node.js)

```bash
npm install distributex  # or npm install -g distributex
```

### Basic JavaScript Example

```javascript
const DistributeX = require('distributex');

// Initialize with your API key
const dx = new DistributeX('your_api_key_here');

// Example 1: Run a JavaScript function
const result = await dx.run((n) => {
  let sum = 0;
  for (let i = 0; i < n; i++) {
    sum += i;
  }
  return sum;
}, { args: [1000000], cpuPerWorker: 2 });

console.log('Result:', result);

// Example 2: Run a Node.js script
const result = await dx.runScript('process.js', {
  workers: 2,
  cpuPerWorker: 4,
  ramPerWorker: 4096
});

console.log('Script complete!');

// Example 3: Run Docker container
const result = await dx.runDocker('python:3.11', {
  command: 'python -c "print(2+2)"',
  cpuPerWorker: 2
});

console.log('Docker result:', result);
```

---

## 🚀 Real-World Examples

### Video Processing

```python
from distributex import DistributeX

dx = DistributeX(api_key="your_api_key")

# Process 4K video with GPU acceleration
result = dx.run_script('transcode_video.py',
    runtime='python',
    workers=4,
    cpuPerWorker=4,
    ramPerWorker=8192,
    gpu=True,
    inputFiles=['video.mp4'],
    outputFiles=['output/'],
    timeout=7200  # 2 hours
)

print("Video processing complete!")
```

### Machine Learning Training

```python
# Train ML model on distributed GPUs
result = dx.run_script('train_model.py',
    runtime='python',
    workers=1,
    cpuPerWorker=16,
    ramPerWorker=32768,
    gpu=True,
    cuda=True,
    inputFiles=['dataset.zip'],
    outputFiles=['models/', 'checkpoints/'],
    timeout=86400  # 24 hours
)
```

### Data Analysis

```python
# Process large CSV files in parallel
files = ['data1.csv', 'data2.csv', 'data3.csv', 'data4.csv']

# Submit all tasks at once
tasks = []
for file in files:
    task = dx.run_script('analyze.py',
        runtime='python',
        inputFiles=[file],
        outputFiles=['results/'],
        wait=False  # Don't wait, submit immediately
    )
    tasks.append(task)

print(f"Submitted {len(tasks)} parallel tasks")

# Wait for all to complete
results = [dx.get_result(t.id) for t in tasks]
print("All analysis complete!")
```

### Docker Workflow

```python
# Run TensorFlow training in Docker
result = dx.run_docker('tensorflow/tensorflow:latest-gpu',
    command='python /app/train.py',
    gpu=True,
    cpuPerWorker=8,
    ramPerWorker=16384,
    volumes={
        '/local/data': '/app/data',
        '/local/checkpoints': '/app/checkpoints'
    },
    environment={
        'BATCH_SIZE': '64',
        'LEARNING_RATE': '0.001'
    }
)
```

---

## 🎛️ Configuration Options

### Resource Requirements

```python
dx.run_script('script.py',
    # Computing resources
    workers=2,              # Number of parallel workers
    cpuPerWorker=4,         # CPU cores per worker
    ramPerWorker=8192,      # RAM in MB per worker
    
    # GPU requirements
    gpu=True,               # Require GPU
    cuda=True,              # Require CUDA support
    
    # Storage
    storageRequired=50,     # GB of storage needed
    
    # Execution
    timeout=3600,           # Timeout in seconds
    priority=7              # Priority (1-10, higher = faster)
)
```

### File Handling

```python
# Upload input files
dx.run_script('process.py',
    inputFiles=[
        'data.csv',
        'config.json',
        'models/pretrained.pth'
    ],
    outputFiles=[
        'results/output.json',
        'results/metrics.csv',
        'models/trained.pth'
    ]
)
```

### Environment Variables

```python
dx.run_script('script.py',
    environment={
        'API_KEY': 'secret_key',
        'DEBUG': 'true',
        'BATCH_SIZE': '32'
    }
)
```

---

## 📊 Monitoring Tasks

### Check Task Status

```python
# Get task info
task = dx.get_task(task_id)

print(f"Status: {task.status}")
print(f"Progress: {task.progress}%")
print(f"Worker: {task.workerId}")
```

### Wait for Completion

```python
# Submit without waiting
task = dx.run_script('long_job.py', wait=False)

# Do other work...

# Wait for completion later
result = dx.wait_for_completion(task.id)
```

### Download Results

```python
# Download task results
result = dx.download_results(task_id, output_dir='./results')
```

---

## 🌐 Network Statistics

```python
# Get current network stats
stats = dx.network_stats()

print(f"Active Workers: {stats['activeWorkers']}")
print(f"Total CPU Cores: {stats['totalCpuCores']}")
print(f"Total RAM: {stats['totalRam'] / 1024} GB")
print(f"GPUs Available: {stats['totalGpus']}")
print(f"Active Tasks: {stats['activeTasks']}")
```

---

## ⚡ Performance Tips

### 1. Use Appropriate Worker Count

```python
# For CPU-bound tasks
dx.run_script('cpu_intensive.py', workers=8, cpuPerWorker=2)

# For memory-bound tasks
dx.run_script('memory_intensive.py', workers=2, ramPerWorker=32768)

# For GPU tasks
dx.run_script('gpu_task.py', workers=1, gpu=True)
```

### 2. Batch Similar Tasks

```python
# Instead of many small tasks...
# BAD: for i in range(100): dx.run_script(...)

# Batch them together
# GOOD: dx.run_script('batch_process.py', workers=10)
```

### 3. Set Appropriate Timeouts

```python
# Short tasks
dx.run_script('quick.py', timeout=300)  # 5 minutes

# Long training
dx.run_script('train.py', timeout=86400)  # 24 hours
```

### 4. Use Priority Wisely

```python
# Critical production task
dx.run_script('important.py', priority=9)

# Background batch job
dx.run_script('background.py', priority=3)
```

---

## 🔧 Advanced Usage

### Custom Docker Images

```python
# Use your own Docker image
dx.run_docker('myregistry/myimage:v1.0',
    command='python /app/custom_script.py',
    gpu=True
)
```

### Multi-Stage Workflows

```python
# Stage 1: Preprocess data
task1 = dx.run_script('preprocess.py', 
    inputFiles=['raw_data.csv'],
    outputFiles=['processed_data.csv']
)

# Stage 2: Train model (wait for stage 1)
task2 = dx.run_script('train.py',
    inputFiles=['processed_data.csv'],
    outputFiles=['model.pth'],
    gpu=True
)

# Stage 3: Evaluate
task3 = dx.run_script('evaluate.py',
    inputFiles=['model.pth', 'test_data.csv'],
    outputFiles=['results.json']
)
```

### Error Handling

```python
try:
    result = dx.run_script('script.py')
except Exception as e:
    print(f"Task failed: {e}")
    # Handle error...
```

---

## 🎓 Example Projects

### 1. Video Transcoding Service

```python
import os
from distributex import DistributeX

dx = DistributeX(api_key=os.getenv('DISTRIBUTEX_API_KEY'))

def transcode_video(input_file, output_format):
    """Transcode video using distributed workers"""
    result = dx.run_script('transcode.py',
        runtime='python',
        workers=4,
        gpu=True,
        inputFiles=[input_file],
        outputFiles=[f'output.{output_format}'],
        environment={
            'FORMAT': output_format,
            'QUALITY': 'high'
        },
        timeout=7200
    )
    return result

# Use it
result = transcode_video('video.mov', 'mp4')
print("Transcoding complete!")
```

### 2. Parallel Data Processing

```python
def process_dataset(files):
    """Process multiple data files in parallel"""
    tasks = []
    
    # Submit all tasks
    for file in files:
        task = dx.run_script('process.py',
            inputFiles=[file],
            outputFiles=[f'results/{file}.json'],
            wait=False
        )
        tasks.append(task)
    
    # Wait for completion
    results = []
    for task in tasks:
        result = dx.get_result(task.id)
        results.append(result)
    
    return results

# Process 100 files
files = [f'data_{i}.csv' for i in range(100)]
results = process_dataset(files)
```

### 3. ML Model Training Pipeline

```python
class MLTrainingPipeline:
    def __init__(self, api_key):
        self.dx = DistributeX(api_key=api_key)
    
    def train(self, config):
        """Complete ML training pipeline"""
        
        # 1. Preprocess
        print("Preprocessing data...")
        preprocess_task = self.dx.run_script('preprocess.py',
            inputFiles=[config['dataset']],
            outputFiles=['train.csv', 'val.csv']
        )
        
        # 2. Train
        print("Training model...")
        train_task = self.dx.run_script('train.py',
            inputFiles=['train.csv', 'val.csv'],
            outputFiles=['model.pth'],
            gpu=True,
            cuda=True,
            ramPerWorker=32768,
            timeout=86400
        )
        
        # 3. Evaluate
        print("Evaluating model...")
        eval_task = self.dx.run_script('evaluate.py',
            inputFiles=['model.pth', 'val.csv'],
            outputFiles=['metrics.json']
        )
        
        return eval_task

# Use it
pipeline = MLTrainingPipeline(api_key="your_key")
result = pipeline.train({
    'dataset': 'data.csv',
    'model_type': 'resnet50'
})
```

---

## 💡 Best Practices

### 1. Always Set Timeouts
```python
# Good
dx.run_script('script.py', timeout=3600)

# Bad (might run forever)
dx.run_script('script.py')
```

### 2. Handle Errors Gracefully
```python
try:
    result = dx.run_script('script.py')
except Exception as e:
    logging.error(f"Task failed: {e}")
    # Implement retry logic
```

### 3. Use Environment Variables for Secrets
```python
# Good
dx.run_script('script.py', environment={'API_KEY': os.getenv('SECRET_KEY')})

# Bad (hardcoding secrets)
dx.run_script('script.py', environment={'API_KEY': 'abc123'})
```

### 4. Monitor Resource Usage
```python
# Check network capacity first
stats = dx.network_stats()
if stats['availableCpuCores'] >= required_cores:
    dx.run_script('script.py', cpuPerWorker=required_cores)
```

---

**Happy Distributed Computing! 🚀**
