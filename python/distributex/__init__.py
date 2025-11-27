"""
DistributeX Python SDK
======================
Distributed computing platform for running code on a global pool of resources.

Installation:
    pip install distributex

Usage:
    from distributex import DistributeX
    
    dx = DistributeX(api_key="your_api_key")
    result = dx.run(my_function, args=(data,), workers=4, gpu=True)

"""

from .client import DistributeX, init, run, run_script, run_docker

__version__ = "1.0.0"
__author__ = "DistributeX Team"
__all__ = ["DistributeX", "init", "run", "run_script", "run_docker"]
