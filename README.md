---

## 📘 How to Use `args=` in DistributeX

This is the **simplest rule** for using `args=`:

---

# ✅ What to Put in `args=`

### **Whatever you normally pass to your function when calling it → put the same values inside `args` as a tuple.**

---

## 🟢 Example 1 — Normal Function Call

If you normally call:

```python
my_function(10, "hello", True)
```

Then with DistributeX:

```python
dx.run(my_function, args=(10, "hello", True))
```

---

## 🔥 One Argument Rule

If your function takes **one argument**, the tuple **must include a comma**:

Normal call:

```python
my_function(5)
```

DistributeX:

```python
dx.run(my_function, args=(5,))
```

✔ `(5,)` is a tuple
❌ `(5)` is NOT a tuple

---

## 🟦 Zero Arguments

If your function requires **no inputs**:

```python
def hello():
    return "hi"
```

Just call:

```python
dx.run(hello)
```

or:

```python
dx.run(hello, args=())
```

---

## 🎯 Summary (Easy to Remember)

### **args = ( everything your function needs, in the same order )**

That’s it!

---
