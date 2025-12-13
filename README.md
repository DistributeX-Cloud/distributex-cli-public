# 🚀 Writing Custom Scripts for DistributeX

**Run ANY Python or JavaScript code on a global network of computers**

This guide shows you how to write scripts that run **100% on remote workers** — your local machine just submits the task and receives the result!

---

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [The Golden Rule](#-the-golden-rule)
- [Python Scripts](#-python-scripts)
- [JavaScript Scripts](#-javascript-scripts)
- [Common Patterns](#-common-patterns)
- [Troubleshooting](#-troubleshooting)
- [Real Examples](#-real-examples)

---

## 🎯 Quick Start

### Install SDK

```bash
# Python
pip install distributex-cloud

# JavaScript
npm install distributex-cloud
```

### Get API Key

Visit [https://distributex.cloud/api-dashboard](https://distributex.cloud/api-dashboard)

### Your First Script

**Python:**
```python
from distributex import DistributeX

dx = DistributeX(api_key="dx_your_key")

def hello_world():
    return "Hello from the cloud!"

result = dx.run(hello_world)
print(result)  # "Hello from the cloud!"
```

**JavaScript:**
```javascript
const DistributeX = require('distributex-cloud');

const dx = new DistributeX('dx_your_key');

const helloWorld = () => {
    return "Hello from the cloud!";
};

dx.run(helloWorld).then(result => {
    console.log(result);  // "Hello from the cloud!"
});
```

---

## 🏆 The Golden Rule

> **Everything your function needs must be INSIDE the function**

When your code runs on a remote worker:
- ❌ No access to your local files
- ❌ No access to variables outside the function
- ❌ No access to other functions you defined
- ✅ Only what's INSIDE the function exists

Think of it like this: Your function is teleported to a different computer in a different location. Only what's inside the function goes with it!

---

## 🐍 Python Scripts

### ✅ Correct Pattern

```python
def my_task():
    # Import packages INSIDE the function
    import numpy as np
    import pandas as pd
    
    # Define helper functions INSIDE
    def helper(x):
        return x * 2
    
    # Define classes INSIDE
    class Calculator:
        def add(self, a, b):
            return a + b
    
    # Your logic here
    data = [1, 2, 3, 4, 5]
    result = [helper(x) for x in data]
    
    calc = Calculator()
    total = calc.add(sum(result), 10)
    
    # Return JSON-serializable data
    return {
        "result": result,
        "total": total
    }

# Run it
result = dx.run(my_task)
print(result)
```

### ❌ Common Mistakes

```python
# ❌ WRONG: Import outside function
import numpy as np

def my_task():
    # Worker doesn't have numpy!
    return np.mean([1, 2, 3])

# ❌ WRONG: Helper function outside
def helper(x):
    return x * 2

def my_task():
    # Worker doesn't have helper()!
    return helper(5)

# ❌ WRONG: Using local variables
local_data = [1, 2, 3]

def my_task():
    # Worker doesn't have local_data!
    return sum(local_data)
```

### ✅ How to Fix Them

```python
# ✅ CORRECT: Import inside
def my_task():
    import numpy as np
    return np.mean([1, 2, 3])

# ✅ CORRECT: Helper inside
def my_task():
    def helper(x):
        return x * 2
    return helper(5)

# ✅ CORRECT: Pass data as argument
def my_task(data):
    return sum(data)

result = dx.run(my_task, args=([1, 2, 3],))
```

### 🎁 Auto-Installed Packages

The SDK automatically detects and installs packages:

```python
def analyze_data(size):
    # These are automatically detected and installed!
    import numpy as np
    import pandas as pd
    import matplotlib.pyplot as plt
    from sklearn.linear_model import LinearRegression
    
    # Create data
    data = np.random.rand(size, 5)
    df = pd.DataFrame(data)
    
    # Analysis
    model = LinearRegression()
    X = df.iloc[:, :4]
    y = df.iloc[:, 4]
    model.fit(X, y)
    
    return {
        "score": model.score(X, y),
        "shape": df.shape
    }

# NumPy, Pandas, Matplotlib, Scikit-learn all installed automatically!
result = dx.run(analyze_data, args=(1000,))
```

**Supported packages:** Any package on PyPI!

### 📦 Passing Arguments

```python
# Single argument
def process(data):
    return sum(data)

dx.run(process, args=([1, 2, 3],))  # Note the comma!

# Multiple arguments
def calculate(x, y, operation):
    if operation == 'add':
        return x + y
    return x * y

dx.run(calculate, args=(10, 5, 'add'))

# Keyword arguments
def greet(name, greeting='Hello'):
    return f"{greeting}, {name}!"

dx.run(greet, args=('Alice',), kwargs={'greeting': 'Hi'})
```

### 🎨 Real Python Example

```python
def image_processing(image_urls):
    """Download and process images on remote worker"""
    from PIL import Image
    import requests
    from io import BytesIO
    import numpy as np
    
    results = []
    
    for url in image_urls:
        # Download image
        response = requests.get(url)
        img = Image.open(BytesIO(response.content))
        
        # Process
        img = img.resize((800, 600))
        img = img.convert('RGB')
        
        # Extract features
        img_array = np.array(img)
        avg_color = np.mean(img_array, axis=(0, 1))
        
        results.append({
            "url": url,
            "size": img.size,
            "avg_color": avg_color.tolist()
        })
    
    return results

# Process 100 images on the cloud
urls = ["https://example.com/img1.jpg", "https://example.com/img2.jpg", ...]
result = dx.run(image_processing, args=(urls,))
```

---

## 🟦 JavaScript Scripts

### ✅ Correct Pattern

```javascript
const myTask = () => {
    // Require packages INSIDE the function
    const _ = require('lodash');
    const moment = require('moment');
    
    // Define helpers INSIDE
    const helper = (x) => x * 2;
    
    // Your logic here
    const data = [1, 2, 3, 4, 5];
    const result = data.map(helper);
    const sum = _.sum(result);
    
    // Return serializable data
    return {
        result: result,
        sum: sum,
        timestamp: moment().format()
    };
};

// Run it
dx.run(myTask).then(result => console.log(result));
```

### ❌ Common Mistakes

```javascript
// ❌ WRONG: Require outside function
const _ = require('lodash');

const myTask = () => {
    // Worker doesn't have lodash!
    return _.sum([1, 2, 3]);
};

// ❌ WRONG: Helper outside
const helper = (x) => x * 2;

const myTask = () => {
    // Worker doesn't have helper!
    return helper(5);
};

// ❌ WRONG: External variable
const localData = [1, 2, 3];

const myTask = () => {
    // Worker doesn't have localData!
    return localData.reduce((a, b) => a + b);
};
```

### ✅ How to Fix Them

```javascript
// ✅ CORRECT: Require inside
const myTask = () => {
    const _ = require('lodash');
    return _.sum([1, 2, 3]);
};

// ✅ CORRECT: Helper inside
const myTask = () => {
    const helper = (x) => x * 2;
    return helper(5);
};

// ✅ CORRECT: Pass as argument
const myTask = (data) => {
    return data.reduce((a, b) => a + b);
};

dx.run(myTask, { args: [[1, 2, 3]] });
```

### 🎁 Auto-Installed Packages

The SDK automatically installs NPM packages:

```javascript
const analyzeData = (dataSize) => {
    // These are automatically installed!
    const _ = require('lodash');
    const moment = require('moment');
    const axios = require('axios');
    
    // Generate data
    const numbers = _.range(dataSize);
    const sum = _.sum(numbers);
    
    return {
        sum: sum,
        average: sum / dataSize,
        timestamp: moment().format(),
        size: dataSize
    };
};

// Lodash, Moment, Axios all installed automatically!
dx.run(analyzeData, { args: [1000] })
    .then(result => console.log(result));
```

**Supported packages:** Any package on NPM!

### 📦 Passing Arguments

```javascript
// Single argument
const process = (data) => {
    return data.reduce((a, b) => a + b);
};

dx.run(process, { args: [[1, 2, 3]] });

// Multiple arguments
const calculate = (x, y, operation) => {
    if (operation === 'add') return x + y;
    return x * y;
};

dx.run(calculate, { args: [10, 5, 'add'] });

// No arguments
const getTimestamp = () => {
    return new Date().toISOString();
};

dx.run(getTimestamp);
```

### 🎨 Real JavaScript Example

```javascript
const processLogs = (logUrls) => {
    const axios = require('axios');
    const _ = require('lodash');
    
    const results = [];
    
    for (const url of logUrls) {
        // Fetch log file
        const response = await axios.get(url);
        const logs = response.data.split('\n');
        
        // Parse and analyze
        const errors = logs.filter(line => line.includes('ERROR'));
        const warnings = logs.filter(line => line.includes('WARN'));
        
        // Group by hour
        const byHour = _.groupBy(logs, (line) => {
            const match = line.match(/\d{2}:\d{2}/);
            return match ? match[0].split(':')[0] : 'unknown';
        });
        
        results.push({
            url: url,
            totalLines: logs.length,
            errors: errors.length,
            warnings: warnings.length,
            hourlyBreakdown: _.mapValues(byHour, arr => arr.length)
        });
    }
    
    return results;
};

// Analyze logs on the cloud
const urls = ['https://logs.example.com/app.log', ...];
dx.run(processLogs, { args: [urls] })
    .then(result => console.log(result));
```

---

## 🎯 Common Patterns

### Pattern 1: Data Processing

**Python:**
```python
def process_dataset(data):
    import pandas as pd
    import numpy as np
    
    # Convert to DataFrame
    df = pd.DataFrame(data)
    
    # Process
    df['processed'] = df['value'] * 2
    df['normalized'] = (df['value'] - df['value'].mean()) / df['value'].std()
    
    # Results
    return {
        "mean": float(df['value'].mean()),
        "std": float(df['value'].std()),
        "processed": df.to_dict('records')
    }

data = [{"value": 10}, {"value": 20}, {"value": 30}]
result = dx.run(process_dataset, args=(data,))
```

**JavaScript:**
```javascript
const processDataset = (data) => {
    const _ = require('lodash');
    
    // Process
    const processed = data.map(item => ({
        ...item,
        processed: item.value * 2
    }));
    
    // Stats
    const values = data.map(item => item.value);
    const mean = _.mean(values);
    const std = Math.sqrt(_.mean(values.map(v => Math.pow(v - mean, 2))));
    
    return { mean, std, processed };
};

const data = [{value: 10}, {value: 20}, {value: 30}];
dx.run(processDataset, { args: [data] });
```

### Pattern 2: Web Scraping

**Python:**
```python
def scrape_website(url):
    import requests
    from bs4 import BeautifulSoup
    
    # Fetch page
    response = requests.get(url)
    soup = BeautifulSoup(response.content, 'html.parser')
    
    # Extract data
    titles = [h2.text for h2 in soup.find_all('h2')]
    links = [a['href'] for a in soup.find_all('a', href=True)]
    
    return {
        "url": url,
        "titles": titles,
        "links": links[:10]  # First 10 links
    }

result = dx.run(scrape_website, args=('https://example.com',))
```

**JavaScript:**
```javascript
const scrapeWebsite = async (url) => {
    const axios = require('axios');
    const cheerio = require('cheerio');
    
    // Fetch page
    const response = await axios.get(url);
    const $ = cheerio.load(response.data);
    
    // Extract data
    const titles = [];
    $('h2').each((i, elem) => {
        titles.push($(elem).text());
    });
    
    const links = [];
    $('a').each((i, elem) => {
        const href = $(elem).attr('href');
        if (href) links.push(href);
    });
    
    return {
        url: url,
        titles: titles,
        links: links.slice(0, 10)
    };
};

dx.run(scrapeWebsite, { args: ['https://example.com'] });
```

### Pattern 3: Machine Learning

**Python:**
```python
def train_model(training_data, labels):
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split
    import numpy as np
    
    # Prepare data
    X = np.array(training_data)
    y = np.array(labels)
    
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Train
    model = RandomForestClassifier(n_estimators=100)
    model.fit(X_train, y_train)
    
    # Evaluate
    train_score = model.score(X_train, y_train)
    test_score = model.score(X_test, y_test)
    
    return {
        "train_accuracy": float(train_score),
        "test_accuracy": float(test_score),
        "feature_importance": model.feature_importances_.tolist()
    }

# Train on cloud with GPU
result = dx.run(
    train_model,
    args=(X_data, y_labels),
    cpu_per_worker=8,
    ram_per_worker=16384,
    gpu=True
)
```

### Pattern 4: File Processing

**Python:**
```python
def process_csv_data(csv_url):
    import pandas as pd
    import requests
    from io import StringIO
    
    # Download CSV
    response = requests.get(csv_url)
    csv_data = StringIO(response.text)
    
    # Load and process
    df = pd.read_csv(csv_data)
    
    # Analysis
    summary = {
        "rows": len(df),
        "columns": list(df.columns),
        "numeric_summary": df.describe().to_dict(),
        "missing_values": df.isnull().sum().to_dict()
    }
    
    return summary

result = dx.run(
    process_csv_data,
    args=('https://data.example.com/dataset.csv',)
)
```

### Pattern 5: API Calls

**JavaScript:**
```javascript
const aggregateAPIs = async (apiUrls) => {
    const axios = require('axios');
    
    const results = [];
    
    for (const url of apiUrls) {
        try {
            const response = await axios.get(url);
            results.push({
                url: url,
                status: response.status,
                data: response.data
            });
        } catch (error) {
            results.push({
                url: url,
                error: error.message
            });
        }
    }
    
    return {
        total: results.length,
        successful: results.filter(r => !r.error).length,
        failed: results.filter(r => r.error).length,
        results: results
    };
};

const apis = [
    'https://api.example.com/data',
    'https://api2.example.com/stats',
    'https://api3.example.com/info'
];

dx.run(aggregateAPIs, { args: [apis] });
```

---

## 🐛 Troubleshooting

### Problem: "Module not found"

**Error:**
```
ModuleNotFoundError: No module named 'numpy'
```

**Solution:** Import INSIDE the function!

```python
# ❌ WRONG
import numpy as np
def task():
    return np.array([1,2,3])

# ✅ CORRECT
def task():
    import numpy as np
    return np.array([1,2,3])
```

### Problem: "Function not defined"

**Error:**
```
NameError: name 'helper' is not defined
```

**Solution:** Define helpers INSIDE the function!

```python
# ❌ WRONG
def helper(x):
    return x * 2

def task():
    return helper(5)

# ✅ CORRECT
def task():
    def helper(x):
        return x * 2
    return helper(5)
```

### Problem: "Variable not found"

**Error:**
```
NameError: name 'data' is not defined
```

**Solution:** Pass data as arguments!

```python
# ❌ WRONG
data = [1, 2, 3]
def task():
    return sum(data)

# ✅ CORRECT
def task(data):
    return sum(data)

dx.run(task, args=([1, 2, 3],))
```

### Problem: Can't return object

**Error:**
```
TypeError: Object of type 'DataFrame' is not JSON serializable
```

**Solution:** Convert to basic types!

```python
def task():
    import pandas as pd
    df = pd.DataFrame({"a": [1, 2, 3]})
    
    # ❌ WRONG: Can't return DataFrame
    # return df
    
    # ✅ CORRECT: Convert to dict
    return df.to_dict('records')
```

**Serializable types:**
- ✅ Strings, numbers, booleans
- ✅ Lists, tuples, dictionaries
- ✅ None / null
- ❌ File objects
- ❌ Class instances
- ❌ Functions

---

## 🎓 Real Examples

### Example 1: Crypto Price Analysis

```python
def analyze_crypto_prices(symbols, days):
    import requests
    import pandas as pd
    from datetime import datetime, timedelta
    
    results = {}
    
    for symbol in symbols:
        # Fetch historical data
        url = f"https://api.coingecko.com/api/v3/coins/{symbol}/market_chart"
        params = {"vs_currency": "usd", "days": days}
        
        response = requests.get(url, params=params)
        data = response.json()
        
        # Process prices
        prices = [p[1] for p in data['prices']]
        df = pd.Series(prices)
        
        results[symbol] = {
            "current_price": prices[-1],
            "mean": float(df.mean()),
            "std": float(df.std()),
            "min": float(df.min()),
            "max": float(df.max()),
            "change_percent": ((prices[-1] - prices[0]) / prices[0]) * 100
        }
    
    return results

# Analyze on cloud
symbols = ['bitcoin', 'ethereum', 'cardano']
result = dx.run(analyze_crypto_prices, args=(symbols, 30))
```

### Example 2: Video Processing

```python
def extract_video_frames(video_url, frame_count):
    import cv2
    import numpy as np
    import requests
    from io import BytesIO
    
    # Download video
    response = requests.get(video_url)
    video_bytes = BytesIO(response.content)
    
    # Save temporarily
    with open('/tmp/video.mp4', 'wb') as f:
        f.write(video_bytes.read())
    
    # Extract frames
    cap = cv2.VideoCapture('/tmp/video.mp4')
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frame_interval = total_frames // frame_count
    
    frames_data = []
    for i in range(frame_count):
        cap.set(cv2.CAP_PROP_POS_FRAMES, i * frame_interval)
        ret, frame = cap.read()
        
        if ret:
            # Get frame statistics
            frames_data.append({
                "frame_number": i * frame_interval,
                "avg_brightness": float(np.mean(frame)),
                "shape": frame.shape
            })
    
    cap.release()
    
    return {
        "total_frames": total_frames,
        "extracted": len(frames_data),
        "frames": frames_data
    }

# Process video on GPU worker
result = dx.run(
    extract_video_frames,
    args=('https://example.com/video.mp4', 10),
    cpu_per_worker=8,
    ram_per_worker=16384,
    gpu=True
)
```

### Example 3: Database Migration

```python
def migrate_database(source_db_url, target_db_url, table_name):
    import psycopg2
    import pandas as pd
    
    # Connect to source
    source_conn = psycopg2.connect(source_db_url)
    
    # Read data
    df = pd.read_sql(f"SELECT * FROM {table_name}", source_conn)
    source_conn.close()
    
    # Connect to target
    target_conn = psycopg2.connect(target_db_url)
    
    # Write data
    df.to_sql(table_name, target_conn, if_exists='replace', index=False)
    target_conn.close()
    
    return {
        "table": table_name,
        "rows_migrated": len(df),
        "columns": list(df.columns)
    }

result = dx.run(
    migrate_database,
    args=('postgresql://...', 'postgresql://...', 'users'),
    cpu_per_worker=4,
    ram_per_worker=8192
)
```

### Example 4: Text Analysis Pipeline

```javascript
const analyzeDocuments = async (documentUrls) => {
    const axios = require('axios');
    const natural = require('natural');
    const tokenizer = new natural.WordTokenizer();
    const TfIdf = natural.TfIdf;
    
    const documents = [];
    const tfidf = new TfIdf();
    
    // Fetch all documents
    for (const url of documentUrls) {
        const response = await axios.get(url);
        const text = response.data;
        documents.push(text);
        tfidf.addDocument(text);
    }
    
    // Extract keywords for each document
    const results = documents.map((doc, idx) => {
        const tokens = tokenizer.tokenize(doc);
        const keywords = [];
        
        tfidf.listTerms(idx).slice(0, 10).forEach(item => {
            keywords.push({
                term: item.term,
                score: item.tfidf
            });
        });
        
        return {
            url: documentUrls[idx],
            wordCount: tokens.length,
            keywords: keywords
        };
    });
    
    return {
        totalDocuments: documents.length,
        results: results
    };
};

const docs = [
    'https://example.com/doc1.txt',
    'https://example.com/doc2.txt',
    'https://example.com/doc3.txt'
];

dx.run(analyzeDocuments, { args: [docs] });
```

---

## 🎉 Summary

### Key Rules

1. **Everything inside** - Imports, helpers, classes all go INSIDE the function
2. **Pass arguments** - Don't use external variables, pass them as arguments
3. **Return simple data** - Strings, numbers, lists, dicts only
4. **Let SDK handle packages** - It auto-installs what you import

### What Happens Behind the Scenes

```
Your Local Machine          DistributeX Cloud           Remote Worker
─────────────────          ─────────────────          ──────────────

dx.run(my_function)   →    Store function code    →   Download code
       ↓                          ↓                         ↓
Serialize function         Queue for execution        Install packages
       ↓                          ↓                         ↓
Send to API               Assign to worker            Execute function
       ↓                          ↓                         ↓
Wait for result           Monitor progress            Return result
       ↓                          ↓                         ↓
Receive result       ←    Aggregate results      ←    Upload result
```

### Your Code Never Runs Locally!

When you call `dx.run(my_function)`:
1. Function is serialized (converted to text)
2. Sent to DistributeX API
3. Queued for available worker
4. Worker downloads and executes
5. Result sent back to you

**Your machine just submits and receives — all execution is remote!**

---

**Happy cloud computing!** ☁️
