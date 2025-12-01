# DistributeX Security & Fair Use Guide

## 🔒 Security Architecture

DistributeX implements enterprise-grade security for P2P distributed computing.

### Multi-Layer Security

```
┌─────────────────────────────────────────┐
│  Layer 1: Authentication & Authorization │
│  • JWT tokens                            │
│  • API key validation                    │
│  • Role-based access control             │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Layer 2: Code Verification              │
│  • SHA-256 code hashing                  │
│  • Malware scanning                      │
│  • Vulnerability detection               │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Layer 3: Sandboxed Execution            │
│  • Docker isolation                      │
│  • Network restrictions                  │
│  • Filesystem read-only                  │
│  • Resource limits                       │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Layer 4: Runtime Monitoring             │
│  • Real-time resource tracking           │
│  • Anomaly detection                     │
│  • Automatic termination                 │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│  Layer 5: Audit & Compliance             │
│  • Complete audit logs                   │
│  • Incident reporting                    │
│  • Reputation system                     │
└─────────────────────────────────────────┘
```

---

## 🛡️ Security Levels

Tasks are assigned security levels based on developer reputation:

### Paranoid (Trust Score < 30)
- ✅ Complete network isolation
- ✅ Read-only filesystem
- ✅ Maximum syscall restrictions
- ✅ 10 max processes
- ✅ Continuous monitoring
- ⚠️ Slowest execution

### High (Trust Score 30-60)
- ✅ Network isolation
- ✅ Read-only filesystem
- ✅ Standard syscall restrictions
- ✅ 20 max processes
- ✅ Regular monitoring

### Medium (Trust Score 60-80)
- ✅ Limited network access
- ✅ Partial filesystem access
- ✅ Relaxed restrictions
- ✅ 50 max processes

### Low (Trust Score 80+, Trusted Developers)
- ✅ Full network access
- ✅ Full filesystem access
- ✅ Minimal restrictions
- ✅ 100 max processes

---

## ⚖️ Fair Resource Distribution

### How It Works

DistributeX ensures fair access to computing resources for all developers:

1. **Fair Share Calculation**
   ```
   Fair Share = Total Resources / Active Developers
   ```

2. **Priority Adjustment**
   - Developers using **less than fair share** → **Higher priority**
   - Developers using **more than fair share** → **Lower priority**
   - Tasks waiting **> 30 minutes** → **Automatic boost**

3. **Queue Management**
   ```
   Final Priority = 
     Base Priority (1-10) × 10 +
     Fairness Multiplier × 50 +
     Wait Time Bonus (0-100)
   ```

### Example Scenario

**Network State:**
- Total: 1000 CPU cores
- Active Developers: 10
- Fair Share: 100 cores each

**Developer A:**
- Currently using: 50 cores (50% of fair share)
- Priority Multiplier: **2.0x** ✅ Boosted
- Next task: **High priority**

**Developer B:**
- Currently using: 150 cores (150% of fair share)
- Priority Multiplier: **0.67x** ⚠️ Reduced
- Next task: **Lower priority**

**Result:** Developer A's tasks execute first, ensuring fairness.

---

## 📊 Quotas & Limits

### Daily Quotas (Default)

```yaml
Tasks:       100 tasks/day
CPU Hours:   100 core-hours/day
RAM Hours:   200 GB-hours/day
GPU Hours:   10 GPU-hours/day
```

### Concurrent Limits

Based on **Trust Score**:

| Trust Score | Max Concurrent | Max Workers/Task |
|-------------|----------------|------------------|
| 0-30        | 3 tasks        | 5 workers        |
| 30-60       | 5 tasks        | 10 workers       |
| 60-80       | 10 tasks       | 20 workers       |
| 80-100      | 20 tasks       | 50 workers       |

### Quota Exceeded Response

```json
{
  "error": "Daily Quota Exceeded",
  "usage": {
    "tasksSubmitted": 100,
    "tasksLimit": 100,
    "cpuHoursUsed": 98.5,
    "cpuHoursLimit": 100
  },
  "resetsAt": "2024-01-02T00:00:00Z"
}
```

---

## 🏆 Reputation System

### Trust Score (0-100)

Your trust score determines your limits and security level:

**Starting Score:** 50

**Increases by:**
- ✅ Each successful task: +0.1
- ✅ Every 10 completed tasks: +1
- ✅ Clean record for 30 days: +5
- ✅ Efficient resource usage: +2

**Decreases by:**
- ❌ Failed task: -0.2
- ❌ Every 5 failed tasks: -1
- ❌ Security incident: -10
- ❌ Resource abuse: -20
- ❌ Malware detected: -50 (+ suspension)

### Trusted Developer Status

Achieve **80+ trust score** to become a Trusted Developer:

**Benefits:**
- ✅ Lower security restrictions
- ✅ Higher concurrent limits
- ✅ Priority support
- ✅ Lower transaction fees
- ✅ Custom quotas

---

## 🚨 Security Incidents

