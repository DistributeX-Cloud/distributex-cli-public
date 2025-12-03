"""
DistributeX Cloud SDK Setup
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read README
readme_file = Path(__file__).parent / "README.md"
if readme_file.exists():
    with open(readme_file, "r", encoding="utf-8") as f:
        long_description = f.read()
else:
    long_description = "DistributeX - Distributed Computing SDK"

setup(
    name="distributex-cloud",
    version="1.0.1",
    author="DistributeX Team",
    author_email="support@distributex.io",
    description="Distributed computing platform - run code on global resource pool",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/DistributeX-Cloud/distributex-cli-public",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
    python_requires=">=3.8",
    install_requires=[
        "requests>=2.28.0",
    ],
    keywords=["distributed", "computing", "cloud", "parallel", "gpu"],
)
