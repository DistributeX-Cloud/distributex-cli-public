"""
DistributeX Python SDK Setup - FIXED
Package name: distributex-cloud (to avoid PyPI conflict)
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read README
readme_file = Path(__file__).parent / "README.md"
if readme_file.exists():
    with open(readme_file, "r", encoding="utf-8") as f:
        long_description = f.read()
else:
    long_description = """
# DistributeX Cloud SDK

Distributed computing platform for Python. Run code on a global pool of CPU, RAM, GPU, and storage.

## Installation

```bash
pip install distributex-cloud
```

## Quick Start

```python
from distributex import DistributeX

dx = DistributeX(api_key="your_api_key")

# Run any Python function
def my_function(data):
    return processed_data

result = dx.run(my_function, args=(data,))
```

Get your API key at: https://distributex-cloud-network.pages.dev
"""

setup(
    name="distributex-cloud",  # NEW NAME to avoid conflict
    version="1.0.0",
    author="DistributeX Team",
    author_email="support@distributex.io",
    description="Distributed computing platform - run code on global resource pool",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/DistributeX-Cloud/distributex-cli-public",
    project_urls={
        "Documentation": "https://distributex.io/docs",
        "Dashboard": "https://distributex-cloud-network.pages.dev",
        "Source": "https://github.com/DistributeX-Cloud/distributex-cli-public",
        "Bug Reports": "https://github.com/DistributeX-Cloud/distributex-cli-public/issues",
    },
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    python_requires=">=3.8",
    install_requires=[
        "requests>=2.28.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
        ],
    },
    keywords=[
        "distributed",
        "computing",
        "cloud",
        "parallel",
        "processing",
        "gpu",
        "cpu",
        "machine-learning",
        "ml",
        "ai",
        "distributex",
    ],
    include_package_data=True,
    zip_safe=False,
)
