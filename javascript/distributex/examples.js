/**
 * DistributeX JavaScript SDK Examples
 * ====================================
 * Real-world usage examples
 */

const DistributeX = require('./src/index');

// Set your API key
const API_KEY = process.env.DISTRIBUTEX_API_KEY || 'your_api_key_here';

// =============================================================================
// Example 1: Simple Function Execution
// =============================================================================
async function example1_simple() {
  console.log('\n=== Example 1: Simple Function ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  // Define a function to run
  function calculatePrimes(max) {
    const primes = [];
    for (let n = 2; n <= max; n++) {
      let isPrime = true;
      for (let i = 2; i <= Math.sqrt(n); i++) {
        if (n % i === 0) {
          isPrime = false;
          break;
        }
      }
      if (isPrime) primes.push(n);
    }
    return primes;
  }
  
  // Run it on the distributed network
  const result = await dx.run(calculatePrimes, {
    args: [10000],
    cpuPerWorker: 2
  });
  
  console.log(`Found ${result.length} primes`);
}

// =============================================================================
// Example 2: Run Python Script
// =============================================================================
async function example2_python_script() {
  console.log('\n=== Example 2: Python Script ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  const result = await dx.runScript('analysis.py', {
    runtime: 'python',
    workers: 1,
    cpuPerWorker: 4,
    ramPerWorker: 8192,
    inputFiles: ['data.csv'],
    outputFiles: ['results.json']
  });
  
  console.log('Analysis complete!', result);
}

// =============================================================================
// Example 3: Docker Container Execution
// =============================================================================
async function example3_docker() {
  console.log('\n=== Example 3: Docker Container ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  const result = await dx.runDocker('python:3.11', {
    command: 'python -c "import sys; print(sys.version)"',
    cpuPerWorker: 2,
    ramPerWorker: 4096
  });
  
  console.log('Python version:', result);
}

// =============================================================================
// Example 4: GPU-Accelerated Task
// =============================================================================
async function example4_gpu() {
  console.log('\n=== Example 4: GPU Task ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  const result = await dx.runScript('train_model.py', {
    runtime: 'python',
    workers: 1,
    cpuPerWorker: 8,
    ramPerWorker: 16384,
    gpu: true,
    cuda: true,
    timeout: 7200 // 2 hours
  });
  
  console.log('Training complete!', result);
}

// =============================================================================
// Example 5: Parallel Processing
// =============================================================================
async function example5_parallel() {
  console.log('\n=== Example 5: Parallel Processing ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  // Process multiple files in parallel
  const files = ['file1.csv', 'file2.csv', 'file3.csv', 'file4.csv'];
  
  const tasks = files.map(file => 
    dx.runScript('process.py', {
      runtime: 'python',
      workers: 1,
      inputFiles: [file],
      wait: false // Don't wait, submit all at once
    })
  );
  
  console.log(`Submitted ${tasks.length} parallel tasks`);
  
  // Wait for all to complete
  const results = await Promise.all(
    tasks.map(task => dx.waitForCompletion(task.id))
  );
  
  console.log('All tasks complete!', results.length);
}

// =============================================================================
// Example 6: Network Statistics
// =============================================================================
async function example6_stats() {
  console.log('\n=== Example 6: Network Stats ===\n');
  
  const dx = new DistributeX(API_KEY);
  
  const stats = await dx.networkStats();
  
  console.log('Network Statistics:');
  console.log(`  Active Workers: ${stats.activeWorkers}`);
  console.log(`  Total CPU Cores: ${stats.totalCpuCores}`);
  console.log(`  Total RAM: ${Math.floor(stats.totalRam / 1024)} GB`);
  console.log(`  GPUs Available: ${stats.totalGpus}`);
  console.log(`  Active Tasks: ${stats.activeTasks}`);
}

// =============================================================================
// Run Examples
// =============================================================================
async function main() {
  console.log('DistributeX JavaScript SDK Examples');
  console.log('===================================\n');
  
  if (API_KEY === 'your_api_key_here') {
    console.error('❌ Please set DISTRIBUTEX_API_KEY environment variable');
    console.log('\nGet your API key at: https://distributex-cloud-network.pages.dev/auth');
    process.exit(1);
  }
  
  try {
    // Run example 6 (stats) - doesn't require files
    await example6_stats();
    
    console.log('\n✅ Example complete!');
    console.log('\nTo run other examples:');
    console.log('  - Uncomment the example function in main()');
    console.log('  - Make sure you have the required files (for script examples)');
    console.log('\nDocumentation: https://distributex.io/docs');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = {
  example1_simple,
  example2_python_script,
  example3_docker,
  example4_gpu,
  example5_parallel,
  example6_stats
};
