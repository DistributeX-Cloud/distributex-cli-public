# DistributeX Cloud Network 🚀

> **Free, open-source distributed computing platform**  
> Share your unused computing resources or run your code on a global pool of CPU, RAM, GPU, and Storage.

## 🎯 Two Ways to Use DistributeX

### 1️⃣ **For Contributors** (Share Your Resources)
Get your idle computer working for you! Contribute CPU, RAM, GPU, or storage and support developers worldwide.

### 2️⃣ **For Developers** (Use the Resource Pool)
Run your scripts, train ML models, process data, or render videos using pooled resources from thousands of devices.

---

## 🚀 Quick Start

### For Contributors (Share Resources)

#### One-Command Install:
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
