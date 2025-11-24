# DistributeX Command Reference

## For Contributors (Share Resources)

### Installation
```bash
# Install and setup worker
curl -fsSL https://get.distributex.cloud | bash

# During installation, you'll be prompted to:
# 1. Create account or login
# 2. Select "Contributor" role
# 3. Choose external storage devices to share
# 4. Configure GPU (if available)
```

### Worker Management
```bash
# Check worker status
dxcloud worker status

# View live logs
dxcloud worker logs -f

# View last 100 log lines
dxcloud worker logs

# Restart worker
dxcloud worker restart

# Stop worker (stops earning)
dxcloud worker stop

# Start worker
dxcloud worker start

# Update to latest version
dxcloud worker update

# Remove worker from this device
dxcloud worker remove
```

### Resource Information
```bash
# View your contribution stats
dxcloud stats contribution

# Show current resource usage
dxcloud worker resources

# List connected storage devices
dxcloud storage list

# Add new storage device
dxcloud storage add

# Remove storage device
dxcloud storage remove <device>
```

### Network Status
```bash
# View global pool status
dxcloud pool status

# View all your devices
dxcloud devices list

# View earnings (coming soon)
dxcloud earnings
```

---

## For Developers (Use Network)

### Installation
```bash
# Install CLI tools
curl -fsSL https://get.distributex.cloud | bash

# During installation:
# 1. Create account or login
# 2. Select "Developer" or "Both" role
# 3. Get your API key
```

### Configuration
```bash
# Set API key
export DISTRIBUTEX_API_KEY="your_api_key_here"

# Or save to config
dxcloud config set api-key <your_key>

# View current config
dxcloud config show
```

### Submit Workloads

#### Simple Command Execution
```bash
# Run a Python script
dxcloud run python:3.11 python -c "print('Hello World')"

# Run with specific resources
dxcloud run python:3.11 \
  --cpu 2 \
  --memory 4 \
  --storage 10 \
  python train.py

# Run with GPU
dxcloud run tensorflow/tensorflow:latest-gpu \
  --gpu \
  --cpu 4 \
  --memory 16 \
  python train_model.py

# Run with environment variables
dxcloud run node:20 \
  -e DATABASE_URL=postgres://... \
  -e API_KEY=abc123 \
  node server.js

# Run with timeout
dxcloud run ubuntu:22.04 \
  --timeout 3600 \
  bash long_script.sh
```

#### Advanced Workload Submission
```bash
# Submit from config file
dxcloud submit workload.json

# workload.json example:
{
  "name": "data-processing",
  "image": "python:3.11",
  "command": ["python", "process.py"],
  "script": "import pandas as pd\n# your code here",
  "files": {
    "data.csv": "<base64_content>",
    "config.yaml": "<base64_content>"
  },
  "env": {
    "BATCH_SIZE": "100",
    "OUTPUT_PATH": "/storage/results"
  },
  "resources": {
    "cpu": 4,
    "memory": 8,
    "storage": 50
  },
  "storageNeeded": true,
  "timeout": 7200
}

# Submit with script file
dxcloud submit --script train.py \
  --image pytorch/pytorch:latest \
  --cpu 8 \
  --memory 32 \
  --gpu \
  --storage-required

# Submit batch workload
dxcloud batch submit workload1.json workload2.json workload3.json
```

### Monitor Workloads
```bash
# List all workloads
dxcloud workloads list

# Filter by status
dxcloud workloads list --status running
dxcloud workloads list --status pending
dxcloud workloads list --status completed

# Get workload details
dxcloud workloads status <workload-id>

# View logs
dxcloud workloads logs <workload-id>

# Stream logs in real-time
dxcloud workloads logs <workload-id> -f

# Download results
dxcloud workloads download <workload-id> -o results/
```

### Workload Control
```bash
# Cancel a running workload
dxcloud workloads cancel <workload-id>

# Delete workload and logs
dxcloud workloads delete <workload-id>

# Retry failed workload
dxcloud workloads retry <workload-id>
```

### Real-World Examples

#### Example 1: Data Processing
```bash
# Process large CSV file
dxcloud run python:3.11 \
  --cpu 4 \
  --memory 16 \
  --storage 100 \
  --storage-required \
  python << 'EOF'
import pandas as pd
import glob

# Read from external storage
files = glob.glob('/storage/*/data/*.csv')
for file in files:
    df = pd.read_csv(file)
    # Process data
    result = df.groupby('category').sum()
    # Save to external storage
    result.to_csv(f'/storage/results/{file.split("/")[-1]}')
EOF
```

#### Example 2: Machine Learning Training
```bash
# Train PyTorch model
dxcloud run pytorch/pytorch:latest \
  --gpu \
  --cpu 8 \
  --memory 32 \
  --storage 200 \
  --storage-required \
  --timeout 86400 \
  python train.py --epochs 100 --batch-size 128
```

#### Example 3: Video Processing
```bash
# Process video files
dxcloud run jrottenberg/ffmpeg:latest \
  --cpu 8 \
  --memory 16 \
  --storage 500 \
  --storage-required \
  bash << 'EOF'
#!/bin/bash
for video in /storage/*/videos/*.mp4; do
  ffmpeg -i "$video" \
    -vf scale=1280:720 \
    -c:v libx264 -preset slow -crf 22 \
    "/storage/output/$(basename $video)"
done
EOF
```

