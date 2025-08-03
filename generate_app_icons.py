#!/usr/bin/env python3
"""
App Icon Generator for iOS/iPadOS/macOS/watchOS

This script generates all required PNG app icon sizes from a source SVG file
using Inkscape for high-quality rendering.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


# Define all required icon sizes based on the AppIcon.appiconset configuration
ICON_SIZES = [
    # iPhone & iPad sizes
    16, 20, 29, 32, 40, 48, 50, 55, 57, 58, 60, 64, 72, 76, 80, 87, 88,
    100, 114, 120, 128, 144, 152, 167, 172, 180, 196, 216, 256, 512, 1024
]


def check_inkscape():
    """Check if Inkscape is available and return the path if found."""
    # Check common Inkscape locations
    inkscape_paths = [
        "inkscape",  # If in PATH
        "/Applications/Inkscape.app/Contents/MacOS/inkscape",  # macOS app
        "/usr/bin/inkscape",  # Linux
        "/opt/homebrew/bin/inkscape",  # Homebrew on macOS
        "/usr/local/bin/inkscape",  # Manual install on macOS/Linux
    ]
    
    for path in inkscape_paths:
        try:
            result = subprocess.run([path, '--version'], 
                                  capture_output=True, text=True, check=True)
            print(f"Found Inkscape: {result.stdout.strip()}")
            return path
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    
    print("ERROR: Inkscape not found")
    print("Please install Inkscape:")
    print("  macOS: brew install inkscape")
    print("  macOS: Download from https://inkscape.org/")
    print("  Linux: sudo apt install inkscape")
    return None


def generate_png(svg_path, output_path, size, inkscape_path):
    """Generate a PNG file from SVG using Inkscape."""
    try:
        cmd = [
            inkscape_path,
            '--export-type=png',
            f'--export-filename={output_path}',
            f'--export-width={size}',
            f'--export-height={size}',
            str(svg_path)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"✓ Generated {size}×{size} → {output_path}")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"✗ Failed to generate {size}×{size}: {e}")
        if e.stderr:
            print(f"  Error: {e.stderr.strip()}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate all required PNG app icon sizes from an SVG file using Inkscape",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           # Use default SVG (Docs/newicon.svg)
  %(prog)s -i my-icon.svg            # Use custom SVG file
  %(prog)s -o my-icons               # Custom output directory
  %(prog)s -i icon.svg -o generated  # Custom input and output

Generated sizes:
  iPhone/iPad: 20, 29, 40, 50, 57, 58, 60, 72, 76, 80, 87, 100, 114, 120, 
               144, 152, 167, 180
  Mac: 16, 32, 64, 128, 256, 512, 1024
  Apple Watch: 48, 55, 88, 172, 196, 216
  App Store: 1024 (marketing)
        """
    )
    
    parser.add_argument(
        '-i', '--input',
        default='Docs/newicon.svg',
        help='Input SVG file path (default: Docs/newicon.svg)'
    )
    
    parser.add_argument(
        '-o', '--output',
        default='generated_icons',
        help='Output directory for PNG files (default: generated_icons)'
    )
    
    parser.add_argument(
        '--force',
        action='store_true',
        help='Overwrite existing output directory without asking'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be generated without actually creating files'
    )
    
    args = parser.parse_args()
    
    # Validate input file
    svg_path = Path(args.input)
    if not svg_path.exists():
        print(f"ERROR: Input SVG file not found: {svg_path}")
        sys.exit(1)
    
    if not svg_path.suffix.lower() == '.svg':
        print(f"WARNING: Input file doesn't have .svg extension: {svg_path}")
    
    # Check Inkscape availability
    inkscape_path = None
    if not args.dry_run:
        inkscape_path = check_inkscape()
        if not inkscape_path:
            sys.exit(1)
    
    # Setup output directory
    output_dir = Path(args.output)
    
    if output_dir.exists():
        if not args.force:
            response = input(f"Output directory '{output_dir}' exists. Overwrite? [y/N]: ")
            if response.lower() not in ['y', 'yes']:
                print("Aborted.")
                sys.exit(0)
    
    if args.dry_run:
        print(f"DRY RUN: Would generate {len(ICON_SIZES)} PNG files:")
        print(f"  Input:  {svg_path}")
        print(f"  Output: {output_dir}/")
        for size in sorted(ICON_SIZES):
            output_file = output_dir / f"{size}.png"
            print(f"  - {size}×{size} → {output_file}")
        sys.exit(0)
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Generating {len(ICON_SIZES)} icon sizes from {svg_path}")
    print(f"Output directory: {output_dir}")
    print()
    
    # Generate all icon sizes
    success_count = 0
    failed_count = 0
    
    for size in sorted(ICON_SIZES):
        output_file = output_dir / f"{size}.png"
        
        if generate_png(svg_path, output_file, size, inkscape_path):
            success_count += 1
        else:
            failed_count += 1
    
    print()
    print(f"Generation complete: {success_count} successful, {failed_count} failed")
    
    if failed_count > 0:
        print(f"WARNING: {failed_count} files failed to generate")
        sys.exit(1)
    
    print(f"\nAll PNG files generated in: {output_dir}")
    print("\nTo use these icons:")
    print(f"1. Copy the PNG files to RemoteCam/Assets.xcassets/AppIcon.appiconset/")
    print(f"2. Replace the existing PNG files with the same names")
    print(f"3. The 1024.png file is used for App Store marketing")


if __name__ == '__main__':
    main() 