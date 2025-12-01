"""
DistributeX Python SDK
======================
Easy integration for developers to use the distributed computing pool

Installation:
    pip install distributex
    
    Or directly:
    curl -sSL https://raw.githubusercontent.com/DistributeX-Cloud/distributex-cli-public/main/python/distributex/client.py -o distributex.py

Usage:
    from distributex import DistributeX
    
    dx = DistributeX(api_key="your_api_key")
    result = dx.run(my_function, args=(data,), workers=4, gpu=True)
"""

import os
import json
import time
import requests
import tarfile
import tempfile
import pickle
import inspect
import hashlib
import base64
from pathlib import Path
from typing import Any, Callable, Optional, List, Dict
from dataclasses import dataclass

__version__ = "1.0.0"
__author__ = "DistributeX Team"

@dataclass
class Task:
    """Represents a distributed task"""
    id: str
    status: str
    progress: float = 0.0
    result: Any = None
    error: Optional[str] = None


class DistributeX:
    """Main SDK class for distributed computing"""
    
    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: str = "https://distributex-cloud-network.pages.dev"
    ):
        """
        Initialize DistributeX client
        
        Args:
            api_key: Your API key (or set DISTRIBUTEX_API_KEY env var)
            base_url: API base URL (default: production)
        """
        self.api_key = api_key or os.getenv("DISTRIBUTEX_API_KEY")
        if not self.api_key:
            raise ValueError(
                "API key required. Set DISTRIBUTEX_API_KEY environment variable "
                "or pass api_key parameter.\n"
                "Get your API key at: https://distributex-cloud-network.pages.dev/auth"
            )
        
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "User-Agent": f"DistributeX-Python-SDK/{__version__}"
        })
    
    def run(
        self,
        func: Callable,
        args: tuple = (),
        kwargs: dict = None,
        workers: int = 1,
        cpu_per_worker: int = 2,
        ram_per_worker: int = 2048,
        gpu: bool = False,
        cuda: bool = False,
        timeout: int = 3600,
        wait: bool = True
    ) -> Any:
        """
        Run a Python function on the distributed network
        
        Args:
            func: Python function to execute
            args: Positional arguments for the function
            kwargs: Keyword arguments for the function
            workers: Number of parallel workers
            cpu_per_worker: CPU cores per worker
            ram_per_worker: RAM in MB per worker
            gpu: Require GPU
            cuda: Require CUDA
            timeout: Timeout in seconds
            wait: Wait for completion (default True)
        
        Returns:
            Function result if wait=True, else Task object
        
        Example:
            def train_model(data, epochs=10):
                # Your training code
                return model
            
            model = dx.run(train_model, args=(data,), kwargs={'epochs': 20}, gpu=True)
        """
        kwargs = kwargs or {}
        
        print("📦 Packaging function...")
        code_url = self._package_function(func, args, kwargs)
        
        print(f"🚀 Submitting to {workers} worker(s)...")
        task = self._submit_task(
            code_url=code_url,
            runtime='python',
            workers=workers,
            cpu_per_worker=cpu_per_worker,
            ram_per_worker=ram_per_worker,
            gpu=gpu,
            cuda=cuda,
            timeout=timeout
        )
        
        if not wait:
            return task
        
        print("⏳ Waiting for execution...")
        return self._wait_and_get_result(task.id)
    
    def run_script(
        self,
        script_path: str,
        command: Optional[str] = None,
        runtime: str = 'auto',
        workers: int = 1,
        cpu_per_worker: int = 2,
        ram_per_worker: int = 2048,
        gpu: bool = False,
        cuda: bool = False,
        input_files: List[str] = None,
        output_files: List[str] = None,
        env: Dict[str, str] = None,
        timeout: int = 3600,
        wait: bool = True
    ) -> Any:
        """
        Run any script file (Python, Node.js, Ruby, Go, Rust, etc.)
        
        Args:
            script_path: Path to script file
            command: Custom command (optional)
            runtime: Runtime (auto-detected from extension)
            workers: Number of parallel workers
            cpu_per_worker: CPU cores per worker
            ram_per_worker: RAM in MB per worker
            gpu: Require GPU
            cuda: Require CUDA
            input_files: Additional input files to upload
            output_files: Output file paths to collect
            env: Environment variables
            timeout: Timeout in seconds
            wait: Wait for completion
        
        Returns:
            Script output if wait=True, else Task object
        
        Example:
            # Python script with GPU
            result = dx.run_script("train.py", gpu=True, workers=2)
            
            # Node.js script
            result = dx.run_script("process.js", ram_per_worker=4096)
            
            # Custom command
            result = dx.run_script("main.go", command="go run main.go")
        """
        input_files = input_files or []
        output_files = output_files or []
        env = env or {}
        
        # Auto-detect runtime
        if runtime == 'auto':
            ext = Path(script_path).suffix.lower()
            runtime_map = {
                '.py': 'python',
                '.js': 'node',
                '.ts': 'node',
                '.rb': 'ruby',
                '.go': 'go',
                '.rs': 'rust',
                '.java': 'java',
                '.cpp': 'cpp',
                '.c': 'c',
                '.sh': 'bash'
            }
            runtime = runtime_map.get(ext, 'bash')
        
        print(f"📦 Uploading {script_path}...")
        code_url = self._upload_file(script_path)
        
        # Upload input files
        input_urls = []
        for input_file in input_files:
            print(f"📤 Uploading input: {input_file}")
            url = self._upload_file(input_file)
            input_urls.append({'path': input_file, 'url': url})
        
        print(f"🚀 Submitting {runtime} script...")
        task = self._submit_task(
            code_url=code_url,
            runtime=runtime,
            command=command,
            workers=workers,
            cpu_per_worker=cpu_per_worker,
            ram_per_worker=ram_per_worker,
            gpu=gpu,
            cuda=cuda,
            input_files=input_urls,
            output_files=output_files,
            env=env,
            timeout=timeout
        )
        
        if not wait:
            return task
        
        print("⏳ Executing...")
        return self._wait_and_get_result(task.id)
    
    def run_docker(
        self,
        image: str,
        command: Optional[str] = None,
        workers: int = 1,
        cpu_per_worker: int = 2,
        ram_per_worker: int = 2048,
        gpu: bool = False,
        volumes: Dict[str, str] = None,
        env: Dict[str, str] = None,
        ports: Dict[int, int] = None,
        timeout: int = 3600,
        wait: bool = True
    ) -> Any:
        """
        Run a Docker container on the network
        
        Args:
            image: Docker image name
            command: Command to run in container
            workers: Number of parallel workers
            cpu_per_worker: CPU cores per worker
            ram_per_worker: RAM in MB per worker
            gpu: Require GPU
            volumes: Volume mappings {host: container}
            env: Environment variables
            ports: Port mappings {host: container}
            timeout: Timeout in seconds
            wait: Wait for completion
        
        Returns:
            Container output if wait=True, else Task object
        
        Example:
            # TensorFlow training
            result = dx.run_docker(
                image="tensorflow/tensorflow:latest-gpu",
                command="python train.py",
                gpu=True,
                volumes={"/data": "/workspace/data"}
            )
        """
        volumes = volumes or {}
        env = env or {}
        ports = ports or {}
        
        print(f"🐳 Submitting Docker task: {image}")
        
        response = self.session.post(
            f"{self.base_url}/api/tasks/execute",
            json={
                "name": f"Docker: {image}",
                "taskType": "docker_execution",
                "dockerImage": image,
                "dockerCommand": command,
                "workers": workers,
                "cpuPerWorker": cpu_per_worker,
                "ramPerWorker": ram_per_worker,
                "gpuRequired": gpu,
                "volumes": volumes,
                "environment": env,
                "ports": ports,
                "timeout": timeout
            }
        )
        response.raise_for_status()
        
        data = response.json()
        task = Task(id=data['id'], status=data['status'])
        
        print(f"✅ Task submitted: {task.id}")
        
        if not wait:
            return task
        
        print("⏳ Executing Docker container...")
        return self._wait_and_get_result(task.id)
    
    def get_task(self, task_id: str) -> Task:
        """Get task status and info"""
        response = self.session.get(f"{self.base_url}/api/tasks/{task_id}")
        response.raise_for_status()
        data = response.json()
        
        return Task(
            id=data['id'],
            status=data['status'],
            progress=data.get('progressPercent', 0),
            error=data.get('errorMessage')
        )
    
	def get_result(self, task_id: str) -> Any:
	    """Download and return task result"""
	    task = self.get_task(task_id)
	    
	    if task.status != 'completed':
	        raise ValueError(f"Task not completed. Status: {task.status}")
	    
	    # Use NEW result endpoint
	    response = self.session.get(f"{self.base_url}/api/tasks/{task_id}/result")
	    
	    # Handle redirects (if result is in file storage)
	    if response.status_code == 302:
	        redirect_url = response.headers.get('Location')
	        response = self.session.get(redirect_url)
	    
	    response.raise_for_status()
	    
	    # Check content type
	    content_type = response.headers.get('content-type', '')
	    
	    # If JSON response (small result stored in DB)
	    if 'application/json' in content_type:
	        data = response.json()
	        return data.get('result')
	    
	    # If file download (tarball with results)
	    if 'application/gzip' in content_type or 'application/octet-stream' in content_type:
	        with tempfile.TemporaryDirectory() as tmpdir:
	            tar_path = Path(tmpdir) / "result.tar.gz"
	            tar_path.write_bytes(response.content)
	            
	            # Extract tarball
	            with tarfile.open(tar_path, 'r:gz') as tar:
	                tar.extractall(tmpdir)
	            
	            # Try to load pickled result first
	            result_file = Path(tmpdir) / "result.pkl"
	            if result_file.exists():
	                with open(result_file, 'rb') as f:
	                    return pickle.load(f)
	            
	            # Try JSON result
	            json_file = Path(tmpdir) / "result.json"
	            if json_file.exists():
	                with open(json_file, 'r') as f:
	                    return json.load(f)
	            
	            # Return text output
	            output_file = Path(tmpdir) / "output.txt"
	            if output_file.exists():
	                return output_file.read_text()
	            
	            # Return all files as dict
	            files = {}
	            for file in Path(tmpdir).rglob('*'):
	                if file.is_file():
	                    rel_path = file.relative_to(tmpdir)
	                    try:
	                        files[str(rel_path)] = file.read_text()
	                    except:
	                        files[str(rel_path)] = f"<binary file: {file.stat().st_size} bytes>"
	            
	            return files if files else None
	    
	    # Unknown content type
	    return response.text
    
    def network_stats(self) -> dict:
        """Get current network statistics"""
        response = self.session.get(f"{self.base_url}/api/stats/network")
        response.raise_for_status()
        return response.json()
    
    def _package_function(self, func: Callable, args: tuple, kwargs: dict) -> str:
        """Package function with args into executable script"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Save function code
            func_code = inspect.getsource(func)
            func_file = Path(tmpdir) / "function.py"
            func_file.write_text(func_code)
            
            # Save arguments
            args_file = Path(tmpdir) / "args.pkl"
            with open(args_file, 'wb') as f:
                pickle.dump({'args': args, 'kwargs': kwargs}, f)
            
            # Create runner
            runner = f"""
