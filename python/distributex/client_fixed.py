"""
DistributeX Python SDK - FIXED VERSION
=======================================
Properly connects to distributed network and utilizes resources
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

__version__ = "1.0.1"

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
                "Get your API key at: https://distributex-cloud-network.pages.dev/api-dashboard"
            )
        
        self.base_url = base_url.rstrip('/')
        
        # Create session with proper headers
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
            "User-Agent": f"DistributeX-Python-SDK/{__version__}"
        })
        
        # Test connection
        self._verify_connection()
    
    def _verify_connection(self):
        """Verify API key and connection"""
        try:
            response = self.session.get(f"{self.base_url}/api/auth/user")
            response.raise_for_status()
            user = response.json()
            print(f"✅ Connected as: {user.get('email', 'Unknown')}")
            
            # Check role
            if user.get('role') != 'developer':
                print(f"⚠️  Warning: Your role is '{user.get('role')}', should be 'developer'")
                print("   Some features may not work. Change role in dashboard.")
            
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 401:
                raise ValueError(
                    "Invalid API key. Please check your key or generate a new one at:\n"
                    "https://distributex-cloud-network.pages.dev/api-dashboard"
                )
            raise
        except Exception as e:
            raise ConnectionError(f"Failed to connect to DistributeX: {e}")
    
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
        """
        kwargs = kwargs or {}
        
        print("📦 Packaging function...")
        
        # Create execution script
        script_content = self._create_function_script(func, args, kwargs)
        
        # Upload as file
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(script_content)
            script_path = f.name
        
        try:
            result = self.run_script(
                script_path,
                runtime='python',
                workers=workers,
                cpu_per_worker=cpu_per_worker,
                ram_per_worker=ram_per_worker,
                gpu=gpu,
                cuda=cuda,
                timeout=timeout,
                wait=wait
            )
            return result
        finally:
            os.unlink(script_path)
    
    def _create_function_script(self, func: Callable, args: tuple, kwargs: dict) -> str:
        """Create Python script that executes the function"""
        func_source = inspect.getsource(func)
        func_name = func.__name__
        
        script = f"""#!/usr/bin/env python3
import json
import sys

# User function
{func_source}

# Arguments
args = {repr(args)}
kwargs = {repr(kwargs)}

# Execute
try:
    result = {func_name}(*args, **kwargs)
    
    # Save result
    with open('result.json', 'w') as f:
        json.dump({{'success': True, 'result': result}}, f)
    
    print(json.dumps(result))
    sys.exit(0)
    
except Exception as e:
    with open('result.json', 'w') as f:
        json.dump({{'success': False, 'error': str(e)}}, f)
    
    print(f"ERROR: {{e}}", file=sys.stderr)
    sys.exit(1)
"""
        return script
    
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
        Run any script file on the network
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
                '.sh': 'bash'
            }
            runtime = runtime_map.get(ext, 'python')
        
        print(f"📤 Uploading script: {script_path}")
        
        # Read script file
        with open(script_path, 'rb') as f:
            script_data = f.read()
        
        # Encode to base64
        script_base64 = base64.b64encode(script_data).decode('utf-8')
        script_hash = hashlib.sha256(script_data).hexdigest()
        
        print(f"🚀 Submitting task to network...")
        
        # Submit task directly with embedded code
        task_data = {
            "name": f"Execute {Path(script_path).name}",
            "taskType": "script_execution",
            "runtime": runtime,
            "command": command,
            "workers": workers,
            "cpuPerWorker": cpu_per_worker,
            "ramPerWorker": ram_per_worker,
            "gpuRequired": gpu,
            "requiresCuda": cuda,
            "timeout": timeout,
            "priority": 5,
            "executionScript": script_base64,  # Embedded script
            "scriptHash": script_hash,
            "inputFiles": [],
            "outputPaths": output_files,
            "environment": env
        }
        
        response = self.session.post(
            f"{self.base_url}/api/tasks/execute",
            json=task_data
        )
        
        response.raise_for_status()
        data = response.json()
        
        if not data.get('success'):
            raise RuntimeError(f"Task submission failed: {data.get('message', 'Unknown error')}")
        
        task_id = data['id']
        print(f"✅ Task submitted: {task_id}")
        print(f"   Status: {data.get('status', 'pending')}")
        
        if data.get('queuePosition'):
            print(f"   Queue position: {data['queuePosition']}")
        if data.get('assignedWorker'):
            print(f"   Assigned to: {data['assignedWorker']['name']}")
        
        task = Task(id=task_id, status=data['status'])
        
        if not wait:
            return task
        
        print("⏳ Waiting for execution...")
        return self._wait_and_get_result(task_id)
    
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
        """
        volumes = volumes or {}
        env = env or {}
        ports = ports or {}
        
        print(f"🐳 Submitting Docker task: {image}")
        
        task_data = {
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
        
        response = self.session.post(
            f"{self.base_url}/api/tasks/execute",
            json=task_data
        )
        response.raise_for_status()
        
        data = response.json()
        task_id = data['id']
        
        print(f"✅ Task submitted: {task_id}")
        
        task = Task(id=task_id, status=data['status'])
        
        if not wait:
            return task
        
        print("⏳ Executing Docker container...")
        return self._wait_and_get_result(task_id)
    
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
        
        # Try new result endpoint
        response = self.session.get(
            f"{self.base_url}/api/tasks/{task_id}/result",
            allow_redirects=True
        )
        response.raise_for_status()
        
        content_type = response.headers.get('content-type', '')
        
        # JSON response (small result in DB)
        if 'application/json' in content_type:
            data = response.json()
            return data.get('result')
        
        # File download (tarball)
        if 'application/gzip' in content_type or 'application/octet-stream' in content_type:
            with tempfile.TemporaryDirectory() as tmpdir:
                tar_path = Path(tmpdir) / "result.tar.gz"
                tar_path.write_bytes(response.content)
                
                with tarfile.open(tar_path, 'r:gz') as tar:
                    tar.extractall(tmpdir)
                
                # Try result.json
                json_file = Path(tmpdir) / "result.json"
                if json_file.exists():
                    with open(json_file, 'r') as f:
                        data = json.load(f)
                        return data.get('result', data)
                
                # Return text output
                output_file = Path(tmpdir) / "output.txt"
                if output_file.exists():
                    return output_file.read_text()
                
                # Return all files
                files = {}
                for file in Path(tmpdir).rglob('*'):
                    if file.is_file():
                        rel_path = file.relative_to(tmpdir)
                        try:
                            files[str(rel_path)] = file.read_text()
                        except:
                            files[str(rel_path)] = f"<binary: {file.stat().st_size} bytes>"
                
                return files if files else None
        
        return response.text
    
    def network_stats(self) -> dict:
        """Get current network statistics"""
        response = self.session.get(f"{self.base_url}/api/stats/network")
        response.raise_for_status()
        return response.json()
    
    def _wait_and_get_result(self, task_id: str, poll_interval: int = 5) -> Any:
        """Poll until complete and return result"""
        last_progress = -1
        
        while True:
            try:
                task = self.get_task(task_id)
                
                # Show progress if changed
                if task.progress > last_progress:
                    print(f"\r   Progress: {task.progress:.1f}%", end='', flush=True)
                    last_progress = task.progress
                
                if task.status == 'completed':
                    print("\n✅ Execution complete!")
                    return self.get_result(task_id)
                
                if task.status == 'failed':
                    print(f"\n❌ Task failed: {task.error}")
                    raise RuntimeError(task.error)
                
                time.sleep(poll_interval)
                
            except requests.exceptions.RequestException as e:
                print(f"\n⚠️  Network error: {e}")
                time.sleep(poll_interval * 2)


# Convenience functions
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