### Types of Incidents

1. **Malware Detected**
   - Severity: Critical
   - Action: Immediate termination + suspension
   - Trust Score: -50

2. **Resource Abuse**
   - Severity: High
   - Action: Task termination
   - Trust Score: -20

3. **Unauthorized Access**
   - Severity: High
   - Action: Investigation + possible suspension
   - Trust Score: -30

4. **Network Attack**
   - Severity: Critical
   - Action: Permanent ban
   - Trust Score: -100

### Incident Response

When an incident occurs:

1. ⚡ Automatic detection
2. 🛑 Immediate task termination
3. 🔒 Worker isolation
4. 📧 Developer notification
5. 🔍 Investigation
6. ⚖️ Action taken (warning/suspension/ban)
7. 📝 Audit log entry

---

## 🔐 Data Protection

### For Contributors (Workers)

**Your data is protected:**
- ✅ Tasks run in isolated Docker containers
- ✅ No file system access
- ✅ Network traffic encrypted (HTTPS)
- ✅ No data persistence after task
- ✅ Complete cleanup on exit

**What workers can see:**
- Task metadata (name, type)
- Resource requirements
- Execution logs (sanitized)

**What workers CANNOT see:**
- Developer identity
- Source code (encrypted)
- Input/output data
- Other tasks

### For Developers

**Your code is protected:**
- ✅ Code stored encrypted at rest
- ✅ Transmitted via HTTPS
- ✅ Hashed for integrity (SHA-256)
- ✅ Access-controlled
- ✅ Auto-deleted after 7 days

**Your data is protected:**
- ✅ Input files encrypted
- ✅ Output files encrypted
- ✅ Results accessible only to you
- ✅ No data shared between tasks
- ✅ Complete deletion available

---

## 🛠️ Sandboxing Details

### Docker Isolation

Every task runs in a fresh Docker container:

```dockerfile
# Security Configuration
FROM python:3.11-slim

# Non-root user
USER distributex

# Read-only filesystem
--read-only

# No network (paranoid mode)
--network none

# Resource limits
--cpus="4"
--memory="8g"
--pids-limit=100

# Dropped capabilities
--cap-drop=ALL
```

### System Call Restrictions

**Allowed:**
- read, write, open, close
- stat, fstat, lstat
- getpid, getuid
- Basic math operations

**Blocked:**
- ptrace (debugging)
- mount, umount
- reboot, shutdown
- socket creation (paranoid mode)
- Raw device access

---

## 📋 Compliance

### GDPR Compliance

- ✅ Data minimization
- ✅ Right to erasure
- ✅ Data portability
- ✅ Breach notification
- ✅ Privacy by design

### SOC 2 Type II

- ✅ Access controls
- ✅ Encryption in transit
- ✅ Encryption at rest
- ✅ Audit logging
- ✅ Incident response

---

## 🔍 Monitoring & Auditing

### Real-Time Monitoring

System monitors:
- CPU/RAM/GPU usage per task
- Network traffic patterns
- Filesystem access attempts
- Process creation
- Syscall patterns

### Audit Logs

Every action is logged:

```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "action": "task_created",
  "actor": "developer-abc",
  "entity": "task-xyz",
  "details": {
    "cpuRequired": 4,
    "securityLevel": "high"
  },
  "ipAddress": "1.2.3.4"
}
```

**Retention:** 90 days minimum

---

## ⚠️ Best Practices

### For Developers

1. **Start Small**
   - Test with 1 worker before scaling
   - Verify output is correct

2. **Estimate Resources**
   - Don't over-allocate
   - Use only what you need

3. **Handle Errors**
   - Implement retries
   - Validate results

4. **Secure Your API Key**
   - Never commit to git
   - Use environment variables
   - Rotate regularly

5. **Monitor Your Tasks**
   - Check logs regularly
   - Watch for failures
   - Optimize code

### For Contributors

1. **Keep Docker Updated**
   - Latest security patches
   - Stable releases only

2. **Monitor Resource Usage**
   - Watch CPU/RAM/disk
   - Ensure headroom

3. **Report Issues**
   - Suspicious tasks
   - System problems
   - Security concerns

4. **Maintain Uptime**
   - Stable internet connection
   - Reliable power
   - Regular maintenance

---

## 🆘 Security FAQs

**Q: Can tasks access my files?**
A: No. Tasks run in isolated Docker containers with no access to your filesystem.

**Q: Can tasks use my network?**
A: Only if security level allows. Paranoid mode = no network access.

**Q: What happens if I submit malware?**
A: Automatic detection → termination → suspension → possible ban.

**Q: Can other developers see my tasks?**
A: No. All tasks are private and isolated.

**Q: How do I increase my trust score?**
A: Submit successful tasks, maintain clean record, use resources efficiently.

**Q: Can I opt out of certain task types?**
A: Yes. Configure allowed task types in worker settings.

---

---

**Last Updated:** Dec 2025
**Version:** 2.0.0
