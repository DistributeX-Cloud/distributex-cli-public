# Developer Quick Start - DistributeX

## Installation

### Python
```bash
# One-line install (fixed version)
curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/python/install_dev.sh | bash

# Set API key
export DISTRIBUTEX_API_KEY="dx_your_key_here"

# Test
python3 -c "from distributex import DistributeX; dx = DistributeX(); print(dx.network_stats())"
```

### JavaScript
```bash
# One-line install (fixed version)
curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/javascript/install_dev.sh | bash

# Set API key
export DISTRIBUTEX_API_KEY="dx_your_key_here"

# Test
node -e "const DX = require('distributex-cloud'); const dx = new DX(); dx.networkStats().then(console.log)"
```

## Get Your API Key

1. Visit: https://distributex-cloud-network.pages.dev/api-dashboard
2. Click "Generate API Key"
3. **COPY IT NOW** (shown only once!)
4. Set environment variable:
```bash
   export DISTRIBUTEX_API_KEY="dx_your_key_here"
```

## Simple Example

### Python
```python
from distributex import DistributeX

dx = DistributeX()

# Simple function
def calculate(n):
    return sum(range(n))

# Run on network
result = dx.run(calculate, args=(1000000,), cpu_per_worker=2)
print(f"Result: {result}")
```

### JavaScript
```javascript
const DistributeX = require('distributex-cloud');
const dx = new DistributeX();

// Simple function
const calculate = (n) => {
  let sum = 0;
  for (let i = 0; i < n; i++) sum += i;
  return sum;
};

// Run on network
dx.run(calculate, { args: [1000000], cpuPerWorker: 2 })
  .then(result => console.log(`Result: ${result}`));
```

## Next Steps

- [Examples](./EXAMPLES.md)
- [API Reference](./API.md)
- [Dashboard](https://distributex-cloud-network.pages.dev/dashboard)
