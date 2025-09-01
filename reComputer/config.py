#!/usr/bin/env python3
"""
Configuration management for jetson-examples
Allows users to set custom paths and preferences
"""

import os
import json
import sys
from pathlib import Path

DEFAULT_CONFIG = {
    "BASE_PATH": os.path.expanduser("~/git"),  # Use git directory as base
    "JETSON_REPO_PATH": None,  # Will be set based on BASE_PATH
    "AUTO_UPDATE": True,
    "DEFAULT_DOCKER_RUNTIME": "nvidia",
    "MAX_DISK_WARNING_GB": 5,
    "VERBOSE": False,
    "PARALLEL_DOWNLOADS": True,
    "CACHE_DIR": None,  # Will be set based on BASE_PATH
}

CONFIG_FILE = os.path.expanduser("~/.config/jetson-examples/config.json")

class Config:
    def __init__(self):
        self.config_dir = os.path.dirname(CONFIG_FILE)
        self.config = DEFAULT_CONFIG.copy()
        self.load()
        
    def load(self):
        """Load configuration from file"""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r') as f:
                    user_config = json.load(f)
                    self.config.update(user_config)
            except Exception as e:
                print(f"Warning: Could not load config: {e}")
        
        # Set derived paths
        if self.config["JETSON_REPO_PATH"] is None:
            self.config["JETSON_REPO_PATH"] = os.path.join(
                self.config["BASE_PATH"], "jetson-containers"
            )
        if self.config["CACHE_DIR"] is None:
            self.config["CACHE_DIR"] = os.path.join(
                self.config["BASE_PATH"], ".cache"
            )
    
    def save(self):
        """Save current configuration to file"""
        os.makedirs(self.config_dir, exist_ok=True)
        with open(CONFIG_FILE, 'w') as f:
            json.dump(self.config, f, indent=2)
        print(f"Configuration saved to {CONFIG_FILE}")
    
    def get(self, key, default=None):
        """Get configuration value"""
        return self.config.get(key, default)
    
    def set(self, key, value):
        """Set configuration value"""
        self.config[key] = value
    
    def update(self, updates):
        """Update multiple configuration values"""
        self.config.update(updates)
    
    def reset(self):
        """Reset to default configuration"""
        self.config = DEFAULT_CONFIG.copy()
        print("Configuration reset to defaults")
    
    def show(self):
        """Display current configuration"""
        print("\nCurrent Configuration:")
        print("-" * 40)
        for key, value in self.config.items():
            print(f"  {key}: {value}")
        print("-" * 40)
    
    def export_env(self):
        """Export configuration as environment variables"""
        exports = []
        for key, value in self.config.items():
            if value is not None:
                exports.append(f"export JETSON_{key}='{value}'")
        return "\n".join(exports)
    
    def validate(self):
        """Validate configuration values"""
        errors = []
        
        # Check BASE_PATH
        base_path = self.config.get("BASE_PATH")
        if not base_path:
            errors.append("BASE_PATH is not set")
        elif not os.path.isabs(os.path.expanduser(base_path)):
            errors.append(f"BASE_PATH must be an absolute path: {base_path}")
        
        # Check disk space warning threshold
        max_disk = self.config.get("MAX_DISK_WARNING_GB", 5)
        if not isinstance(max_disk, (int, float)) or max_disk < 0:
            errors.append(f"MAX_DISK_WARNING_GB must be a positive number: {max_disk}")
        
        if errors:
            print("Configuration validation errors:")
            for error in errors:
                print(f"  - {error}")
            return False
        return True

def main():
    """CLI for configuration management"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Manage jetson-examples configuration")
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Show command
    parser_show = subparsers.add_parser('show', help='Show current configuration')
    
    # Get command
    parser_get = subparsers.add_parser('get', help='Get a configuration value')
    parser_get.add_argument('key', help='Configuration key')
    
    # Set command
    parser_set = subparsers.add_parser('set', help='Set a configuration value')
    parser_set.add_argument('key', help='Configuration key')
    parser_set.add_argument('value', help='Configuration value')
    
    # Reset command
    parser_reset = subparsers.add_parser('reset', help='Reset to default configuration')
    
    # Export command
    parser_export = subparsers.add_parser('export', help='Export as environment variables')
    
    # Validate command
    parser_validate = subparsers.add_parser('validate', help='Validate configuration')
    
    args = parser.parse_args()
    
    config = Config()
    
    if args.command == 'show' or args.command is None:
        config.show()
    elif args.command == 'get':
        value = config.get(args.key)
        if value is not None:
            print(value)
        else:
            print(f"Key '{args.key}' not found")
            sys.exit(1)
    elif args.command == 'set':
        # Try to parse value as JSON for complex types
        try:
            import json
            value = json.loads(args.value)
        except:
            value = args.value
        
        # Convert string booleans
        if value == "true":
            value = True
        elif value == "false":
            value = False
        
        config.set(args.key, value)
        config.save()
        print(f"Set {args.key} = {value}")
    elif args.command == 'reset':
        config.reset()
        config.save()
    elif args.command == 'export':
        print(config.export_env())
    elif args.command == 'validate':
        if config.validate():
            print("Configuration is valid")
        else:
            sys.exit(1)

if __name__ == "__main__":
    main()