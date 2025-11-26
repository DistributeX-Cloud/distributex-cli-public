   # DistributeX Worker
   
   Contribute your unused computing resources to the DistributeX network.
   
   ## Quick Start
   
   ### Install via npm
   ```bash
   npm install -g @distributex/worker
   distributex-worker --api-key YOUR_API_KEY
   ```
   
   ### Quick Install Script
   ```bash
   curl -sSL https://distributex.pages.dev/install.sh | bash
   ```
   
   ## What Gets Shared?
   
   - CPU: 30-40% of available cores
   - RAM: 20-30% of free memory
   - GPU: 50% when idle (if available)
   - Storage: 10-20% of free disk space
   
   ## Commands
   
   ```bash
   # Start worker
   distributex-worker --api-key YOUR_KEY
   
   # Check status
   distributex-worker status
   
   # Stop worker
   distributex-worker stop
   
   # View configuration
   distributex-worker config
   ```

Publishing to npm:

1. Create npm account at npmjs.com
2. Login: `npm login`
3. Publish: `npm publish --access public`

Users can then install with:
```bash
npm install -g @distributex/worker
