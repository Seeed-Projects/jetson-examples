#!/usr/bin/env python3
"""
Generate comprehensive example comparison table
Shows detailed information about each example
"""

import os
import yaml
import json
import glob
from tabulate import tabulate
from pathlib import Path

def get_example_info(config_path):
    """Extract information from an example's config.yaml"""
    example_dir = os.path.dirname(config_path)
    example_name = os.path.basename(example_dir)
    
    info = {
        'name': example_name,
        'type': 'Unknown',
        'models': [],
        'disk_gb': 'N/A',
        'memory_gb': 'N/A',
        'l4t_versions': [],
        'jetpack_versions': [],
        'cuda_required': False,
        'docker_image_size': 'N/A',
        'description': '',
        'features': [],
        'dependencies': []
    }
    
    # Read config.yaml
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
            
        info['disk_gb'] = config.get('REQUIRED_DISK_SPACE', 'N/A')
        info['memory_gb'] = config.get('REQUIRED_MEM_SPACE', 'N/A')
        info['l4t_versions'] = config.get('ALLOWED_L4T_VERSIONS', [])
        info['dependencies'] = config.get('PACKAGES', [])
        
        # Map L4T to JetPack versions
        l4t_to_jetpack = {
            '35.3.1': '5.1.1',
            '35.4.1': '5.1.2', 
            '35.5.0': '5.1.3',
            '36.2.0': '6.0 DP',
            '36.3.0': '6.0',
            '36.4.0': '6.1',
            '36.4.3': '6.2',
            '36.4.4': '6.2.1'
        }
        
        jetpack_versions = set()
        for l4t in info['l4t_versions']:
            if l4t in l4t_to_jetpack:
                jetpack_versions.add(l4t_to_jetpack[l4t])
        info['jetpack_versions'] = sorted(list(jetpack_versions))
        
    except Exception as e:
        print(f"Error reading {config_path}: {e}")
    
    # Read README if exists
    readme_path = os.path.join(example_dir, 'README.md')
    if os.path.exists(readme_path):
        try:
            with open(readme_path, 'r') as f:
                content = f.read()
                # Extract first paragraph as description
                lines = content.split('\n')
                for line in lines:
                    if line.strip() and not line.startswith('#'):
                        info['description'] = line.strip()[:100]
                        break
        except:
            pass
    
    # Categorize by name patterns
    name_lower = example_name.lower()
    if 'llama' in name_lower or 'llava' in name_lower or 'gpt' in name_lower:
        info['type'] = 'LLM/VLM'
    elif 'yolo' in name_lower or 'depth' in name_lower or 'comfy' in name_lower:
        info['type'] = 'Computer Vision'
    elif 'stable-diffusion' in name_lower:
        info['type'] = 'Image Generation'
    elif 'whisper' in name_lower or 'audio' in name_lower or 'tts' in name_lower:
        info['type'] = 'Audio'
    elif 'ollama' in name_lower:
        info['type'] = 'Inference Server'
    elif 'nanodb' in name_lower:
        info['type'] = 'Vector Database'
    
    return info

def generate_markdown_table(examples):
    """Generate a markdown table from example information"""
    # Sort by type then name
    examples.sort(key=lambda x: (x['type'], x['name']))
    
    # Create detailed table
    headers = ['Example', 'Type', 'Disk Space', 'Memory', 'JetPack Support', 'Description']
    rows = []
    
    for ex in examples:
        # Format JetPack versions
        if ex['jetpack_versions']:
            if len(ex['jetpack_versions']) > 3:
                jp_support = f"{ex['jetpack_versions'][0]}...{ex['jetpack_versions'][-1]}"
            else:
                jp_support = ', '.join(ex['jetpack_versions'])
        else:
            jp_support = 'Unknown'
        
        # Format disk/memory
        disk = f"{ex['disk_gb']}GB" if ex['disk_gb'] != 'N/A' else 'N/A'
        memory = f"{ex['memory_gb']}GB" if ex['memory_gb'] != 'N/A' else 'N/A'
        
        # Truncate description
        desc = ex['description'][:50] + '...' if len(ex['description']) > 50 else ex['description']
        
        rows.append([
            ex['name'],
            ex['type'],
            disk,
            memory,
            jp_support,
            desc
        ])
    
    return tabulate(rows, headers, tablefmt='github')

