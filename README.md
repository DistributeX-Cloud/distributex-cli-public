# 🚀 DistributeX — Distributed Computing Made Simple

**Run Python & JavaScript code on a global network of computers**

Turn any heavy computation into a distributed task that runs across multiple machines simultaneously — automatically.

---

## 📖 Table of Contents

- [Quick Start](#-quick-start)
- [Python SDK Guide](#-python-sdk-guide)
- [JavaScript SDK Guide](#-javascript-sdk-guide)
- [How DistributeX Works](#-how-distributex-works)
- [Writing DistributeX Scripts](#-writing-distributex-scripts)
- [Multi-Worker Parallel Execution](#-multi-worker-parallel-execution)
- [Advanced Features](#-advanced-features)
- [Real-World Examples](#-real-world-examples)
- [API Reference](#-api-reference)
- [Become a Contributor](#-become-a-contributor)
- [Troubleshooting](#-troubleshooting)

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
const DistributeX = require('distributex-cloud');

const dx = new DistributeX('dx_your_key_here');

const calculateSum = (n) => {
    let total = 0;
    for (let i = 0; i < n; i++) total += i;
    return total;
};

dx.run(calculateSum, { args: [1000000] })
    .then(result => console.log(result));
```

---

## 🐍 Python SDK Guide

### Installation
```bash
pip install distributex-cloud
```

### Basic Function Execution

The Python SDK automatically serializes your function, detects dependencies, and executes it on remote workers.
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

### Auto-Detected Dependencies

The SDK automatically detects imported packages and installs them on the worker:
```python
def analyze_data(data_size):
    # These libraries are automatically detected and installed!
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

# NumPy and Pandas are auto-detected from imports
result = dx.run(analyze_data, args=(1000,))
print(result)
```

**How it works:**
1. SDK extracts function source code using `inspect.getsource()`
2. AST parser detects all `import` and `from` statements
3. Filters out standard library modules (os, sys, json, etc.)
4. Installs required packages on worker before execution

### Using Classes Inside Functions

**✅ CORRECT** — Define classes **inside** the function:
```python
def process_with_class(x, y):
    # Define class INSIDE the function
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

**❌ INCORRECT** — Classes outside won't be serialized:
```python
# ❌ This will fail!
class Calculator:
    def __init__(self, a, b):
        self.a = a
        self.b = b

def process_with_class(x, y):
    return Calculator(x, y).compute()  # Worker doesn't have this class!
```

### Function Execution Flow
```python
# 1. Function is serialized to standalone script
# 2. Script includes: function code + arguments + dependency installer
# 3. Script is base64 encoded and sent via API
# 4. Worker receives task with embedded script
# 5. Worker decodes and saves script as .py file
# 6. Worker installs dependencies (if any)
# 7. Worker executes: python script.py
# 8. Worker captures result and sends back to API
# 9. SDK polls task status and returns result
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

## 🟦 JavaScript SDK Guide

### Installation
```bash
npm install distributex-cloud
```

### Basic Function Execution
```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX('dx_your_key');

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

### Function Execution Flow
```javascript
// 1. SDK calls _createExecutableScript(func, args)
// 2. Function.toString() converts function to string
// 3. Script wraps function with args and result capture
// 4. Script is base64 encoded
// 5. Sent to API via POST /api/tasks/execute
// 6. Worker receives task with executionScript field
// 7. Worker decodes and saves as script.js
// 8. Worker executes: node script.js
// 9. Result saved to result.json
// 10. SDK polls and returns result
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

## 🔧 How DistributeX Works

### System Architecture
```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│             │     │                  │     │             │
│  Developer  │────▶│   DistributeX    │◀────│   Worker    │
│   (SDK)     │     │   Cloud API      │     │   Agent     │
│             │     │                  │     │             │
└─────────────┘     └──────────────────┘     └─────────────┘
                            │
                            ▼
                    ┌──────────────┐
                    │   Database   │
                    │  (Neon PG)   │
                    └──────────────┘
```

### Task Lifecycle

1. **Task Submission** — Developer calls `dx.run()` which serializes the function, encodes it to base64, and sends it via `POST /api/tasks/execute`

2. **Task Storage** — API stores task in database with status='pending' and embedded script in `execution_config` JSON field

3. **Task Distribution** — Worker polls `GET /api/workers/{id}/tasks/next` every 10 seconds looking for matching tasks based on resource requirements

4. **Task Assignment** — When match found, task status changes to 'active', worker downloads script or uses embedded version

5. **Execution** — Worker decodes base64 script, saves to file, installs dependencies, executes script, captures output

6. **Result Reporting** — Worker calls `PUT /api/tasks/{id}/complete` with output, task status changes to 'completed'

7. **Result Retrieval** — SDK polls task status, when completed calls `GET /api/tasks/{id}/result` to download result

### Component Details

#### SDK (Developer Side)

**Python SDK** (`python/distributex/client.py`):
- `DistributeX.run()` — Main entry point
- `FunctionSerializer.create_executable_script()` — Converts function to standalone script
- `ImportDetector.detect_imports()` — Uses AST to find all imported packages
- Creates script with: imports, function body, args, execution wrapper, result capture
- Base64 encodes entire script and sends via API

**JavaScript SDK** (`javascript/distributex/index.js`):
- `DistributeX.run()` — Main entry point
- `_createExecutableScript()` — Wraps function with args and result handling
- Uses `Function.toString()` to serialize function code
- Creates standalone Node.js script with require() support
- Base64 encodes and sends via API

#### API (Cloud Infrastructure)

**Task Execution** (`functions/api/tasks/execute.ts`):
- Accepts both `snake_case` (Python) and `camelCase` (JavaScript) parameters
- Validates authentication via JWT or API key
- Stores task in database with embedded `executionScript`
- Attempts immediate worker assignment if resources available
- Returns task ID and queue position

**Worker Task Polling** (`functions/api/workers/[id]/tasks/next.ts`):
- Worker requests next task matching its capabilities
- Filters by CPU, RAM, GPU, storage requirements
- Returns task with embedded script or download URL
- Updates task status to 'active' and worker status to 'busy'

#### Worker Agent

**Worker Agent** (`worker-agent.js`):
- Registers with API providing system capabilities
- Sends heartbeat every 60 seconds to stay 'online'
- Polls for tasks every 10 seconds
- Downloads and extracts code (supports embedded scripts, URLs, tar.gz, zip)
- Detects runtime from file extension or task config
- Installs dependencies automatically
- Executes script and captures stdout/stderr
- Reports completion or failure back to API

**Task Executor** (`worker-agent.js` TaskExecutor class):
- `execute()` — Main task execution logic
- `downloadAndExtract()` — Handles embedded scripts, URLs, archives
- `execPython()`, `execNode()`, `execBash()` — Runtime-specific execution
- `execDocker()` — Docker container execution support
- Captures output in real-time and streams to API

---

## 📝 Writing DistributeX Scripts

### Python Script Guidelines

#### ✅ DO: Keep Everything Self-Contained
```python
def my_distributed_function(data):
    # Import INSIDE the function
    import numpy as np
    import pandas as pd
    
    # Define helper functions INSIDE
    def helper(x):
        return x * 2
    
    # Define classes INSIDE
    class DataProcessor:
        def __init__(self, values):
            self.values = values
        
        def process(self):
            return [helper(v) for v in self.values]
    
    # Your logic here
    processor = DataProcessor(data)
    result = processor.process()
    
    # Return JSON-serializable data
    return {
        'processed': result,
        'count': len(result)
    }

# Execute
dx.run(my_distributed_function, args=([1, 2, 3],))
```

#### ❌ DON'T: Use External Dependencies
```python
# ❌ Global imports won't be available on worker
import numpy as np

# ❌ External classes won't be serialized
class MyClass:
    pass

# ❌ External functions won't be available
def external_helper():
    pass

def my_function():
    return external_helper()  # Will fail!
```

### JavaScript Script Guidelines

#### ✅ DO: Use Self-Contained Functions
```javascript
const myDistributedFunction = (data) => {
    // Require INSIDE the function
    const _ = require('lodash');
    
    // Define helpers INSIDE
    const helper = (x) => x * 2;
    
    // Your logic
    const processed = data.map(helper);
    
    // Return serializable data
    return {
        processed: processed,
        count: processed.length
    };
};

dx.run(myDistributedFunction, { args: [[1, 2, 3]] });
```

#### ❌ DON'T: Reference External Scope
```javascript
// ❌ External variables won't be available
const externalData = [1, 2, 3];

// ❌ External functions won't be serialized
const externalHelper = () => {};

const myFunction = () => {
    return externalHelper(externalData);  // Will fail!
};
```

### Script Execution Environment

When your script executes on a worker:

**Available:**
- Standard library (Python: os, sys, json; Node: fs, path, crypto)
- Auto-installed packages (detected from imports)
- Function arguments (passed via JSON)
- Environment variables (if provided)

**Not Available:**
- Parent scope variables or functions
- External class definitions
- Global state from your local machine
- Local file system (unless uploaded as input files)

### Return Value Guidelines

**What you can return:**
- Strings, numbers, booleans
- Lists/arrays
- Dictionaries/objects
- JSON-serializable data structures

**What to avoid:**
- File objects or handles
- Network connections
- Complex objects with circular references
- Binary data (use base64 encoding if needed)

### Resource Requirements

Specify resource needs based on your script:
```python
dx.run(
    my_function,
    args=(data,),
    cpu_per_worker=4,      # CPU cores needed
    ram_per_worker=8192,   # RAM in MB (8GB)
    gpu=True,              # Requires GPU
    cuda=True,             # Requires CUDA support
    timeout=7200           # Max 2 hours
)
```

**Resource Caps** (enforced by API):
- Max workers: 10
- Max CPU per worker: 16 cores
- Max RAM per worker: 32GB
- Max timeout: 24 hours
- Max priority: 10

---

## ⚡ Multi-Worker Parallel Execution

**Heavy tasks automatically use multiple workers to run faster!**

### How Parallelization Works

When you specify `workers > 1`, the system:

1. **Replicates Task** — Same script/function sent to multiple workers
2. **Parallel Execution** — Each worker executes independently
3. **Individual Results** — Each worker returns its result
4. **No Automatic Merging** — Results come back as individual task completions

**Note:** Current implementation runs identical copies on each worker. For data partitioning, you need to manually split your data and submit separate tasks.

### Python Example
```python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key")

def process_large_dataset(chunk_id, total_chunks):
    import numpy as np
    
    # Each worker processes its chunk
    chunk_size = 1000000 // total_chunks
    start = chunk_id * chunk_size
    end = start + chunk_size
    
    # Heavy computation on this chunk
    result = []
    for i in range(start, end):
        processed = np.sin(i) * np.cos(i)
        result.append(processed)
    
    return {
        'chunk_id': chunk_id,
        'processed_count': len(result),
        'sum': sum(result)
    }

# Submit multiple tasks (one per chunk)
tasks = []
num_workers = 4

for i in range(num_workers):
    task = dx.run(
        process_large_dataset,
        args=(i, num_workers),
        cpu_per_worker=4,
        wait=False  # Don't wait, submit all tasks
    )
    tasks.append(task)

# Wait for all tasks and collect results
results = []
for task in tasks:
    result = dx.get_result(task.id)
    results.append(result)

# Merge results
total_sum = sum(r['sum'] for r in results)
print(f"Processed {sum(r['processed_count'] for r in results)} items")
print(f"Total sum: {total_sum}")
```

### JavaScript Example
```javascript
const DistributeX = require('distributex-cloud');
const dx = new DistributeX('dx_your_key');

const processChunk = (chunkId, totalChunks) => {
    const chunkSize = Math.floor(1000000 / totalChunks);
    const start = chunkId * chunkSize;
    const end = start + chunkSize;
    
    let sum = 0;
    for (let i = start; i < end; i++) {
        sum += Math.sin(i) * Math.cos(i);
    }
    
    return {
        chunkId: chunkId,
        processedCount: chunkSize,
        sum: sum
    };
};

// Submit multiple tasks
const numWorkers = 4;
const promises = [];

for (let i = 0; i < numWorkers; i++) {
    const promise = dx.run(processChunk, {
        args: [i, numWorkers],
        cpuPerWorker: 4
    });
    promises.push(promise);
}

// Wait for all results
Promise.all(promises).then(results => {
    const totalSum = results.reduce((sum, r) => sum + r.sum, 0);
    const totalCount = results.reduce((sum, r) => sum + r.processedCount, 0);
    
    console.log(`Processed ${totalCount} items using ${numWorkers} workers`);
    console.log(`Total sum: ${totalSum}`);
});
```

---

## 🎨 Advanced Features

### GPU Acceleration
```python
def train_model(epochs):
    import tensorflow as tf
    
    # Your GPU-accelerated code
    model = tf.keras.Sequential([
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dense(10, activation='softmax')
    ])
    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy')
    # ... training code ...
    
    return {'accuracy': 0.95}

result = dx.run(
    train_model,
    args=(100,),
    gpu=True,              # Require GPU
    cuda=True,             # Require CUDA support
    ram_per_worker=16384   # 16GB RAM
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

### Real-Time Output Streaming

The Python SDK v2.0+ supports live output streaming:
```python
def long_running_task():
    import time
    
    print("Starting computation...")
    for i in range(10):
        time.sleep(1)
        print(f"Progress: {i+1}/10")  # Streamed to developer terminal!
    
    print("Done!")
    return "Success"

# Live output appears in your terminal as the worker executes
result = dx.run(
    long_running_task,
    wait=True,
    stream_output=True  # Enable real-time streaming
)
```

**How it works:**
1. Worker captures stdout/stderr
2. Worker sends batches to `POST /api/tasks/{id}/output`
3. SDK polls `GET /api/tasks/{id}/output?since={lastId}`
4. Output appears in developer's terminal in real-time

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

# Process 1000 images
image_urls = [...]  # Your image URLs
result = dx.run(
    process_images,
    args=(image_urls,),
    workers=1,  # Submit as single task
    ram_per_worker=4096
)
```

### 2. Machine Learning Training
```python
def train_neural_network(training_data, labels):
    import tensorflow as tf
    import numpy as np
    
    # Convert data
    X = np.array(training_data)
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

### 3. Data Analysis at Scale
```python
def analyze_market_data(stock_symbols):
    import pandas as pd
    import numpy as np
    
    results = {}
    
    for symbol in stock_symbols:
        # Simulate fetching data
        # In reality, you'd use yfinance or another API
        data = fetch_stock_data(symbol)
        
        # Calculate metrics
        df = pd.DataFrame(data)
        results[symbol] = {
            'mean': float(df['price'].mean()),
            'std': float(df['price'].std()),
            'trend': 'up' if df['price'].iloc[-1] > df['price'].iloc[0] else 'down'
        }
    
    return results

# Analyze stocks
stocks = ['AAPL', 'GOOGL', 'MSFT']  # Your stock symbols
result = dx.run(
    analyze_market_data,
    args=(stocks,),
    cpu_per_worker=4
)
```

---

## 📚 API Reference

### Python SDK

#### `DistributeX(api_key, base_url)`

Initialize the client.

**Parameters:**
- `api_key` (str): Your API key from dashboard
- `base_url` (str, optional): API endpoint (default: `https://distributex.cloud`)
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
- `workers` (int): Number of workers for parallel execution (default: 1, max: 10)
- `cpu_per_worker` (int): CPU cores per worker (default: 2, max: 16)
- `ram_per_worker` (int): RAM in MB per worker (default: 2048, max: 32768)
- `gpu` (bool): Require GPU (default: False)
- `cuda` (bool): Require CUDA (default: False)
- `storage` (int): Storage in GB (default: 10)
- `timeout` (int): Max seconds (default: 3600, max: 86400)
- `priority` (int): Priority 1-10 (default: 5)
- `wait` (bool): Wait for completion (default: True)
- `stream_output` (bool): Enable real-time output streaming (default: True)
- `packages` (list): Manual package list (overrides auto-detection)

**Returns:**
- Result of function if `wait=True`
- Task object with `id` and `status` if `wait=False`
```python
result = dx.run(
    my_function,
    args=(arg1, arg2),
    workers=1,
    cpu_per_worker=8,
    gpu=True,
    stream_output=True
)
```

---

#### `dx.get_task(task_id)`

Get task status.

**Returns:** Task object with `id`, `status`, `progress`, `error`
```python
status = dx.get_task('task-123')
print(status.status)  # 'pending', 'active', 'completed', 'failed'
print(status.progress)  # Progress percentage (0-100)
```

---

#### `dx.get_result(task_id)`

Download task result.

**Returns:** Task result data (automatically unwrapped from API response)
```python
result = dx.get_result('task-123')
```

**Result Format:**
- If stored in database: Returns the actual result value (unwrapped)
- If stored in file storage: Redirects to download URL
- Automatically extracts `result` or `output` field from JSON responses

---

#### `dx.network_stats()`

Get network statistics.

**Returns:** Dictionary with worker/resource stats
```python
stats = dx.network_stats()
print(stats['activeWorkers'])
print(stats['totalCpuCores'])
print(stats['availableCpuCores'])
```

---

### JavaScript SDK

#### `new DistributeX(apiKey, baseUrl)`

Initialize the client.
```javascript
const dx = new DistributeX('dx_your_key');
// Or with custom URL
const dx = new DistributeX('dx_your_key', 'https://distributex.cloud');
```

---

#### `dx.run(func, options)`

Execute a function on the network.

**Options:**
- `args` (array): Function arguments
- `workers` (number): Number of workers (default: 1, max: 10)
- `cpuPerWorker` (number): CPU cores per worker (default: 2, max: 16)
- `ramPerWorker` (number): RAM in MB per worker (default: 2048, max: 32768)
- `gpu` (boolean): Require GPU (default: false)
- `cuda` (boolean): Require CUDA (default: false)
- `timeout` (number): Max seconds (default: 3600, max: 86400)
- `wait` (boolean): Wait for completion (default: true)
```javascript
const result = await dx.run(myFunction, {
    args: [arg1, arg2],
    cpuPerWorker: 8,
    gpu: true
});
```

**Note:** JavaScript SDK accepts both `camelCase` (shown above) and `snake_case` (Python style) for compatibility.

---

#### `dx.getTask(taskId)`

Get task status.
```javascript
const status = await dx.getTask('task-123');
console.log(status.status);
console.log(status.progressPercent);
```

---

#### `dx.networkStats()`

Get network statistics.
```javascript
const stats = await dx.networkStats();
console.log(stats.activeWorkers);
console.log(stats.totalCpuCores);
```

---

## 🤝 Become a Contributor

**Share your computer's resources and earn rewards!**

### Quick Setup (One Command)
```bash
curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/refs/heads/main/public/install.sh | bash
```

The installer will:
1. Detect your system resources (CPU, RAM, GPU)
2. Install Docker worker container
3. Connect to the network
4. Start accepting tasks

### What Gets Shared?

You control what percentage of your resources to share:
- **CPU**: 90% by default (configurable)
- **RAM**: 80% by default (configurable)
- **GPU**: 70% by default (if available)
- **Storage**: 50% by default (configurable)

These percentages are set during registration and can be adjusted.

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

## 🙏 Acknowledgments

Built with love by the DistributeX team and our amazing community of contributors.

**Ready to get started?** → [Sign up now](https://distributex.cloud)

---
