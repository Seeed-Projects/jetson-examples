#!/usr/bin/env python3
"""
Jetson Compatibility Checker
Provides comprehensive compatibility information for all Jetson models
"""

import os
import subprocess
import json

# Comprehensive Jetson model mapping
JETSON_MODELS = {
    # Jetson Nano series
    "jetson-nano": {
        "name": "Jetson Nano",
        "variants": ["Developer Kit", "2GB Developer Kit", "Production Module"],
        "compute": "5.3",
        "memory": ["4GB", "2GB"],
        "l4t_versions": ["32.4.3", "32.5.0", "32.5.1", "32.5.2", "32.6.1", "32.7.1", "32.7.2", "32.7.3"],
        "jetpack": ["4.4", "4.4.1", "4.5", "4.5.1", "4.6", "4.6.1", "4.6.2", "4.6.3"],
        "cuda": "10.2",
        "status": "production"
    },
    
    # Jetson TX1
    "jetson-tx1": {
        "name": "Jetson TX1",
        "variants": ["Developer Kit", "Production Module"],
        "compute": "5.3",
        "memory": ["4GB"],
        "l4t_versions": ["28.2", "28.2.1", "28.3", "28.3.1", "28.3.2", "28.4", "28.5"],
        "jetpack": ["3.2", "3.2.1", "3.3", "3.3.1", "3.3.2", "3.3.3"],
        "cuda": "10.0",
        "status": "legacy"
    },
    
    # Jetson TX2 series
    "jetson-tx2": {
        "name": "Jetson TX2",
        "variants": ["Developer Kit", "TX2 4GB", "TX2i", "TX2 NX"],
        "compute": "6.2",
        "memory": ["8GB", "4GB"],
        "l4t_versions": ["32.4.3", "32.5.0", "32.5.1", "32.5.2", "32.6.1", "32.7.1", "32.7.2", "32.7.3"],
        "jetpack": ["4.4", "4.4.1", "4.5", "4.5.1", "4.6", "4.6.1", "4.6.2", "4.6.3"],
        "cuda": "10.2",
        "status": "production"
    },
    
    # Jetson Xavier NX
    "jetson-xavier-nx": {
        "name": "Jetson Xavier NX",
        "variants": ["Developer Kit", "Production Module 16GB", "Production Module 8GB"],
        "compute": "7.2",
        "memory": ["16GB", "8GB"],
        "l4t_versions": ["32.4.3", "32.5.0", "32.5.1", "32.5.2", "32.6.1", "32.7.1", "32.7.2", "32.7.3", 
                        "35.1.0", "35.2.1", "35.3.1", "35.4.1", "35.5.0"],
        "jetpack": ["4.4", "4.4.1", "4.5", "4.5.1", "4.6", "4.6.1", "4.6.2", "4.6.3",
                   "5.0.2", "5.1", "5.1.1", "5.1.2", "5.1.3"],
        "cuda": ["10.2", "11.4"],
        "status": "production"
    },
    
    # Jetson AGX Xavier
    "jetson-agx-xavier": {
        "name": "Jetson AGX Xavier",
        "variants": ["Developer Kit 32GB", "Industrial 32GB", "Series 64GB", "Series 32GB", "Series 16GB", "Series 8GB"],
        "compute": "7.2",
        "memory": ["64GB", "32GB", "16GB", "8GB"],
        "l4t_versions": ["32.4.3", "32.5.0", "32.5.1", "32.5.2", "32.6.1", "32.7.1", "32.7.2", "32.7.3",
                        "35.1.0", "35.2.1", "35.3.1", "35.4.1", "35.5.0"],
        "jetpack": ["4.4", "4.4.1", "4.5", "4.5.1", "4.6", "4.6.1", "4.6.2", "4.6.3",
                   "5.0.2", "5.1", "5.1.1", "5.1.2", "5.1.3"],
        "cuda": ["10.2", "11.4"],
        "status": "production"
    },
    
    # Jetson AGX Orin
    "jetson-agx-orin": {
        "name": "Jetson AGX Orin",
        "variants": ["Developer Kit", "64GB", "32GB", "Industrial"],
        "compute": "8.7",
        "memory": ["64GB", "32GB"],
        "l4t_versions": ["34.1.0", "34.1.1", "35.1.0", "35.2.1", "35.3.1", "35.4.1", "35.5.0", 
                        "36.2.0", "36.3.0", "36.4.0", "36.4.3", "36.4.4"],
        "jetpack": ["5.0", "5.0.1", "5.0.2", "5.1", "5.1.1", "5.1.2", "5.1.3", 
                   "6.0 DP", "6.0", "6.1", "6.2", "6.2.1"],
        "cuda": ["11.4", "12.2", "12.6"],
        "status": "production"
    },
    
    # Jetson Orin NX
    "jetson-orin-nx": {
        "name": "Jetson Orin NX",
        "variants": ["16GB", "8GB"],
        "compute": "8.7",
        "memory": ["16GB", "8GB"],
        "l4t_versions": ["35.2.1", "35.3.1", "35.4.1", "35.5.0", "36.2.0", "36.3.0", "36.4.0", "36.4.3", "36.4.4"],
        "jetpack": ["5.1", "5.1.1", "5.1.2", "5.1.3", "6.0 DP", "6.0", "6.1", "6.2", "6.2.1"],
        "cuda": ["11.4", "12.2", "12.6"],
        "status": "production"
    },
    
    # Jetson Orin Nano
    "jetson-orin-nano": {
        "name": "Jetson Orin Nano",
        "variants": ["Developer Kit", "8GB", "4GB"],
        "compute": "8.7",
        "memory": ["8GB", "4GB"],
        "l4t_versions": ["35.3.1", "35.4.1", "35.5.0", "36.2.0", "36.3.0", "36.4.0", "36.4.3", "36.4.4"],
        "jetpack": ["5.1.1", "5.1.2", "5.1.3", "6.0 DP", "6.0", "6.1", "6.2", "6.2.1"],
        "cuda": ["11.4", "12.2", "12.6"],
        "status": "production"
    }
}

