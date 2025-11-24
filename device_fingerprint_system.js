// Device Fingerprinting System for DistributeX
// Generates unique device IDs based on hardware characteristics

const crypto = require('crypto');
const os = require('os');
const { execSync } = require('child_process');

class DeviceFingerprint {
  /**
   * Generate a unique device fingerprint based on hardware characteristics
   * This fingerprint will be consistent across restarts but unique per device
   */
  static async generate() {
    const components = [];
    
    // 1. CPU Information
    try {
      const cpus = os.cpus();
      if (cpus.length > 0) {
        // Use CPU model and core count
        components.push(`cpu:${cpus[0].model}:${cpus.length}`);
      }
    } catch (e) {
      console.warn('Could not get CPU info');
    }
    
    // 2. Total Memory (unique per device)
    try {
      const totalMemory = os.totalmem();
      components.push(`mem:${totalMemory}`);
    } catch (e) {
      console.warn('Could not get memory info');
    }
    
    // 3. Platform and Architecture
    components.push(`platform:${os.platform()}`);
    components.push(`arch:${os.arch()}`);
    
    // 4. Machine ID (most reliable for Linux/Mac)
    try {
      let machineId = null;
      
      if (os.platform() === 'linux') {
        // Try /etc/machine-id first (systemd)
        try {
          machineId = execSync('cat /etc/machine-id', { 
            encoding: 'utf8', 
            stdio: ['pipe', 'pipe', 'ignore'] 
          }).trim();
        } catch (e) {
          // Try /var/lib/dbus/machine-id (older systems)
          try {
            machineId = execSync('cat /var/lib/dbus/machine-id', { 
              encoding: 'utf8', 
              stdio: ['pipe', 'pipe', 'ignore'] 
            }).trim();
          } catch (e2) {
            // Try dmidecode for hardware UUID
            try {
              machineId = execSync('dmidecode -s system-uuid', { 
                encoding: 'utf8', 
                stdio: ['pipe', 'pipe', 'ignore'] 
              }).trim();
            } catch (e3) {
              // Ignore
            }
          }
        }
      } else if (os.platform() === 'darwin') {
        // macOS: Use hardware UUID
        try {
          machineId = execSync('ioreg -rd1 -c IOPlatformExpertDevice | grep IOPlatformUUID', { 
            encoding: 'utf8', 
            stdio: ['pipe', 'pipe', 'ignore'] 
          }).split('=')[1].trim().replace(/"/g, '');
        } catch (e) {
          // Ignore
        }
      } else if (os.platform() === 'win32') {
        // Windows: Use WMIC to get UUID
        try {
          machineId = execSync('wmic csproduct get UUID', { 
            encoding: 'utf8', 
            stdio: ['pipe', 'pipe', 'ignore'] 
          }).split('\n')[1].trim();
        } catch (e) {
          // Ignore
        }
      }
      
      if (machineId && machineId.length > 0) {
        components.push(`machine:${machineId}`);
      }
    } catch (e) {
      console.warn('Could not get machine ID');
    }
    
    // 5. Hostname (fallback if no machine ID)
    try {
      const hostname = os.hostname();
      if (hostname) {
        components.push(`hostname:${hostname}`);
      }
    } catch (e) {
      console.warn('Could not get hostname');
    }
    
    // 6. Network interfaces MAC addresses (unique per device)
    try {
      const interfaces = os.networkInterfaces();
      const macAddresses = [];
      
      for (const [name, addrs] of Object.entries(interfaces)) {
        if (addrs) {
          for (const addr of addrs) {
            if (addr.mac && addr.mac !== '00:00:00:00:00:00' && !addr.internal) {
              macAddresses.push(addr.mac);
            }
          }
        }
      }
      
      if (macAddresses.length > 0) {
        // Sort to ensure consistency
        macAddresses.sort();
        components.push(`mac:${macAddresses.join(',')}`);
      }
    } catch (e) {
      console.warn('Could not get network interfaces');
    }
    
    // Create fingerprint hash
    const fingerprintString = components.join('|');
    const hash = crypto.createHash('sha256').update(fingerprintString).digest('hex');
    
    return {
      deviceId: `device-${hash.substring(0, 32)}`,
      fingerprint: hash,
      components: components,
      generatedAt: new Date().toISOString()
    };
  }
  
  /**
   * Generate a worker ID that's unique per device per account
   * Format: worker-{userId-hash}-{device-hash}
   */
  static generateWorkerId(userId, deviceFingerprint) {
    const userHash = crypto.createHash('sha256').update(userId).digest('hex').substring(0, 8);
    const deviceHash = deviceFingerprint.substring(0, 16);
    return `worker-${userHash}-${deviceHash}`;
  }
}

module.exports = DeviceFingerprint;
