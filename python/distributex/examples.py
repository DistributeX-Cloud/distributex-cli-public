"""
DistributeX Python SDK Examples
================================
Real-world usage examples for the distributed computing platform
"""

from distributex import DistributeX
import os

# Set your API key
# Get it from: https://distributex-cloud-network.pages.dev/auth
API_KEY = os.getenv("DISTRIBUTEX_API_KEY", "your_api_key_here")


# =============================================================================
# Example 1: AI Model Training
# =============================================================================

def example_ai_training():
    """Train ML model on distributed GPUs"""
    dx = DistributeX(api_key=API_KEY)
    
    def train_model(data, epochs=10, learning_rate=0.001):
        import torch
        import torch.nn as nn
        
        model = nn.Sequential(
            nn.Linear(784, 128),
            nn.ReLU(),
            nn.Linear(128, 10)
        )
        
        optimizer = torch.optim.Adam(model.parameters(), lr=learning_rate)
        criterion = nn.CrossEntropyLoss()
        
        for epoch in range(epochs):
            # Training loop
            pass
        
        return model.state_dict()
    
    # Run on 4 GPU workers
    result = dx.run(
        train_model,
        args=(training_data,),
        kwargs={'epochs': 20, 'learning_rate': 0.001},
        workers=4,
        gpu=True,
        cuda=True,
        ram_per_worker=16384
    )
    
    print("✅ Training complete!")
    return result


# =============================================================================
# Example 2: Video Processing
# =============================================================================

def example_video_processing():
    """Process videos in parallel"""
    dx = DistributeX(api_key=API_KEY)
    
    result = dx.run_script(
        "process_video.py",
        workers=8,
        cpu_per_worker=4,
        gpu=True,
        input_files=["videos/*.mp4"],
        output_files=["output/", "thumbnails/"],
        timeout=7200
    )
    
    print("✅ Video processing complete!")
    return result


# =============================================================================
# Example 3: Data Analysis
# =============================================================================

def example_data_analysis():
    """Analyze large dataset"""
    dx = DistributeX(api_key=API_KEY)
    
    def analyze_chunk(data):
        import pandas as pd
        
        df = pd.DataFrame(data)
        return {
            'mean': df.mean().to_dict(),
            'std': df.std().to_dict(),
            'corr': df.corr().to_dict()
        }
    
    # Process chunks in parallel
    results = []
    for chunk in data_chunks:
        task = dx.run(
            analyze_chunk,
            args=(chunk,),
            workers=1,
            cpu_per_worker=8,
            ram_per_worker=8192,
            wait=False
        )
        results.append(task)
    
    # Collect results
    final = [dx.get_result(t.id) for t in results]
    print("✅ Analysis complete!")
    return final


# =============================================================================
# Example 4: Docker Container
# =============================================================================

def example_docker():
    """Run TensorFlow in Docker"""
    dx = DistributeX(api_key=API_KEY)
    
    result = dx.run_docker(
        image="tensorflow/tensorflow:latest-gpu",
        command="python /workspace/train.py",
        workers=2,
        cpu_per_worker=8,
        ram_per_worker=32768,
        gpu=True,
        volumes={
            "/local/data": "/workspace/data",
            "/local/checkpoints": "/workspace/checkpoints"
        },
        env={
            'BATCH_SIZE': '64',
            'LEARNING_RATE': '0.001'
        }
    )
    
    print("✅ Docker training complete!")
    return result


# =============================================================================
# Example 5: Quick Start
# =============================================================================

def example_quick_start():
    """Simplest possible example"""
    dx = DistributeX(api_key=API_KEY)
    
    # Define any Python function
    def calculate_sum(n):
        return sum(range(n))
    
    # Run it distributed!
    result = dx.run(calculate_sum, args=(1000000,), cpu_per_worker=4)
    
    print(f"Result: {result}")
    return result


# =============================================================================
# Example 6: Network Statistics
# =============================================================================

def example_network_stats():
    """Get current network stats"""
    dx = DistributeX(api_key=API_KEY)
    
    stats = dx.network_stats()
    
    print("\n🌍 Network Statistics:")
    print(f"   Active Workers: {stats.get('activeWorkers', 0)}")
    print(f"   Total CPU Cores: {stats.get('totalCpuCores', 0)}")
    print(f"   Total RAM: {stats.get('totalRam', 0) / 1024:.0f} GB")
    print(f"   GPUs Available: {stats.get('totalGpus', 0)}")
    print(f"   Active Tasks: {stats.get('activeTasks', 0)}")
    
    return stats


if __name__ == "__main__":
    print("DistributeX Python SDK Examples")
    print("=" * 50)
    
    # Run examples
    print("\n1. Quick Start Example:")
    example_quick_start()
    
    print("\n2. Network Statistics:")
    example_network_stats()
    
    print("\n✅ Examples complete!")
    print("\nTo run other examples:")
    print("  - example_ai_training()")
    print("  - example_video_processing()")
    print("  - example_data_analysis()")
    print("  - example_docker()")