# L4T to JetPack version mapping
L4T_TO_JETPACK = {
    # JetPack 3.x
    "28.2": "3.2",
    "28.2.1": "3.2.1", 
    "28.3": "3.3",
    "28.3.1": "3.3.1",
    "28.3.2": "3.3.2",
    "28.4": "3.3.3",
    
    # JetPack 4.x
    "32.1": "4.2",
    "32.2": "4.2.1",
    "32.2.1": "4.2.2",
    "32.2.3": "4.2.3",
    "32.3.1": "4.3",
    "32.4.2": "4.4 DP",
    "32.4.3": "4.4",
    "32.4.4": "4.4.1",
    "32.5.0": "4.5",
    "32.5.1": "4.5.1",
    "32.5.2": "4.5.1",
    "32.6.1": "4.6",
    "32.7.1": "4.6.1",
    "32.7.2": "4.6.2",
    "32.7.3": "4.6.3",
    "32.7.4": "4.6.4",
    
    # JetPack 5.x
    "34.1.0": "5.0",
    "34.1.1": "5.0.1",
    "35.1.0": "5.0.2",
    "35.2.1": "5.1",
    "35.3.1": "5.1.1",
    "35.4.1": "5.1.2",
    "35.5.0": "5.1.3",
    
    # JetPack 6.x
    "36.2.0": "6.0 DP",
    "36.3.0": "6.0",
    "36.4.0": "6.1",
    "36.4.3": "6.2",
    "36.4.4": "6.2.1"
}

