# 🚀 DistributeX — Distributed Computing Made Simple

**Run Python & JavaScript code on a global network of computers**

Turn any heavy computation into a distributed task that runs across multiple machines simultaneously — automatically.

---

## 📖 Table of Contents

- [Quick Start](#-quick-start)
- [Python Guide](#-python-guide)
- [JavaScript Guide](#-javascript-guide)
- [Multi-Worker Parallel Execution](#-multi-worker-parallel-execution)
- [Advanced Features](#-advanced-features)
- [Examples](#-real-world-examples)
- [API Reference](#-api-reference)
- [Contributing Resources](#-become-a-contributor)

---

## 🎯 Quick Start

### For Developers (Use the Network)

**1. Install SDK**

```bash
# Python
pip install distributex-cloud

# JavaScript/Node.js
npm install distributex-cloud
```

**2. Get Your API Key**

Visit [https://distributex.cloud/api-dashboard](https://distributex.cloud/api-dashboard) and generate your API key.

**3. Run Your First Task**

```python
# Python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key_here")

def calculate_sum(n):
    return sum(range(n))

result = dx.run(calculate_sum, args=(1000000,))
print(result)  # Runs on the network automatically!
```

```javascript
// JavaScript
const { DistributeX } = require('distributex-cloud');

const dx = new DistributeX({ apiKey: 'dx_your_key_here' });

const calculateSum = (n) => {
    let total = 0;
    for (let i = 0; i < n; i++) total += i;
    return total;
};

dx.run(calculateSum, { args: [1000000] })
    .then(result => console.log(result));
```

---

## 🐍 Python Guide

### Basic Function Execution

```python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key")

# ✅ Simple function
def process_data(items):
    total = 0
    for item in items:
        total += item ** 2
    return total

result = dx.run(process_data, args=([1, 2, 3, 4, 5],))
print(result)  # Output: 55
```

### With External Libraries (Auto-Installed!)

```python
def analyze_data(data_size):
    # These libraries are automatically installed on the worker!
    import numpy as np
    import pandas as pd
    
    # Create random data
    data = np.random.rand(data_size, 10)
    df = pd.DataFrame(data)
    
    return {
        'mean': float(df.mean().mean()),
        'std': float(df.std().mean()),
        'shape': df.shape
    }

# Libraries are auto-detected and installed
result = dx.run(analyze_data, args=(1000,))
print(result)
```

### Using Classes Inside Functions

**✅ CORRECT** — Classes must be **inside** the function:

```python
def process_with_class(x, y):
    
    class Calculator:
        def __init__(self, a, b):
            self.a = a
            self.b = b
        
        def compute(self):
            return self.a ** 2 + self.b ** 2
    
    calc = Calculator(x, y)
    return calc.compute()

result = dx.run(process_with_class, args=(3, 4))
print(result)  # Output: 25
```

**❌ INCORRECT** — Classes outside won't work:

```python
# ❌ This will fail!
class Calculator:
    def __init__(self, a, b):
        self.a = a
        self.b = b

def process_with_class(x, y):
    return Calculator(x, y).compute()  # Worker doesn't have this class!
```

### Arguments Syntax

```python
# Multiple arguments
dx.run(my_function, args=(arg1, arg2, arg3))

# Single argument (note the comma!)
dx.run(my_function, args=(single_arg,))

# No arguments
dx.run(my_function)

# With keyword arguments
dx.run(my_function, args=(10, 20), kwargs={'flag': True})
```

---

## 🟦 JavaScript Guide

### Basic Function Execution

```javascript
const { DistributeX } = require('distributex-cloud');

const dx = new DistributeX({ apiKey: 'dx_your_key' });

// ✅ Simple function
const processData = (items) => {
    return items.reduce((sum, item) => sum + item ** 2, 0);
};

dx.run(processData, { args: [[1, 2, 3, 4, 5]] })
    .then(result => console.log(result));  // Output: 55
```

### With NPM Packages (Auto-Installed!)

```javascript
const analyzeData = (dataSize) => {
    // These will be auto-installed on the worker
    const _ = require('lodash');
    const moment = require('moment');
    
    const numbers = _.range(dataSize);
    const sum = _.sum(numbers);
    
    return {
        sum: sum,
        average: sum / dataSize,
        timestamp: moment().format()
    };
};

dx.run(analyzeData, { args: [1000] })
    .then(result => console.log(result));
```

### Arguments Syntax

```javascript
// Multiple arguments
dx.run(myFunction, { args: [arg1, arg2, arg3] });

// Single argument
dx.run(myFunction, { args: [singleArg] });

// No arguments
dx.run(myFunction);
```

---

## ⚡ Multi-Worker Parallel Execution

**Heavy tasks automatically use multiple workers to run faster!**

### Python — Parallel Data Processing

```python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key")

def process_large_dataset(data):
    import numpy as np
    
    # Process a chunk of data
    result = []
    for item in data:
        # Heavy computation
        processed = np.sin(item) * np.cos(item) * np.sqrt(item)
        result.append(processed)
    
    return result

# This will automatically split across 4 workers!
large_data = list(range(1000000))
result = dx.run(
    process_large_dataset, 
    args=(large_data,),
    workers=4,              # ⚡ Use 4 workers simultaneously
    cpu_per_worker=4,       # Each worker gets 4 CPU cores
    ram_per_worker=8192     # Each worker gets 8GB RAM
)

print(f"Processed {len(result)} items using 4 workers!")
```

### JavaScript — Parallel Processing

```javascript
const { DistributeX } = require('distributex-cloud');

const dx = new DistributeX({ apiKey: 'dx_your_key' });

const processChunk = (data) => {
    // Heavy computation on a data chunk
    return data.map(item => {
        return Math.sin(item) * Math.cos(item) * Math.sqrt(item);
    });
};

// Automatically splits across 4 workers
const largeData = Array.from({ length: 1000000 }, (_, i) => i);

dx.run(processChunk, {
    args: [largeData],
    workers: 4,              // ⚡ 4 workers simultaneously
    cpuPerWorker: 4,         // 4 CPU cores per worker
    ramPerWorker: 8192       // 8GB RAM per worker
}).then(result => {
    console.log(`Processed ${result.length} items using 4 workers!`);
});
```

### How It Works

When you specify `workers > 1`:

1. **Automatic Splitting**: Your data is automatically divided into chunks
2. **Parallel Execution**: Each chunk runs on a different worker machine simultaneously
3. **Result Merging**: Results are automatically combined in the correct order
4. **Faster Processing**: 4 workers = ~4x faster (depending on task)

```python
# Single worker (slower)
result = dx.run(my_function, args=(data,), workers=1)

# Multi-worker (faster!)
result = dx.run(my_function, args=(data,), workers=4)
```

---

## 🎨 Advanced Features

### GPU Acceleration

```python
def train_model(epochs):
    import tensorflow as tf
    
    # Your GPU-accelerated code
    model = tf.keras.Sequential([...])
    model.compile(...)
    model.fit(...)
    
    return model.evaluate()

result = dx.run(
    train_model, 
    args=(100,),
    gpu=True,              # Require GPU
    cuda=True,             # Require CUDA support
    ram_per_worker=16384   # 16GB RAM
)
```

### Resource Allocation

```python
result = dx.run(
    my_function,
    args=(data,),
    
    # Parallelization
    workers=4,                  # Number of workers
    
    # Resources per worker
    cpu_per_worker=8,           # CPU cores
    ram_per_worker=16384,       # RAM in MB (16GB)
    
    # GPU requirements
    gpu=True,                   # Need GPU
    cuda=True,                  # Need CUDA
    
    # Timing
    timeout=7200,               # Max 2 hours
    priority=8                  # Higher priority (1-10)
)
```

### Async Execution (Fire and Forget)

```python
# Submit without waiting
task = dx.run(
    long_running_task,
    args=(data,),
    wait=False  # Don't wait for completion
)

print(f"Task submitted: {task.id}")

# Check status later
status = dx.get_task(task.id)
print(f"Status: {status.status}")

# Get result when ready
if status.status == 'completed':
    result = dx.get_result(task.id)
```

### Network Statistics

```python
stats = dx.network_stats()

print(f"Available Workers: {stats['activeWorkers']}")
print(f"Total CPU Cores: {stats['totalCpuCores']}")
print(f"Available GPUs: {stats['totalGpus']}")
```

---

## 💡 Real-World Examples

### 1. Image Processing Pipeline

```python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key")

def process_images(image_urls):
    from PIL import Image
    import requests
    from io import BytesIO
    
    results = []
    for url in image_urls:
        # Download image
        response = requests.get(url)
        img = Image.open(BytesIO(response.content))
        
        # Process (resize, filter, etc.)
        img = img.resize((800, 600))
        img = img.convert('L')  # Grayscale
        
        results.append({
            'url': url,
            'size': img.size,
            'mode': img.mode
        })
    
    return results

# Process 1000 images across 10 workers
image_urls = [...]  # Your image URLs
result = dx.run(
    process_images,
    args=(image_urls,),
    workers=10,
    ram_per_worker=4096
)
```

### 2. Machine Learning Training

```python
def train_neural_network(data, labels):
    import tensorflow as tf
    import numpy as np
    
    # Convert data
    X = np.array(data)
    y = np.array(labels)
    
    # Build model
    model = tf.keras.Sequential([
        tf.keras.layers.Dense(128, activation='relu', input_shape=(X.shape[1],)),
        tf.keras.layers.Dropout(0.2),
        tf.keras.layers.Dense(64, activation='relu'),
        tf.keras.layers.Dense(10, activation='softmax')
    ])
    
    model.compile(
        optimizer='adam',
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    
    # Train
    history = model.fit(X, y, epochs=50, batch_size=32, validation_split=0.2)
    
    return {
        'final_accuracy': float(history.history['accuracy'][-1]),
        'val_accuracy': float(history.history['val_accuracy'][-1])
    }

# Train with GPU acceleration
result = dx.run(
    train_neural_network,
    args=(training_data, labels),
    gpu=True,
    cuda=True,
    cpu_per_worker=8,
    ram_per_worker=32768  # 32GB
)
```

### 3. Financial Data Analysis

```python
def analyze_market_data(stock_symbols):
    import pandas as pd
    import numpy as np
    
    results = {}
    
    for symbol in stock_symbols:
        # Simulate fetching data
        data = fetch_stock_data(symbol)
        
        # Calculate metrics
        df = pd.DataFrame(data)
        results[symbol] = {
            'mean': df['price'].mean(),
            'std': df['price'].std(),
            'trend': 'up' if df['price'].iloc[-1] > df['price'].iloc[0] else 'down'
        }
    
    return results

# Analyze 100 stocks across 5 workers
stocks = ['AAPL', 'GOOGL', 'MSFT', ...]  # 100 symbols
result = dx.run(
    analyze_market_data,
    args=(stocks,),
    workers=5,
    cpu_per_worker=4
)
```

### 4. Text Processing at Scale

```python
def process_documents(documents):
    import re
    from collections import Counter
    
    results = []
    
    for doc in documents:
        # Clean text
        text = doc['content'].lower()
        text = re.sub(r'[^\w\s]', '', text)
        
        # Analyze
        words = text.split()
        word_count = Counter(words)
        
        results.append({
            'id': doc['id'],
            'word_count': len(words),
            'unique_words': len(word_count),
            'top_words': word_count.most_common(10)
        })
    
    return results

# Process 10,000 documents across 8 workers
documents = [...]  # Your documents
result = dx.run(
    process_documents,
    args=(documents,),
    workers=8,
    cpu_per_worker=4,
    ram_per_worker=8192
)
```

---

## 📚 API Reference

### Python SDK

#### `DistributeX(api_key, base_url)`

Initialize the client.

**Parameters:**
- `api_key` (str): Your API key from dashboard
- `base_url` (str, optional): API endpoint (default: production)

```python
dx = DistributeX(api_key="dx_your_key")
```

---

#### `dx.run(func, args=(), kwargs={}, **options)`

Execute a function on the network.

**Parameters:**
- `func` (callable): Function to execute
- `args` (tuple): Positional arguments
- `kwargs` (dict): Keyword arguments
- `workers` (int): Number of workers for parallel execution (default: 1)
- `cpu_per_worker` (int): CPU cores per worker (default: 2)
- `ram_per_worker` (int): RAM in MB per worker (default: 2048)
- `gpu` (bool): Require GPU (default: False)
- `cuda` (bool): Require CUDA (default: False)
- `timeout` (int): Max seconds (default: 3600)
- `priority` (int): Priority 1-10 (default: 5)
- `wait` (bool): Wait for completion (default: True)

**Returns:**
- Result of function if `wait=True`
- Task object if `wait=False`

```python
result = dx.run(
    my_function,
    args=(arg1, arg2),
    workers=4,
    cpu_per_worker=8,
    gpu=True
)
```

---

#### `dx.get_task(task_id)`

Get task status.

**Returns:** Task object with `status`, `progress`, `error`

```python
status = dx.get_task('task-123')
print(status.status)  # 'pending', 'active', 'completed', 'failed'
```

---

#### `dx.get_result(task_id)`

Download task result.

**Returns:** Task result data

```python
result = dx.get_result('task-123')
```

---

#### `dx.network_stats()`

Get network statistics.

**Returns:** Dictionary with worker/resource stats

```python
stats = dx.network_stats()
print(stats['activeWorkers'])
```

---

### JavaScript SDK

#### `new DistributeX({ apiKey, baseUrl })`

Initialize the client.

```javascript
const dx = new DistributeX({ 
    apiKey: 'dx_your_key',
    baseUrl: 'https://distributex.cloud'  // optional
});
```

---

#### `dx.run(func, options)`

Execute a function on the network.

**Options:**
- `args` (array): Function arguments
- `workers` (number): Number of workers (default: 1)
- `cpuPerWorker` (number): CPU cores per worker (default: 2)
- `ramPerWorker` (number): RAM in MB per worker (default: 2048)
- `gpu` (boolean): Require GPU (default: false)
- `cuda` (boolean): Require CUDA (default: false)
- `timeout` (number): Max seconds (default: 3600)
- `wait` (boolean): Wait for completion (default: true)

```javascript
const result = await dx.run(myFunction, {
    args: [arg1, arg2],
    workers: 4,
    cpuPerWorker: 8,
    gpu: true
});
```

---

#### `dx.getTask(taskId)`

Get task status.

```javascript
const status = await dx.getTask('task-123');
console.log(status.status);
```

---

#### `dx.networkStats()`

Get network statistics.

```javascript
const stats = await dx.networkStats();
console.log(stats.activeWorkers);
```

---

## 🤝 Become a Contributor

**Share your computer's resources and earn rewards!**

### Quick Setup (One Command)

```bash
# Linux/Mac
curl -sSL https://distributex.cloud/install.sh | bash

# Windows (PowerShell)
irm https://distributex.cloud/install.ps1 | iex
```

The installer will:
1. Detect your system resources (CPU, RAM, GPU)
2. Install Docker worker container
3. Connect to the network
4. Start earning for shared resources

### What Gets Shared?

You control what percentage of your resources to share:
- **CPU**: 90% by default
- **RAM**: 80% by default
- **GPU**: 70% by default (if available)
- **Storage**: 50% by default

### Monitor Your Worker

```bash
# Check status
docker ps | grep distributex-worker

# View logs
docker logs -f distributex-worker

# Check resource usage
docker stats distributex-worker
```

### Dashboard

Monitor your contributions at [https://distributex.cloud/dashboard](https://distributex.cloud/dashboard)

---

## 🔒 Security & Privacy

- **Sandboxed Execution**: All tasks run in isolated containers
- **Code Verification**: Tasks are scanned for malicious code
- **Resource Limits**: Strict CPU/RAM/storage limits enforced
- **No Data Retention**: Worker results are deleted after retrieval
- **Encrypted Communication**: All API calls use HTTPS

---

## 💰 Pricing

### For Developers

Pay only for what you use:
- **CPU**: $0.01 per core-hour
- **RAM**: $0.005 per GB-hour
- **GPU**: $0.50 per GPU-hour
- **Free Tier**: 100 tasks/month, 10 CPU hours

### For Contributors

Earn rewards for sharing resources:
- **CPU**: Earn based on cores shared
- **GPU**: Higher rewards for GPU sharing
- **Uptime Bonuses**: Extra rewards for consistent availability

---

## 📖 Documentation

- **Full Documentation**: [https://distributex.cloud/docs](https://distributex.cloud/docs)
- **API Reference**: [https://distributex.cloud/api](https://distributex.cloud/api)
- **Examples**: [https://github.com/distributex/examples](https://github.com/distributex/examples)
- **Discord Community**: [https://discord.gg/distributex](https://discord.gg/distributex)

---

## 🐛 Troubleshooting

### Common Issues

**"Authentication required"**
```python
# Make sure your API key is correct
dx = DistributeX(api_key="dx_your_actual_key")
```

**"No workers available"**
```python
# Check network status
stats = dx.network_stats()
print(stats['activeWorkers'])  # Should be > 0
```

**Function fails with import errors**
```python
# Put all imports INSIDE the function
def my_function():
    import numpy as np  # ✅ Import inside
    # ... rest of code
```

**Task stuck in pending**
```python
# Check task status
status = dx.get_task(task_id)
print(status.status, status.error)
```

---

## 🚀 Roadmap

- [x] Python SDK
- [x] JavaScript SDK
- [x] Multi-worker parallel execution
- [x] GPU support
- [ ] Go SDK
- [ ] Rust SDK
- [ ] Spot instances (lower cost)
- [ ] Private worker pools
- [ ] Custom Docker images

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details

---

## 🙏 Acknowledgments

Built with love by the DistributeX team and our amazing community of contributors.

**Ready to get started?** → [Sign up now](https://distributex.cloud/signup)

---

**Questions?** → [support@distributex.cloud](mailto:support@distributex.cloud) | [Discord](https://discord.gg/distributex)
