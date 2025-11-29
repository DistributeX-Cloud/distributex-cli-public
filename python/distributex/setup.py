"""
DistributeX Python SDK Setup
Fixed version with proper dependencies and entry points
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read README if available
readme_file = Path(__file__).parent / "README.md"
long_description = ""
if readme_file.exists():
    long_description = readme_file.read_text(encoding="utf-8")
else:
    long_description = "Distributed computing platform SDK for Python"

setup(
    name="distributex",
    version="1.0.0",
    author="DistributeX Team",
    author_email="support@distributex.io",
    description="Distributed computing platform SDK - run code on global resource pool",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/DistributeX-Cloud/distributex-cli-public",
    project_urls={
        "Documentation": "https://distributex.io/docs",
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
            "mypy>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "distributex-py=distributex.cli:main",
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
    ],
    include_package_data=True,
    zip_safe=False,
)
