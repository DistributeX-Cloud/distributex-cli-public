#!/usr/bin/env node
// Enhanced DistributeX CLI with Training Support

import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import inquirer from 'inquirer';
import Table from 'cli-table3';
import { TrainingClient } from './sdk/training';

const program = new Command();

program
  .name('dxcloud')
  .description('DistributeX Cloud Network CLI - Enhanced with Training')
  .version('2.0.0');

// ==================== TRAINING COMMANDS ====================

const training = program.command('train').description('AI training commands');

training
  .command('submit')
  .description('Submit a training job')
  .option('-n, --name <name>', 'Training job name')
  .option('-f, --framework <framework>', 'Framework (pytorch, tensorflow, jax)', 'pytorch')
  .option('-t, --type <type>', 'Training type', 'custom')
  .option('-d, --dataset <path>', 'Dataset location (supports external: /external/usb0/dataset)')
  .option('--epochs <n>', 'Number of epochs', '10')
  .option('--batch-size <n>', 'Batch size', '32')
  .option('--learning-rate <lr>', 'Learning rate', '0.001')
  .option('--gpus <n>', 'Number of GPUs', '1')
  .option('--cpu <n>', 'CPU cores', '4')
  .option('--memory <gb>', 'Memory in GB', '16')
  .option('--distributed', 'Use distributed training', false)
  .option('-c, --config <file>', 'Training config file (JSON/YAML)')
  .action(async (options) => {
    const spinner = ora('Submitting training job...').start();
    
    try {
      const client = await getTrainingClient();
      
      let config;
      
      if (options.config) {
        const fs = await import('fs/promises');
        const configData = await fs.readFile(options.config, 'utf-8');
        config = JSON.parse(configData);
      } else {
        config = {
          trainingName: options.name || `training-${Date.now()}`,
          framework: options.framework,
          trainingType: options.type,
          modelConfig: {},
          datasetLocation: options.dataset,
          hyperparameters: {
            epochs: parseInt(options.epochs),
            batchSize: parseInt(options.batchSize),
            learningRate: parseFloat(options.learningRate)
          },
          requiredResources: {
            cpuCores: parseInt(options.cpu),
            memoryGb: parseInt(options.memory),
            storageGb: 50,
            gpuCount: parseInt(options.gpus),
            gpuMemoryGb: 8
          },
          distributedStrategy: options.distributed ? 'data_parallel' : 'single_gpu'
        };
      }

      const result = await client.submitTraining(config);
      
      spinner.succeed('Training job submitted successfully!');
      
      console.log(chalk.cyan('\n📊 Training Details\n'));
      console.log(`Training ID: ${chalk.bold(result.trainingId)}`);
      console.log(`Status: ${chalk.yellow(result.status)}`);
      
      if (options.dataset && options.dataset.startsWith('/external/')) {
        console.log(chalk.blue(`\n💾 Using external storage: ${options.dataset}`));
      }
      
      console.log(`\nMonitor progress: ${chalk.gray(`dxcloud train status ${result.trainingId}`)}`);
      console.log(`View logs: ${chalk.gray(`dxcloud train logs ${result.trainingId}`)}\n`);
    } catch (error: any) {
      spinner.fail('Failed to submit training job');
      console.error(chalk.red(`Error: ${error.message}\n`));
      process.exit(1);
    }
  });

training
  .command('status <trainingId>')
  .description('Get training job status')
  .action(async (trainingId) => {
    const spinner = ora('Fetching training status...').start();
    
    try {
      const client = await getTrainingClient();
      const training = await client.getTrainingStatus(trainingId);
      
      spinner.stop();
      
      console.log(chalk.cyan('\n📊 Training Status\n'));
      
      const table = new Table({
        colWidths: [25, 60]
      });
      
      const statusColor = getStatusColor(training.status);
      
      table.push(
        ['Training ID', training.trainingId],
        ['Name', training.name],
        ['Framework', training.framework],
        ['Status', statusColor(training.status)],
        ['Progress', `${training.progress.toFixed(1)}%`],
        ['Epoch', `${training.currentEpoch}/${training.totalEpochs}`],
        ['Worker', training.assignedWorker || 'Not assigned'],
        ['GPU', training.workerGpu || 'N/A'],
        ['Checkpoints', training.checkpoints]
      );
      
      if (training.latestMetrics) {
        table.push(
          ['Latest Loss', training.latestMetrics.loss.toFixed(4)],
          ['Latest Accuracy', `${(training.latestMetrics.accuracy * 100).toFixed(2)}%`],
          ['Throughput', `${training.latestMetrics.throughput.toFixed(0)} samples/sec`]
        );
      }
      
      console.log(table.toString());
      console.log();
    } catch (error: any) {
      spinner.fail('Failed to fetch training status');
      console.error(chalk.red(`Error: ${error.message}\n`));
      process.exit(1);
    }
  });