#### Example 4: Web Scraping
```bash
# Scrape websites
dxcloud run python:3.11 \
  --cpu 2 \
  --memory 4 \
  python << 'EOF'
import requests
from bs4 import BeautifulSoup
import json

urls = [...]  # List of URLs
results = []

for url in urls:
    response = requests.get(url)
    soup = BeautifulSoup(response.text, 'html.parser')
    # Extract data
    data = soup.find_all('div', class_='item')
    results.extend(data)

# Save results
with open('/storage/output/results.json', 'w') as f:
    json.dump(results, f)
EOF
```

#### Example 5: Scientific Computation
```bash
# Run simulation
dxcloud run continuumio/miniconda3:latest \
  --cpu 16 \
  --memory 64 \
  --timeout 172800 \
  bash << 'EOF'
#!/bin/bash
conda install -y numpy scipy matplotlib
python simulation.py --iterations 1000000 --output /storage/results/
EOF
```

### Usage Statistics
```bash
# View your usage stats
dxcloud stats usage

# View cost estimate
dxcloud stats cost

# View resource utilization
dxcloud stats resources

# Export usage report
dxcloud stats export --format csv -o report.csv
```

### Storage Operations
```bash
# List available storage in network
dxcloud storage network

# Upload file to distributed storage
dxcloud storage upload local_file.txt

# Download file from distributed storage
dxcloud storage download remote_file.txt

# List your stored files
dxcloud storage list

# Delete file
dxcloud storage delete file.txt
```

### Network Information
```bash
# View network statistics
dxcloud pool stats

# View available resources
dxcloud pool resources

# View current pricing
dxcloud pool pricing

# View network health
dxcloud pool health
```

---

## Common Workflows

### Contributor Workflow
```bash
# 1. Initial setup
curl -fsSL https://get.distributex.cloud | bash
# Select: Contributor, choose storage devices

# 2. Monitor contribution
dxcloud worker status
dxcloud stats contribution

# 3. Update periodically
dxcloud worker update

# 4. Check earnings (coming soon)
dxcloud earnings
```

### Developer Workflow
```bash
# 1. Initial setup
curl -fsSL https://get.distributex.cloud | bash
# Select: Developer or Both

# 2. Configure API key
dxcloud config set api-key <your_key>

# 3. Submit workload
dxcloud run python:3.11 --cpu 4 --memory 8 python script.py

# 4. Monitor progress
dxcloud workloads logs <workload-id> -f

# 5. Download results
dxcloud workloads download <workload-id>
```

### Both Roles Workflow
```bash
# Contribute resources AND use network
curl -fsSL https://get.distributex.cloud | bash
# Select: Both

# Monitor your contribution
dxcloud worker status

# Run your workloads
dxcloud run python:3.11 python my_script.py

# Net usage = your usage - your contribution
dxcloud stats balance
```

---

## API Usage (SDK)

### Python SDK
```python
from distributex import DistributeXClient

client = DistributeXClient(api_key='your_api_key')

# Submit workload
workload = client.submit_workload(
    name='data-processing',
    image='python:3.11',
    command=['python', 'process.py'],
    resources={'cpu': 4, 'memory': 8},
    storage_needed=True
)

# Monitor
for log in client.stream_logs(workload.id):
    print(log)

# Wait for completion
result = client.wait_for_completion(workload.id)
print(f"Exit code: {result.exit_code}")
```

### Node.js SDK
```javascript
const { DistributeXClient } = require('@distributex/sdk');

const client = new DistributeXClient({ 
  apiKey: 'your_api_key' 
});

// Submit workload
const workload = await client.submitWorkload({
  name: 'web-scraping',
  image: 'node:20',
  command: ['node', 'scraper.js'],
  resources: { cpu: 2, memory: 4 }
});

// Monitor
await client.streamLogs(workload.id, (log) => {
  console.log(log.message);
});

// Get results
const result = await client.getWorkload(workload.id);
```

---

## Environment Variables

### For Contributors
```bash
# Optional overrides
export DISTRIBUTEX_MAX_CPU=4        # Limit CPU cores to share
export DISTRIBUTEX_MAX_MEMORY=8     # Limit memory to share (GB)
export DISTRIBUTEX_MAX_STORAGE=50   # Limit storage to share (GB)
export DISTRIBUTEX_ENABLE_GPU=true  # Enable/disable GPU
```

### For Developers
```bash
# Required
export DISTRIBUTEX_API_KEY="your_key"

# Optional
export DISTRIBUTEX_API_URL="https://api.distributex.cloud"
export DISTRIBUTEX_DEFAULT_TIMEOUT=3600
export DISTRIBUTEX_DEFAULT_CPU=2
export DISTRIBUTEX_DEFAULT_MEMORY=4
```

---

## Troubleshooting

### Contributors
```bash
# Worker not showing online
dxcloud worker restart
docker logs distributex-worker

# GPU not detected
bash <(curl -fsSL https://get.distributex.cloud/gpu-diagnostic)

# Storage not accessible
dxcloud storage list
dxcloud storage reconnect

# Check logs
dxcloud worker logs
tail -f ~/.distributex/logs/worker.log
```

### Developers
```bash
# Workload stuck in pending
dxcloud pool status  # Check available resources

# Authentication errors
dxcloud config show
dxcloud config set api-key <new_key>

# Logs not showing
dxcloud workloads logs <id> --force-refresh

# Download failed results
dxcloud workloads download <id> --force
```
