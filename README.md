---

# 🚀 DistributeX — Official Usage Guide

Powerful distributed execution for Python & JavaScript

---

# 📦 Installation

## 🐍 Python

```bash
pip install distributex-cloud
```

**Import + initialize:**

```python
from distributex import DistributeX
dx = DistributeX(api_key="your_api_key_here")
```

---

## 🟦 JavaScript / Node.js

```bash
npm install distributex-cloud
```

**Import + initialize:**

```javascript
import { DistributeX } from "distributex-cloud";

const dx = new DistributeX({
  apiKey: "your_api_key_here"
});
```

---

# 🎯 Using `args=` (Python + JavaScript)

This is the **golden rule**:

> **Whatever you normally pass to your function when calling it → put the same values inside `args`, in the same order.**

---

## 🐍 Python `args=` Examples

### Normal call:

```python
my_function(10, "hello")
```

DistributeX:

```python
dx.run(my_function, args=(10, "hello"))
```

### One argument (MUST include comma!)

```python
dx.run(my_function, args=(5,))
```

### No arguments

```python
dx.run(my_function)
```

---

## 🟦 JavaScript `args=` Examples

### Normal call:

```javascript
myFunction(10, "hello");
```

DistributeX:

```javascript
dx.run(myFunction, { args: [10, "hello"] });
```

### One argument

```javascript
dx.run(myFunction, { args: [5] });
```

### No arguments

```javascript
dx.run(myFunction);
```

---

# 🐍 Python — Full Math Engine Example

```python
from distributex import DistributeX

dx = DistributeX(api_key="your_api_key")

def math_engine(script: str):
    import math

    env = {
        name: getattr(math, name)
        for name in dir(math)
        if not name.startswith("_")
    }

    env.update({
        "abs": abs,
        "round": round,
        "min": min,
        "max": max,
        "pow": pow,
    })

    local_vars = {}

    def eval_expr(expr):
        try:
            return eval(expr, {"__builtins__": {}}, {**env, **local_vars})
        except Exception as e:
            return f"Error in '{expr}': {str(e)}"

    results = []
    lines = script.strip().splitlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        if "=" in line and "(" in line.split("=")[0]:
            name, expr = line.split("=", 1)
            fname = name[:name.index("(")].strip()
            args = name[name.index("(")+1:name.index(")")].strip().split(",")

            def make_func(expr, args):
                return lambda *vals: eval_expr(
                    expr.replace(
                        args[0].strip(), str(vals[0])
                    ) if len(args) == 1 else expr
                )

            local_vars[fname] = make_func(expr.strip(), args)
            results.append(f"Defined function '{fname}'")
            continue

        if "=" in line:
            var, expr = line.split("=", 1)
            var = var.strip()
            val = eval_expr(expr.strip())
            local_vars[var] = val
            results.append(f"{var} = {val}")
            continue

        val = eval_expr(line)
        results.append(val)

    return results


script = """
# define variables
a = 25
b = sqrt(a) * 10
c = sin(b) + cos(a)

# define custom function
f(x) = x*2 + sqrt(x)

# compute results
f(a)
f(b)
c + f(a) - f(b) + pow(a, 3)
"""

result = dx.run(math_engine, args=(script,))
print(result)
```

---

# 🔧 JavaScript — Equivalent Basic Example

```javascript
const DistributeX = require("distributex-cloud");

const dx = new DistributeX("YOUR_API_KEY");

const worker = (script) => {
  return {
    received: script,
    length: script.length
  };
};

(async () => {
  const result = await dx.run(worker, { args: ["hello world"] });
  console.log(result);
})();
```

---

# 🏗 Python Classes & Methods Inside One Worker

**IMPORTANT:** DistributeX executes *only the single worker function*.
So your classes must be **inside** it.

---

## ✔ Correct (class inside worker)

```python
def worker(a, b):

    class Calculator:
        def __init__(self, x, y):
            self.x = x
            self.y = y

        def add(self):
            return self.x + self.y

        def multiply(self):
            return self.x * self.y

    calc = Calculator(a, b)

    return {
        "sum": calc.add(),
        "product": calc.multiply()
    }

dx.run(worker, args=(5, 7))
```

---

## ❌ Incorrect (class outside worker)

```python
class Calculator: ...
def worker(a,b):
    return Calculator(a,b).add()   # 🚫 remote node doesn't have class
```

---

# 🧱 Multiple Classes & Helpers (Inside Worker)

```python
def worker(text):

    class Cleaner:
        def clean(self, t):
            return t.strip().lower()

    class Analyzer:
        def length(self, t):
            return len(t)

    cleaner = Cleaner()
    analyzer = Analyzer()

    cleaned = cleaner.clean(text)
    size = analyzer.length(cleaned)

    return {"cleaned": cleaned, "size": size}
```

---

# 🧠 Summary Cheat Sheet

### 💡 Python

* `args=(value,)` for a single argument
* All classes & helpers must be inside the worker function
* The worker is self-contained and sent as executable code

### 💡 JavaScript

* `args: [value]`
* Wrap your logic inside the function you pass to `dx.run()`
* Returned values are JSON-serializable

---