class JetsonCompatibilityChecker:
    def __init__(self):
        self.model = None
        self.l4t_version = None
        self.jetpack_version = None
        self.cuda_version = None
        self.memory = None
        
    def detect_jetson_model(self):
        """Detect the current Jetson model"""
        try:
            if os.path.exists("/proc/device-tree/model"):
                with open("/proc/device-tree/model", "r") as f:
                    model_string = f.read().strip().lower()
                    
                # Map model strings to our model keys
                if "nano" in model_string:
                    if "orin" in model_string:
                        self.model = "jetson-orin-nano"
                    else:
                        self.model = "jetson-nano"
                elif "tx1" in model_string:
                    self.model = "jetson-tx1"
                elif "tx2" in model_string:
                    self.model = "jetson-tx2"
                elif "xavier nx" in model_string or "nx" in model_string:
                    if "orin" in model_string:
                        self.model = "jetson-orin-nx"
                    else:
                        self.model = "jetson-xavier-nx"
                elif "xavier" in model_string or "agx" in model_string:
                    if "orin" in model_string:
                        self.model = "jetson-agx-orin"
                    else:
                        self.model = "jetson-agx-xavier"
                elif "orin nx" in model_string:
                    self.model = "jetson-orin-nx"
                elif "orin" in model_string:
                    self.model = "jetson-agx-orin"
                    
                return self.model
        except:
            pass
        return None
    
    def detect_l4t_version(self):
        """Detect L4T version"""
        try:
            if os.path.exists("/etc/nv_tegra_release"):
                with open("/etc/nv_tegra_release", "r") as f:
                    version_string = f.read()
                    # Parse L4T version
                    import re
                    match = re.search(r'R(\d+) \(release\), REVISION: ([\d.]+)', version_string)
                    if match:
                        release = match.group(1)
                        revision = match.group(2)
                        self.l4t_version = f"{release}.{revision}"
                        self.jetpack_version = L4T_TO_JETPACK.get(self.l4t_version, "Unknown")
                        return self.l4t_version
        except:
            pass
        return None
    
    def detect_cuda_version(self):
        """Detect CUDA version"""
        # Try nvcc in PATH first
        try:
            result = subprocess.run(['nvcc', '--version'], capture_output=True, text=True)
            if result.returncode == 0:
                import re
                match = re.search(r'release ([\d.]+)', result.stdout)
                if match:
                    self.cuda_version = match.group(1)
                    return self.cuda_version
        except:
            pass
        
        # Try standard CUDA locations
        cuda_paths = ['/usr/local/cuda/bin/nvcc', '/usr/local/cuda-12/bin/nvcc', 
                      '/usr/local/cuda-11/bin/nvcc', '/usr/local/cuda-12.6/bin/nvcc']
        for cuda_path in cuda_paths:
            if os.path.exists(cuda_path):
                try:
                    result = subprocess.run([cuda_path, '--version'], capture_output=True, text=True)
                    if result.returncode == 0:
                        import re
                        match = re.search(r'release ([\d.]+)', result.stdout)
                        if match:
                            self.cuda_version = match.group(1)
                            return self.cuda_version
                except:
                    pass
        
        return None
    
    def detect_memory(self):
        """Detect system memory"""
        try:
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    if line.startswith('MemTotal'):
                        mem_kb = int(line.split()[1])
                        mem_gb = round(mem_kb / (1024 * 1024))
                        self.memory = f"{mem_gb}GB"
                        return self.memory
        except:
            pass
        return None
    
    def check_compatibility(self, example_requirements):
        """Check if current system is compatible with example requirements"""
        compatibility = {
            "compatible": True,
            "warnings": [],
            "errors": []
        }
        
        if not self.model:
            compatibility["errors"].append("Could not detect Jetson model")
            compatibility["compatible"] = False
            return compatibility
            
        model_info = JETSON_MODELS.get(self.model)
        if not model_info:
            compatibility["warnings"].append(f"Unknown Jetson model: {self.model}")
            
        # Check L4T version
        if "l4t_versions" in example_requirements:
            required_l4t = example_requirements["l4t_versions"]
            if self.l4t_version not in required_l4t:
                compatibility["errors"].append(f"L4T version {self.l4t_version} not supported. Required: {required_l4t}")
                compatibility["compatible"] = False
                
        # Check memory
        if "min_memory" in example_requirements:
            required_mem = example_requirements["min_memory"]
            current_mem = int(self.memory.replace("GB", ""))
            if current_mem < required_mem:
                compatibility["errors"].append(f"Insufficient memory: {self.memory}. Required: {required_mem}GB")
                compatibility["compatible"] = False
                
        # Check CUDA
        if "cuda_version" in example_requirements:
            required_cuda = example_requirements["cuda_version"]
            if self.cuda_version:
                current_cuda_major = float('.'.join(self.cuda_version.split('.')[:2]))
                required_cuda_major = float('.'.join(required_cuda.split('.')[:2]))
                if current_cuda_major < required_cuda_major:
                    compatibility["warnings"].append(f"CUDA version {self.cuda_version} may not be optimal. Recommended: {required_cuda}")
                    
        return compatibility
    
    def generate_compatibility_report(self):
        """Generate a comprehensive compatibility report"""
        report = {
            "system_info": {
                "model": self.model,
                "model_name": JETSON_MODELS.get(self.model, {}).get("name", "Unknown"),
                "l4t_version": self.l4t_version,
                "jetpack_version": self.jetpack_version,
                "cuda_version": self.cuda_version,
                "memory": self.memory
            },
            "model_capabilities": JETSON_MODELS.get(self.model, {}),
            "supported_examples": [],
            "unsupported_examples": []
        }
        
        return report
    
    def print_report(self):
        """Print a formatted compatibility report"""
        print("\n" + "="*60)
        print("         JETSON COMPATIBILITY REPORT")
        print("="*60)
        
        print("\n📊 SYSTEM INFORMATION:")
        print(f"  Model: {JETSON_MODELS.get(self.model, {}).get('name', 'Unknown')}")
        print(f"  L4T Version: {self.l4t_version or 'Not detected'}")
        print(f"  JetPack: {self.jetpack_version or 'Not detected'}")
        print(f"  CUDA: {self.cuda_version or 'Not detected'}")
        print(f"  Memory: {self.memory or 'Not detected'}")
        
        if self.model and self.model in JETSON_MODELS:
            model_info = JETSON_MODELS[self.model]
            print("\n🔧 MODEL CAPABILITIES:")
            print(f"  Compute Capability: {model_info['compute']}")
            print(f"  Variants: {', '.join(model_info['variants'])}")
            print(f"  Status: {model_info['status']}")
            print(f"  Supported L4T: {', '.join(model_info['l4t_versions'][:3])}...")
            print(f"  Supported JetPack: {', '.join(model_info['jetpack'][:3])}...")
        
        print("\n" + "="*60)

def main():
    checker = JetsonCompatibilityChecker()
    
    # Detect system information
    checker.detect_jetson_model()
    checker.detect_l4t_version()
    checker.detect_cuda_version()
    checker.detect_memory()
    
    # Print report
    checker.print_report()
    
    # Generate JSON report for programmatic use
    report = checker.generate_compatibility_report()
    
    # Save report to file
    report_file = os.path.expanduser("~/.config/jetson-examples/compatibility_report.json")
    os.makedirs(os.path.dirname(report_file), exist_ok=True)
    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2)
    print(f"\n📄 Full report saved to: {report_file}\n")

if __name__ == "__main__":
    main()