def generate_compatibility_matrix(examples):
    """Generate a JetPack compatibility matrix"""
    jetpack_versions = ['5.1.1', '5.1.2', '5.1.3', '6.0 DP', '6.0', '6.1', '6.2', '6.2.1']
    
    headers = ['Example'] + [f'JP {v}' for v in jetpack_versions]
    rows = []
    
    for ex in examples:
        row = [ex['name']]
        for jp in jetpack_versions:
            if jp in ex['jetpack_versions']:
                row.append('✓')
            else:
                row.append('')
        rows.append(row)
    
    return tabulate(rows, headers, tablefmt='github')

def generate_resource_requirements(examples):
    """Generate resource requirements summary"""
    headers = ['Category', 'Examples', 'Min Disk', 'Max Disk', 'Min Memory', 'Max Memory']
    
    # Group by type
    by_type = {}
    for ex in examples:
        if ex['type'] not in by_type:
            by_type[ex['type']] = []
        by_type[ex['type']].append(ex)
    
    rows = []
    for cat, exs in sorted(by_type.items()):
        disk_values = [e['disk_gb'] for e in exs if e['disk_gb'] != 'N/A']
        mem_values = [e['memory_gb'] for e in exs if e['memory_gb'] != 'N/A']
        
        min_disk = min(disk_values) if disk_values else 'N/A'
        max_disk = max(disk_values) if disk_values else 'N/A'
        min_mem = min(mem_values) if mem_values else 'N/A'
        max_mem = max(mem_values) if mem_values else 'N/A'
        
        rows.append([
            cat,
            len(exs),
            f"{min_disk}GB" if min_disk != 'N/A' else 'N/A',
            f"{max_disk}GB" if max_disk != 'N/A' else 'N/A',
            f"{min_mem}GB" if min_mem != 'N/A' else 'N/A',
            f"{max_mem}GB" if max_mem != 'N/A' else 'N/A'
        ])
    
    return tabulate(rows, headers, tablefmt='github')

def main():
    """Generate comprehensive example tables"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_files = glob.glob(os.path.join(script_dir, "*/config.yaml"))
    
    print("📊 Analyzing examples...")
    examples = []
    for config_file in config_files:
        info = get_example_info(config_file)
        examples.append(info)
    
    print(f"Found {len(examples)} examples\n")
    
    # Generate main comparison table
    print("=" * 80)
    print("EXAMPLE COMPARISON TABLE")
    print("=" * 80)
    print(generate_markdown_table(examples))
    
    print("\n" + "=" * 80)
    print("JETPACK COMPATIBILITY MATRIX")
    print("=" * 80)
    print(generate_compatibility_matrix(examples))
    
    print("\n" + "=" * 80)
    print("RESOURCE REQUIREMENTS SUMMARY")
    print("=" * 80)
    print(generate_resource_requirements(examples))
    
    # Save to files
    output_dir = os.path.join(script_dir, "..")
    
    # Save detailed JSON
    json_file = os.path.join(output_dir, "examples_info.json")
    with open(json_file, 'w') as f:
        json.dump(examples, f, indent=2)
    print(f"\n📄 Detailed info saved to: {json_file}")
    
    # Save markdown tables
    md_file = os.path.join(output_dir, "EXAMPLES_TABLE.md")
    with open(md_file, 'w') as f:
        f.write("# Jetson Examples Comparison\n\n")
        f.write("## Example Overview\n\n")
        f.write(generate_markdown_table(examples))
        f.write("\n\n## JetPack Compatibility Matrix\n\n")
        f.write(generate_compatibility_matrix(examples))
        f.write("\n\n## Resource Requirements by Category\n\n")
        f.write(generate_resource_requirements(examples))
        f.write("\n\n---\n")
        f.write("*Generated automatically by `reComputer/scripts/generate_example_table.py`*\n")
    
    print(f"📄 Markdown tables saved to: {md_file}")

if __name__ == "__main__":
    main()