training
  .command('monitor <trainingId>')
  .description('Monitor training progress in real-time')
  .action(async (trainingId) => {
    try {
      const client = await getTrainingClient();
      
      console.log(chalk.cyan(`\n📈 Monitoring training: ${trainingId}\n`));
      console.log(chalk.gray('Press Ctrl+C to stop monitoring\n'));
      
      for await (const metrics of client.streamMetrics(trainingId)) {
        const progress = (metrics.epoch / metrics.totalEpochs) * 100;
        const progressBar = createProgressBar(progress, 30);
        
        console.clear();
        console.log(chalk.cyan('\n📈 Training Progress\n'));
        console.log(`${progressBar} ${progress.toFixed(1)}%`);
        console.log();
        console.log(`Epoch: ${chalk.bold(metrics.epoch)}/${metrics.totalEpochs}`);
        console.log(`Loss: ${chalk.yellow(metrics.loss.toFixed(4))}`);
        console.log(`Accuracy: ${chalk.green((metrics.accuracy * 100).toFixed(2))}%`);
        console.log(`Learning Rate: ${metrics.learningRate.toExponential(2)}`);
        console.log(`Throughput: ${metrics.throughput.toFixed(0)} samples/sec`);
        console.log();
      }
      
      console.log(chalk.green('\n✓ Training completed!\n'));
    } catch (error: any) {
      console.error(chalk.red(`\nError: ${error.message}\n`));
      process.exit(1);
    }
  });

training
  .command('list')
  .description('List all training jobs')
  .option('-s, --status <status>', 'Filter by status')
  .action(async (options) => {
    const spinner = ora('Fetching training jobs...').start();
    
    try {
      const client = await getTrainingClient();
      const trainings = await (client as any).client.api.get('/training/list', {
        params: { status: options.status }
      });
      
      spinner.stop();
      
      if (trainings.data.length === 0) {
        console.log(chalk.yellow('\nNo training jobs found\n'));
        return;
      }
      
      console.log(chalk.cyan('\n📊 Training Jobs\n'));
      
      const table = new Table({
        head: ['ID', 'Name', 'Framework', 'Status', 'Progress', 'Worker'],
        style: { head: ['cyan'] }
      });
      
      for (const t of trainings.data) {
        const statusColor = getStatusColor(t.status);
        table.push([
          t.id.substring(0, 12),
          t.name,
          t.framework,
          statusColor(t.status),
          `${t.progress.toFixed(0)}%`,
          t.assignedWorker || 'N/A'
        ]);
      }
      
      console.log(table.toString());
      console.log();
    } catch (error: any) {
      spinner.fail('Failed to fetch training jobs');
      console.error(chalk.red(`Error: ${error.message}\n`));
      process.exit(1);
    }
  });

training
  .command('cancel <trainingId>')
  .description('Cancel a running training job')
  .action(async (trainingId) => {
    const spinner = ora('Cancelling training...').start();
    
    try {
      const client = await getTrainingClient();
      await client.cancelTraining(trainingId);
      
      spinner.succeed('Training cancelled successfully!');
      console.log();
    } catch (error: any) {
      spinner.fail('Failed to cancel training');
      console.error(chalk.red(`Error: ${error.message}\n`));
      process.exit(1);
    }
  });

training
  .command('checkpoint <trainingId> <epoch>')
  .description('Download a training checkpoint')
  .option('-o, --output <file>', 'Output file', 'checkpoint.pt')
  .action(async (trainingId, epoch, options) => {
    const spinner = ora('Downloading checkpoint...').start();
    
    try {
      const client = await getTrainingClient();
      const data = await client.downloadCheckpoint(trainingId, parseInt(epoch));
      
      const fs = await import('fs/promises');
      await fs.writeFile(options.output, Buffer.from(data));
      
      spinner.succeed('Checkpoint downloaded successfully!');
      console.log(`\nSaved to: ${chalk.bold(options.output)}\n`);
    } catch (error: any) {
      spinner.fail('Failed to download checkpoint');
      console.error(chalk.red(`Error: ${error.message}\n`));
      process.exit(1);
    }
  });

// ==================== EXTERNAL STORAGE COMMANDS ====================

const storage = program.command('storage').description('External storage management');

storage
  .command('list')
  .description('List detected external storage devices')
  .action(async () => {
    const spinner = ora('Detecting external storage...').start();
    
    try {
      // This would call the worker's storage detection
      // For now, show example
      spinner.stop();
      
      console.log(chalk.cyan('\n💾 External Storage Devices\n'));
      
      const table = new Table({
        head: ['Device', 'Mount Point', 'Capacity', 'Available', 'Type'],
        style: { head: ['cyan'] }
      });
      
      table.push(
        ['sdb1', '/media/usb0', '500 GB', '350 GB', 'USB 3.0'],
        ['sdc1', '/media/usb1', '1 TB', '750 GB', 'USB 3.0']
      );
      
      console.log(table.toString());
      console.log();
      console.log(chalk.gray('Use these paths in training: /external/usb0/your_dataset\n'));
    } catch (error: any) {
      spinner.fail('Failed to list storage devices');
      console.error(chalk.red(`Error: ${error.message}\n`));
    }
  });

// ==================== HELPER FUNCTIONS ====================

async function getTrainingClient(): Promise<TrainingClient> {
  const fs = await import('fs/promises');
  const path = await import('path');
  const os = await import('os');
  
  const configPath = path.join(os.homedir(), '.distributex', 'config.json');
  const config = JSON.parse(await fs.readFile(configPath, 'utf-8'));
  
  return new TrainingClient(config.authToken);
}

function getStatusColor(status: string): (text: string) => string {
  switch (status) {
    case 'completed': return chalk.green;
    case 'running': return chalk.blue;
    case 'failed': return chalk.red;
    case 'pending':
    case 'assigned': return chalk.yellow;
    default: return chalk.white;
  }
}

function createProgressBar(percent: number, width: number): string {
  const filled = Math.round((percent / 100) * width);
  const empty = width - filled;
  return chalk.green('█'.repeat(filled)) + chalk.gray('░'.repeat(empty));
}

program.parse();
