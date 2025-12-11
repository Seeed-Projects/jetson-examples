#!/usr/bin/env python3
"""
Update all config.yaml files to support JetPack 6.0 and 6.1
"""

import os
import yaml
import glob

# JetPack 6.x L4T versions
# 36.2.0 = JetPack 6.0 DP (Developer Preview)
# 36.3.0 = JetPack 6.0 GA (General Availability) 
# 36.4.0 = JetPack 6.1
# 36.4.3 = JetPack 6.2 (estimated)
# 36.4.4 = JetPack 6.2.1
JETPACK_6_VERSIONS = ["36.2.0", "36.3.0", "36.4.0", "36.4.3", "36.4.4"]

def update_config_file(filepath):
    """Update a single config.yaml file to support JetPack 6.x"""
    updated = False
    
    try:
        with open(filepath, 'r') as f:
            config = yaml.safe_load(f)
        
        if 'ALLOWED_L4T_VERSIONS' in config:
            current_versions = config['ALLOWED_L4T_VERSIONS']
            
            # Add JetPack 6.x versions if not present
            for version in JETPACK_6_VERSIONS:
                if version not in current_versions:
                    current_versions.append(version)
                    updated = True
            
            if updated:
                # Sort versions
                config['ALLOWED_L4T_VERSIONS'] = sorted(current_versions)
                
                # Write back to file
                with open(filepath, 'w') as f:
                    yaml.dump(config, f, default_flow_style=False, sort_keys=False)
                
                print(f"✅ Updated: {filepath}")
                return True
            else:
                print(f"ℹ️  Already supported: {filepath}")
                return False
    except Exception as e:
        print(f"❌ Error updating {filepath}: {e}")
        return False
    
    return False

def main():
    """Update all config.yaml files in the scripts directory"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_files = glob.glob(os.path.join(script_dir, "*/config.yaml"))
    
    print("🚀 Updating config files for JetPack 6.0 support...")
    print(f"   Adding L4T versions: {', '.join(JETPACK_6_VERSIONS)}")
    print("-" * 60)
    
    updated_count = 0
    for config_file in config_files:
        if update_config_file(config_file):
            updated_count += 1
    
    print("-" * 60)
    print(f"✨ Updated {updated_count}/{len(config_files)} config files")
    
    # Create a compatibility matrix
    create_compatibility_matrix()

def create_compatibility_matrix():
    """Create a compatibility matrix for all examples"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_files = glob.glob(os.path.join(script_dir, "*/config.yaml"))
    
    matrix = {}
    
    for config_file in config_files:
        example_name = os.path.basename(os.path.dirname(config_file))
        
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            
            matrix[example_name] = {
                'l4t_versions': config.get('ALLOWED_L4T_VERSIONS', []),
                'disk_space': config.get('REQUIRED_DISK_SPACE', 'N/A'),
                'memory': config.get('REQUIRED_MEM_SPACE', 'N/A'),
                'jetpack_6_compatible': any(v in config.get('ALLOWED_L4T_VERSIONS', []) 
                                           for v in JETPACK_6_VERSIONS)
            }
        except:
            pass
    
    # Save compatibility matrix
    matrix_file = os.path.join(script_dir, "../compatibility_matrix.yaml")
    with open(matrix_file, 'w') as f:
        yaml.dump(matrix, f, default_flow_style=False)
    
    print(f"\n📊 Compatibility matrix saved to: {matrix_file}")
    
    # Print summary
    jp6_compatible = sum(1 for ex in matrix.values() if ex['jetpack_6_compatible'])
    print(f"\n📈 JetPack 6.0 Compatibility Summary:")
    print(f"   Compatible examples: {jp6_compatible}/{len(matrix)}")
    
    # List incompatible examples
    incompatible = [name for name, info in matrix.items() if not info['jetpack_6_compatible']]
    if incompatible:
        print(f"   ⚠️  Incompatible examples: {', '.join(incompatible)}")

if __name__ == "__main__":
    main()