import pickle
from function import {func.__name__}

with open('args.pkl', 'rb') as f:
    data = pickle.load(f)

result = {func.__name__}(*data['args'], **data['kwargs'])

with open('result.pkl', 'wb') as f:
    pickle.dump(result, f)
"""
            runner_file = Path(tmpdir) / "runner.py"
            runner_file.write_text(runner)
            
            # Create tarball
            tar_path = Path(tmpdir) / "code.tar.gz"
            with tarfile.open(tar_path, 'w:gz') as tar:
                tar.add(func_file, arcname='function.py')
                tar.add(args_file, arcname='args.pkl')
                tar.add(runner_file, arcname='runner.py')
            
            return self._upload_file(str(tar_path))
    
    def _upload_file(self, file_path: str) -> str:
        """Upload file to storage"""
        with open(file_path, 'rb') as f:
            data = f.read()
        
        response = self.session.post(
            f"{self.base_url}/api/storage/upload",
            json={
                "filename": Path(file_path).name,
                "data": base64.b64encode(data).decode(),
                "hash": hashlib.sha256(data).hexdigest(),
                "size": len(data)
            }
        )
        response.raise_for_status()
        return response.json()['url']
    
    def _submit_task(self, **kwargs) -> Task:
        """Submit execution task"""
        response = self.session.post(
            f"{self.base_url}/api/tasks/execute",
            json=kwargs
        )
        response.raise_for_status()
        
        data = response.json()
        return Task(id=data['id'], status=data['status'])
    
    def _wait_and_get_result(self, task_id: str) -> Any:
        """Poll until complete and return result"""
        while True:
            try:
                task = self.get_task(task_id)
            
                if task.progress > 0:
                    print(f"\r   Progress: {task.progress:.1f}%", end='', flush=True)
            
                if task.status == 'completed':
                    print("\n✅ Execution complete!")
                    return self.get_result(task_id)
            
                if task.status == 'failed':
                    print(f"\n❌ Task failed: {task.error}")
                    raise RuntimeError(task.error)
            
                time.sleep(5)
            
            except requests.exceptions.JSONDecodeError as e:
                print(f"\n❌ Invalid response from API: {e}")
                raise RuntimeError("API returned invalid JSON")
            except requests.exceptions.RequestException as e:
                print(f"\n❌ Network error: {e}")
                time.sleep(10)  # Wait longer on network errors

# Convenience module-level API
_default_client = None

def init(api_key: Optional[str] = None, base_url: str = "https://distributex-cloud-network.pages.dev"):
    """Initialize default client"""
    global _default_client
    _default_client = DistributeX(api_key, base_url)

def run(*args, **kwargs):
    """Run function using default client"""
    if not _default_client:
        init()
    return _default_client.run(*args, **kwargs)

def run_script(*args, **kwargs):
    """Run script using default client"""
    if not _default_client:
        init()
    return _default_client.run_script(*args, **kwargs)

def run_docker(*args, **kwargs):
    """Run Docker using default client"""
    if not _default_client:
        init()
    return _default_client.run_docker(*args, **kwargs)
