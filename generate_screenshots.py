#!/usr/bin/env python3
"""
Remote Shutter Screenshot Generator
Generates localized SVG screenshots for different device sizes and languages.
Reads from SVG template files for better design control.
Exports PNG files at expected resolutions using rsvg-convert.
"""

import os
import json
import re
import subprocess
import sys
import platform
from pathlib import Path

# Device configurations
DEVICES = {
    "iphone_67": {
        "name": "iPhone 15 Pro Max",
        "template_name": "iphone_15_pro_max",
        "fastlane_family": "APP_IPHONE_67",
        "width": 1290, "height": 2796,
    },
    "iphone_65": {
        "name": "iPhone 15 Pro",
        "template_name": "iphone_15_pro",
        "fastlane_family": "APP_IPHONE_65",
        "width": 1284, "height": 2778,
    },
    "iphone_55": {
        "name": "iPhone 8 Plus",
        "template_name": "iphone_15_pro",  # reuse 6.5" template, resize on export
        "fastlane_family": "APP_IPHONE_55",
        "width": 1242, "height": 2208,
    },
    "ipad_pro_11": {
        "name": "iPad Pro 11",
        "template_name": "ipad_pro_11",
        "fastlane_family": "APP_IPAD_PRO_3GEN_11",
        "width": 1640, "height": 2360,
    },
    "ipad_pro_12_9": {
        "name": "iPad Pro 12.9",
        "template_name": "ipad_pro_12.9",
        "fastlane_family": "APP_IPAD_PRO_3GEN_129",
        "width": 2048, "height": 2732,
    },
}

# Localization data
LOCALIZATIONS = {
    "en": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Take pictures",
            "description": "from anywhere.",
            "feature": "Works from\nup to 50\nfeet away!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Take pictures",
            "description": "from anywhere.",
            "feature": "Works from\nup to 50\nfeet away!"
        },
        "screenshot3": {
            "title": "Capture Memories",
            "subtitle": "Just Like You",
            "description": "Want Them",
            "feature": "Perfect for\ncreative\nangles!"
        },
        "screenshot4": {
            "title": "Setup Guide",
            "subtitle": "Quick Start",
            "description": "Instructions",
            "feature": "Instructions\nVerify that wifi is on\nLaunch this app\non a second device",
            "camera": "Camera",
            "remote": "Remote"
        }
    },
    "it": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Scatta foto",
            "description": "da ovunque.",
            "feature": "Funziona fino a\n50 piedi\ndi distanza!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Scatta foto",
            "description": "da ovunque.",
            "feature": "Funziona fino a\n50 piedi\ndi distanza!"
        },
        "screenshot3": {
            "title": "Cattura Ricordi",
            "subtitle": "Proprio Come",
            "description": "Li Vuoi",
            "feature": "Perfetto per\nangoli\ncreativi!"
        },
        "screenshot4": {
            "title": "Guida Setup",
            "subtitle": "Avvio Rapido",
            "description": "Istruzioni",
            "feature": "Istruzioni\nVerifica che il wifi sia attivo\nAvvia questa app\nsu un secondo dispositivo",
            "camera": "Camera",
            "remote": "Controllo"
        }
    },
    "fr": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Prenez des photos",
            "description": "de n'importe où.",
            "feature": "Fonctionne jusqu'à\n50 pieds\nde distance!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Prenez des photos",
            "description": "de n'importe où.",
            "feature": "Fonctionne jusqu'à\n50 pieds\nde distance!"
        },
        "screenshot3": {
            "title": "Capturez des Souvenirs",
            "subtitle": "Exactement Comme",
            "description": "Vous Les Voulez",
            "feature": "Parfait pour\ndes angles\ncréatifs!"
        },
        "screenshot4": {
            "title": "Guide de Configuration",
            "subtitle": "Démarrage Rapide",
            "description": "Instructions",
            "feature": "Instructions\nVérifiez que le wifi est activé\nLancez cette app\nsur un deuxième appareil",
            "camera": "Caméra",
            "remote": "Remote"
        }
    },
    "es": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Toma fotos",
            "description": "desde cualquier lugar.",
            "feature": "¡Funciona hasta\n50 pies\nde distancia!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Toma fotos",
            "description": "desde cualquier lugar.",
            "feature": "¡Funciona hasta\n50 pies\nde distancia!"
        },
        "screenshot3": {
            "title": "Captura Recuerdos",
            "subtitle": "Exactamente Como",
            "description": "Los Quieres",
            "feature": "¡Perfecto para\nángulos\ncreativos!"
        },
        "screenshot4": {
            "title": "Guía de Configuración",
            "subtitle": "Inicio Rápido",
            "description": "Instrucciones",
            "feature": "Instrucciones\nVerifica que el wifi esté activado\nLanza esta app\nen un segundo dispositivo",
            "camera": "Cámara",
            "remote": "Control"
        }
    },
    "de": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Machen Sie Fotos",
            "description": "von überall.",
            "feature": "Funktioniert aus\nbis zu 15\nMetern Entfernung!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Machen Sie Fotos",
            "description": "von überall.",
            "feature": "Funktioniert aus\nbis zu 15\nMetern Entfernung!"
        },
        "screenshot3": {
            "title": "Erinnerungen",
            "subtitle": "Genau So",
            "description": "Festhalten",
            "feature": "Perfekt für\nkreative\nBlickwinkel!"
        },
        "screenshot4": {
            "title": "Einrichtung",
            "subtitle": "Schnellstart",
            "description": "Anleitung",
            "feature": "Anleitung\nÜberprüfen Sie dass WLAN aktiv ist\nStarten Sie diese App\nauf einem zweiten Gerät",
            "camera": "Kamera",
            "remote": "Fernbedienung"
        }
    },
    "pt": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Tire fotos",
            "description": "de qualquer lugar.",
            "feature": "Funciona até\n50 pés\nde distância!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Tire fotos",
            "description": "de qualquer lugar.",
            "feature": "Funciona até\n50 pés\nde distância!"
        },
        "screenshot3": {
            "title": "Capture Memórias",
            "subtitle": "Exatamente Como",
            "description": "Você As Quer",
            "feature": "Perfeito para\nângulos\ncriativos!"
        },
        "screenshot4": {
            "title": "Guia de Configuração",
            "subtitle": "Início Rápido",
            "description": "Instruções",
            "feature": "Instruções\nVerifique que o wifi está ativado\nAbra este app\nem um segundo dispositivo",
            "camera": "Câmera",
            "remote": "Controle"
        }
    },
    "da": {
        "screenshot1": {
            "title": "Remote Shutter",
            "subtitle": "Tag billeder",
            "description": "fra hvor som helst.",
            "feature": "Virker op til\n50 fod\nvæk!"
        },
        "screenshot2": {
            "title": "Remote Shutter",
            "subtitle": "Tag billeder",
            "description": "fra hvor som helst.",
            "feature": "Virker op til\n50 fod\nvæk!"
        },
        "screenshot3": {
            "title": "Fang Minder",
            "subtitle": "Præcis Som Du",
            "description": "Vil Have Dem",
            "feature": "Perfekt til\nkreative\nvinkler!"
        },
        "screenshot4": {
            "title": "Opsætningsguide",
            "subtitle": "Hurtig Start",
            "description": "Instruktioner",
            "feature": "Instruktioner\nKontroller at wifi er tændt\nStart denne app\npå en anden enhed",
            "camera": "Kamera",
            "remote": "Remote"
        }
    }
}

# Map script language codes to fastlane locale directory names
LANG_TO_LOCALE = {
    "en": "en-US",
    "es": "es-MX",
    "fr": "fr-FR",
    "da": "da",
    "it": "it",
    "pt": "pt-BR",
    "de": "de-DE",
}

def detect_package_manager():
    """Detect the appropriate package manager for the current system"""
    system = platform.system().lower()
    
    if system == "darwin":  # macOS
        # Check if Homebrew is available
        try:
            subprocess.run(["brew", "--version"], capture_output=True, check=True)
            return "brew"
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("⚠️  Homebrew not found. Please install it first:")
            print("   /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
            return None
    
    elif system == "linux":
        # Check for apt (Debian/Ubuntu)
        try:
            subprocess.run(["apt", "--version"], capture_output=True, check=True)
            return "apt"
        except (subprocess.CalledProcessError, FileNotFoundError):
            # Check for yum (RHEL/CentOS)
            try:
                subprocess.run(["yum", "--version"], capture_output=True, check=True)
                return "yum"
            except (subprocess.CalledProcessError, FileNotFoundError):
                print("⚠️  Unsupported Linux distribution. Please install librsvg manually.")
                return None
    
    elif system == "windows":
        # Check for Chocolatey
        try:
            subprocess.run(["choco", "--version"], capture_output=True, check=True)
            return "choco"
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("⚠️  Chocolatey not found. Please install it first:")
            print("   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))")
            return None
    
    return None

def install_rsvg_convert():
    """Install rsvg-convert using the appropriate package manager"""
    package_manager = detect_package_manager()
    
    if not package_manager:
        print("❌ Could not detect package manager. Please install librsvg manually:")
        print("   macOS: brew install librsvg")
        print("   Ubuntu/Debian: sudo apt install librsvg2-bin")
        print("   Windows: choco install librsvg")
        return False
    
    print(f"🔧 Installing librsvg using {package_manager}...")
    
    try:
        if package_manager == "brew":
            subprocess.run(["brew", "install", "librsvg"], check=True)
        elif package_manager == "apt":
            subprocess.run(["sudo", "apt", "update"], check=True)
            subprocess.run(["sudo", "apt", "install", "-y", "librsvg2-bin"], check=True)
        elif package_manager == "yum":
            subprocess.run(["sudo", "yum", "install", "-y", "librsvg2"], check=True)
        elif package_manager == "choco":
            subprocess.run(["choco", "install", "librsvg", "-y"], check=True)
        
        print("✅ librsvg installed successfully!")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to install librsvg: {e}")
        print("Please install it manually:")
        print("   macOS: brew install librsvg")
        print("   Ubuntu/Debian: sudo apt install librsvg2-bin")
        print("   Windows: choco install librsvg")
        return False

def check_rsvg_convert():
    """Check if rsvg-convert is available"""
    try:
        subprocess.run(["rsvg-convert", "--version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def check_inkscape():
    """Check if Inkscape is available"""
    # Check common Inkscape locations
    inkscape_paths = [
        "inkscape",  # If in PATH
        "/Applications/Inkscape.app/Contents/MacOS/inkscape",  # macOS app
        "/usr/bin/inkscape",  # Linux
        "/opt/homebrew/bin/inkscape",  # Homebrew
    ]
    
    for path in inkscape_paths:
        try:
            subprocess.run([path, "--version"], capture_output=True, check=True)
            return path
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    
    return None

def convert_svg_to_png_inkscape(svg_file, png_file, width, height):
    """Convert SVG to PNG using Inkscape"""
    inkscape_path = check_inkscape()
    if not inkscape_path:
        return False
    
    try:
        cmd = [
            inkscape_path,
            "--export-type=png",
            f"--export-width={width}",
            f"--export-height={height}",
            f"--export-filename={png_file}",
            str(svg_file)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"✅ Converted with Inkscape: {png_file.name}")
            return True
        else:
            print(f"❌ Inkscape failed to convert {svg_file.name}: {result.stderr}")
            return False
            
    except Exception as e:
        print(f"❌ Error converting with Inkscape {svg_file.name}: {e}")
        return False

def convert_svg_to_png(svg_file, png_file, width, height):
    """Convert SVG to PNG using rsvg-convert with Inkscape fallback"""
    try:
        cmd = [
            "rsvg-convert",
            "--width", str(width),
            "--height", str(height),
            "--format", "png",
            "--output", str(png_file),
            str(svg_file)
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print(f"✅ Converted: {png_file.name}")
            return True
        else:
            # rsvg-convert failed, try Inkscape as fallback
            print(f"⚠️  rsvg-convert failed, trying Inkscape...")
            if check_inkscape():
                return convert_svg_to_png_inkscape(svg_file, png_file, width, height)
            else:
                print(f"❌ Failed to convert {svg_file.name}: {result.stderr}")
                print("   Install Inkscape for better SVG compatibility")
                return False
            
    except Exception as e:
        print(f"❌ Error converting {svg_file.name}: {e}")
        # Try Inkscape as fallback
        if check_inkscape():
            return convert_svg_to_png_inkscape(svg_file, png_file, width, height)
        return False

def ensure_rsvg_convert():
    """Ensure rsvg-convert is available, install if needed"""
    if check_rsvg_convert():
        return True
    
    print("⚠️  rsvg-convert not found. Attempting to install...")
    
    # Ask user for permission
    response = input("Do you want to install librsvg automatically? (y/N): ").strip().lower()
    if response not in ['y', 'yes']:
        print("📄 PNG conversion will be skipped. Only SVG files will be generated.")
        return False
    
    return install_rsvg_convert()

def load_svg_template(template_name, device):
    """Load SVG template file and return its content"""
    template_dir = Path("svg_templates")
    template_file = template_dir / f"{template_name}_{device['name'].lower().replace(' ', '_')}.svg"
    
    if not template_file.exists():
        raise FileNotFoundError(f"SVG template not found: {template_file}")
    
    with open(template_file, 'r', encoding='utf-8') as f:
        return f.read()

def validate_svg_file(svg_file):
    """Validate SVG file and return True if valid"""
    try:
        with open(svg_file, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Basic SVG validation
        if not content.strip().startswith('<?xml'):
            return False, "Missing XML declaration"
        
        if '<svg' not in content:
            return False, "Missing SVG root element"
        
        if '</svg>' not in content:
            return False, "Missing closing SVG tag"
        
        # Check for mismatched tags (more reliable corruption indicator)
        if content.count('<svg') != content.count('</svg>'):
            return False, "Mismatched SVG tags"
        
        # Check for obvious XML syntax errors
        if content.count('<') != content.count('>'):
            return False, "Mismatched XML tags"
        
        return True, "Valid SVG"
        
    except Exception as e:
        return False, f"Error reading SVG: {e}"

def replace_text_in_svg(svg_content, lang, screenshot_type):
    """Replace placeholder text in SVG with localized content"""
    local_data = LOCALIZATIONS[lang][screenshot_type]
    
    # Replace various placeholder patterns
    replacements = {
        r'{{TITLE}}': local_data['title'],
        r'{{SUBTITLE}}': local_data['subtitle'],
        r'{{DESCRIPTION}}': local_data['description'],
        r'{{FEATURE}}': local_data['feature'],
        r'{{FEATURE_LINE1}}': local_data['feature'].split('\n')[0],
        r'{{FEATURE_LINE2}}': local_data['feature'].split('\n')[1] if len(local_data['feature'].split('\n')) > 1 else '',
        r'{{FEATURE_LINE3}}': local_data['feature'].split('\n')[2] if len(local_data['feature'].split('\n')) > 2 else '',
    }
    
    # Apply replacements
    for placeholder, replacement in replacements.items():
        svg_content = re.sub(placeholder, replacement, svg_content)
    
    return svg_content

def generate_svg_from_template(device_config, lang, screenshot_type, svg_work_dir, fastlane_dir, locale, png_enabled):
    """Generate SVG from template for specific device, language, and screenshot type.

    SVG intermediates go to svg_work_dir/<lang>/<device>/.
    PNGs go to fastlane_dir/<locale>/ with fastlane naming.
    """

    # Create SVG working directory (for intermediates)
    lang_dir = svg_work_dir / lang
    lang_dir.mkdir(exist_ok=True)
    device_dir = lang_dir / device_config['name'].lower().replace(' ', '_')
    device_dir.mkdir(exist_ok=True)

    # Load template using template_name field
    template_name = f"{screenshot_type}_{device_config['template_name']}.svg"
    template_path = Path("svg_templates") / template_name

    if not template_path.exists():
        print(f"❌ Template not found: {template_path}")
        return False

    # Load localization data
    lang_file = Path("localization") / f"{lang}.json"
    if not lang_file.exists():
        print(f"❌ Localization file not found: {lang_file}")
        return False

    with open(lang_file, 'r', encoding='utf-8') as f:
        lang_data = json.load(f)

    # Load template content
    with open(template_path, 'r', encoding='utf-8') as f:
        template_content = f.read()

    # Replace placeholders
    if screenshot_type == "screenshot1":
        replacements = {
            "{{TITLE}}": lang_data.get(screenshot_type, {}).get("title", ""),
            "{{SUBTITLE}}": lang_data.get(screenshot_type, {}).get("subtitle", ""),
            "{{DESCRIPTION}}": lang_data.get(screenshot_type, {}).get("description", "")
        }
    elif screenshot_type == "screenshot4":
        feature_lines = lang_data.get(screenshot_type, {}).get("feature", "").split('\n')
        replacements = {
            "{{FEATURE_LINE1}}": feature_lines[0] if len(feature_lines) > 0 else "",
            "{{FEATURE_LINE2}}": feature_lines[1] if len(feature_lines) > 1 else "",
            "{{FEATURE_LINE3}}": feature_lines[2] if len(feature_lines) > 2 else "",
            "{{FEATURE_LINE4}}": feature_lines[3] if len(feature_lines) > 3 else "",
            "{{FEATURE}}": lang_data.get(screenshot_type, {}).get("feature", ""),
            "{{CAMERA}}": lang_data.get(screenshot_type, {}).get("camera", "Camera"),
            "{{REMOTE}}": lang_data.get(screenshot_type, {}).get("remote", "Remote")
        }
    else:
        feature_lines = lang_data.get(screenshot_type, {}).get("feature", "").split('\n')
        replacements = {
            "{{FEATURE_LINE1}}": feature_lines[0] if len(feature_lines) > 0 else "",
            "{{FEATURE_LINE2}}": feature_lines[1] if len(feature_lines) > 1 else "",
            "{{FEATURE_LINE3}}": feature_lines[2] if len(feature_lines) > 2 else "",
            "{{FEATURE}}": lang_data.get(screenshot_type, {}).get("feature", "")
        }

    # Apply replacements
    for placeholder, value in replacements.items():
        template_content = template_content.replace(placeholder, value)

    # Write SVG intermediate
    svg_filename = f"{screenshot_type}_{lang}.svg"
    svg_path = device_dir / svg_filename
    with open(svg_path, 'w', encoding='utf-8') as f:
        f.write(template_content)
    print(f"Generated SVG: {svg_path}")

    # Convert to PNG with fastlane naming
    if png_enabled:
        # screenshot1 -> index 0, screenshot2 -> index 1, etc.
        screenshot_index = int(screenshot_type.replace("screenshot", "")) - 1
        fastlane_family = device_config['fastlane_family']

        # Fastlane naming: <index>_<DEVICE_FAMILY>_<index>.png
        png_filename = f"{screenshot_index}_{fastlane_family}_{screenshot_index}.png"
        locale_dir = fastlane_dir / locale
        locale_dir.mkdir(parents=True, exist_ok=True)
        png_path = locale_dir / png_filename

        if convert_svg_to_png(svg_path, png_path, device_config['width'], device_config['height']):
            print(f"✅ PNG: {png_path}")
            return True
        else:
            print(f"⚠️  PNG conversion failed for {svg_filename}")
            return False

    return True

def generate_all_screenshots():
    """Generate all screenshots for all devices and languages.

    SVG intermediates go to screenshots/.
    PNGs go to fastlane/screenshots/<locale>/ with fastlane naming.
    """

    # SVG working directory (intermediates)
    svg_work_dir = Path("screenshots")
    svg_work_dir.mkdir(exist_ok=True)

    # Fastlane output directory
    fastlane_dir = Path("fastlane") / "screenshots"
    fastlane_dir.mkdir(parents=True, exist_ok=True)

    # Create locale subdirectories
    for lang, locale in LANG_TO_LOCALE.items():
        (fastlane_dir / locale).mkdir(exist_ok=True)

    # Create templates directory if it doesn't exist
    templates_dir = Path("svg_templates")
    templates_dir.mkdir(exist_ok=True)

    print("🎨 Generating Remote Shutter Screenshots...")
    print(f"📁 SVG working directory: {svg_work_dir.absolute()}")
    print(f"📁 PNG output directory: {fastlane_dir.absolute()}")
    print(f"📁 Templates directory: {templates_dir.absolute()}")
    print()

    # Check and ensure converter availability
    png_enabled = ensure_rsvg_convert()
    inkscape_available = check_inkscape() is not None

    if png_enabled:
        print("✅ rsvg-convert found - PNG conversion enabled")
        if inkscape_available:
            print("✅ Inkscape found - will be used as fallback if rsvg-convert fails")
    elif inkscape_available:
        print("✅ Inkscape found - PNG conversion enabled")
        png_enabled = True
    else:
        print("⚠️  No SVG converters found - only SVG files will be generated")
        print("   Install rsvg-convert or Inkscape for PNG conversion")
    print()

    # Check if templates exist
    if not list(templates_dir.glob("*.svg")):
        print("⚠️  No SVG templates found!")
        print("📝 Please create SVG template files in the 'svg_templates' directory:")
        print("   - screenshot1_iphone_15_pro_max.svg")
        print("   - screenshot1_iphone_15_pro.svg")
        print("   - screenshot1_ipad_pro_11.svg")
        print("   - screenshot2_iphone_15_pro_max.svg")
        print("   - screenshot2_iphone_15_pro.svg")
        print("   - screenshot2_ipad_pro_11.svg")
        print("   - screenshot3_iphone_15_pro_max.svg")
        print("   - screenshot3_iphone_15_pro.svg")
        print("   - screenshot3_ipad_pro_11.svg")
        print("   - screenshot4_iphone_15_pro_max.svg")
        print("   - screenshot4_iphone_15_pro.svg")
        print("   - screenshot4_ipad_pro_11.svg")
        print()
        print("🔧 Template placeholders:")
        print("   {{TITLE}} - App title")
        print("   {{SUBTITLE}} - Subtitle text")
        print("   {{DESCRIPTION}} - Description text")
        print("   {{FEATURE}} - Full feature text")
        print("   {{FEATURE_LINE1}} - First line of feature text")
        print("   {{FEATURE_LINE2}} - Second line of feature text")
        print("   {{FEATURE_LINE3}} - Third line of feature text")
        return

    total_screenshots = len(DEVICES) * len(LOCALIZATIONS) * 4
    current = 0

    for lang in LOCALIZATIONS.keys():
        locale = LANG_TO_LOCALE[lang]
        print(f"🌍 Language: {lang} (locale: {locale})")

        for device_name, device_config in DEVICES.items():
            print(f"  📱 Device: {device_config['name']} ({device_config['fastlane_family']})")

            for i in range(1, 5):
                screenshot_type = f"screenshot{i}"
                generate_svg_from_template(
                    device_config, lang, screenshot_type,
                    svg_work_dir, fastlane_dir, locale, png_enabled
                )
                current += 1

            print(f"    ✅ Generated 4 screenshots ({current}/{total_screenshots})")

    print()
    print("🎉 All screenshots generated successfully!")
    print(f"📊 Total screenshots: {total_screenshots}")
    print(f"📱 Devices: {len(DEVICES)}")
    print(f"🌍 Languages: {len(LOCALIZATIONS)}")
    print(f"🖼️  Screenshots per device/language: 4")

    if png_enabled:
        print(f"📄 Format: SVG (working) + PNG (fastlane)")
        print(f"📏 PNG resolutions:")
        for device_name, device_config in DEVICES.items():
            print(f"   - {device_config['name']} ({device_config['fastlane_family']}): {device_config['width']} x {device_config['height']}")
    else:
        print(f"📄 Format: SVG only (install rsvg-convert or Inkscape for PNG conversion)")

    print()
    print("📁 Fastlane directory structure:")
    print("   fastlane/screenshots/")
    for lang, locale in LANG_TO_LOCALE.items():
        print(f"   ├── {locale}/")
        for device_name, device_config in DEVICES.items():
            family = device_config['fastlane_family']
            for i in range(4):
                print(f"   │   ├── {i}_{family}_{i}.png")

def create_localization_files():
    """Create JSON files for each language for easy editing"""
    loc_dir = Path("localization")
    loc_dir.mkdir(exist_ok=True)
    
    for lang, data in LOCALIZATIONS.items():
        filename = f"{lang}.json"
        filepath = loc_dir / filename
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"📝 Created localization file: {filename}")

def create_sample_templates():
    """Create sample SVG template files for each device resolution if they don't exist"""
    templates_dir = Path("svg_templates")
    templates_dir.mkdir(exist_ok=True)
    
    # Define all required template files
    required_templates = [
        "screenshot1_iphone_15_pro_max.svg",
        "screenshot2_iphone_15_pro_max.svg", 
        "screenshot3_iphone_15_pro_max.svg",
        "screenshot4_iphone_15_pro_max.svg",
        "screenshot1_iphone_15_pro.svg",
        "screenshot2_iphone_15_pro.svg",
        "screenshot3_iphone_15_pro.svg",
        "screenshot4_iphone_15_pro.svg",
        "screenshot1_ipad_pro_11.svg",
        "screenshot2_ipad_pro_11.svg",
        "screenshot3_ipad_pro_11.svg",
        "screenshot4_ipad_pro_11.svg",
        "screenshot1_ipad_pro_12.9.svg",
        "screenshot2_ipad_pro_12.9.svg",
        "screenshot3_ipad_pro_12.9.svg",
        "screenshot4_ipad_pro_12.9.svg"
    ]
    
    # Check which templates already exist
    existing_templates = []
    missing_templates = []
    
    for template in required_templates:
        template_path = templates_dir / template
        if template_path.exists():
            existing_templates.append(template)
        else:
            missing_templates.append(template)
    
    # If all templates exist, don't overwrite them
    if not missing_templates:
        print("📁 SVG templates already exist - preserving your custom designs")
        print("   If you want to regenerate templates, delete the svg_templates/ directory first")
        return
    
    # If some templates exist, warn user
    if existing_templates:
        print("⚠️  Some SVG templates already exist:")
        for template in existing_templates:
            print(f"   ✅ {template}")
        print("   These will be preserved. Only missing templates will be created.")
        print()
    
    # Create only missing templates
    print("📝 Creating missing SVG templates...")
    
    # iPhone 15 Pro Max (1290 x 2796)
    iphone_max_template1 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1290" height="2796" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1290" height="2796" fill="url(#greenGradient)"/>
    
    <!-- Main Text - iPhone 15 Pro Max positioning -->
    <text x="322" y="839" font-family="Arial, sans-serif" font-size="86" 
          font-weight="bold" fill="white">
        <tspan x="322" dy="0">{{TITLE}}</tspan>
        <tspan x="322" dy="107" font-size="103">{{SUBTITLE}}</tspan>
        <tspan x="322" dy="129" font-size="103">{{DESCRIPTION}}</tspan>
    </text>
    
    <!-- Device mockup - iPhone 15 Pro Max proportions -->
    <g transform="translate(774,839) rotate(-15)">
        <rect x="0" y="0" width="516" height="929" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="500" height="913" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
</svg>'''
    
    iphone_max_template2 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1290" height="2796" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient2" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1290" height="2796" fill="url(#greenGradient2)"/>
    
    <!-- Device mockup - iPhone 15 Pro Max proportions -->
    <g transform="translate(129,1677) rotate(-15)">
        <rect x="0" y="0" width="425" height="766" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="409" height="750" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPhone 15 Pro Max positioning -->
    <text x="774" y="559" font-family="Arial, sans-serif" font-size="64" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="774" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="774" dy="86">{{FEATURE_LINE2}}</tspan>
        <tspan x="774" dy="86">{{FEATURE_LINE3}}</tspan>
    </text>
</svg>'''
    
    # iPhone 15 Pro (1284 x 2778)
    iphone_template1 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1284" height="2778" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1284" height="2778" fill="url(#greenGradient)"/>
    
    <!-- Main Text - iPhone 15 Pro positioning -->
    <text x="321" y="833" font-family="Arial, sans-serif" font-size="86" 
          font-weight="bold" fill="white">
        <tspan x="321" dy="0">{{TITLE}}</tspan>
        <tspan x="321" dy="107" font-size="103">{{SUBTITLE}}</tspan>
        <tspan x="321" dy="129" font-size="103">{{DESCRIPTION}}</tspan>
    </text>
    
    <!-- Device mockup - iPhone 15 Pro proportions -->
    <g transform="translate(770,833) rotate(-15)">
        <rect x="0" y="0" width="514" height="925" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="498" height="909" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
</svg>'''
    
    iphone_template2 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1284" height="2778" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient2" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1284" height="2778" fill="url(#greenGradient2)"/>
    
    <!-- Device mockup - iPhone 15 Pro proportions -->
    <g transform="translate(128,1667) rotate(-15)">
        <rect x="0" y="0" width="423" height="762" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="407" height="746" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPhone 15 Pro positioning -->
    <text x="770" y="555" font-family="Arial, sans-serif" font-size="64" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="770" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="770" dy="86">{{FEATURE_LINE2}}</tspan>
        <tspan x="770" dy="86">{{FEATURE_LINE3}}</tspan>
    </text>
</svg>'''
    
    # iPad Pro 11" (1640 x 2360)
    ipad_template1 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1640" height="2360" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1640" height="2360" fill="url(#greenGradient)"/>
    
    <!-- Main Text - iPad Pro 11" positioning -->
    <text x="410" y="708" font-family="Arial, sans-serif" font-size="110" 
          font-weight="bold" fill="white">
        <tspan x="410" dy="0">{{TITLE}}</tspan>
        <tspan x="410" dy="137" font-size="132">{{SUBTITLE}}</tspan>
        <tspan x="410" dy="165" font-size="132">{{DESCRIPTION}}</tspan>
    </text>
    
    <!-- Device mockup - iPad Pro 11" proportions -->
    <g transform="translate(987,708) rotate(-15)">
        <rect x="0" y="0" width="656" height="944" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="640" height="928" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
</svg>'''
    
    ipad_template2 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1640" height="2360" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient2" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1640" height="2360" fill="url(#greenGradient2)"/>
    
    <!-- Device mockup - iPad Pro 11" proportions -->
    <g transform="translate(164,1416) rotate(-15)">
        <rect x="0" y="0" width="541" height="708" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="525" height="692" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPad Pro 11" positioning -->
    <text x="987" y="472" font-family="Arial, sans-serif" font-size="82" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="987" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="987" dy="110">{{FEATURE_LINE2}}</tspan>
        <tspan x="987" dy="110">{{FEATURE_LINE3}}</tspan>
    </text>
</svg>'''
    
    # Create special template for screenshot4 with CAMERA and REMOTE placeholders
    iphone_max_template4 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1290" height="2796" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient4" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1290" height="2796" fill="url(#greenGradient4)"/>
    
    <!-- Device mockup - iPhone 15 Pro Max proportions -->
    <g transform="translate(129,1677) rotate(-15)">
        <rect x="0" y="0" width="425" height="766" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="409" height="750" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPhone 15 Pro Max positioning -->
    <text x="774" y="559" font-family="Arial, sans-serif" font-size="64" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="774" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="774" dy="86">{{FEATURE_LINE2}}</tspan>
        <tspan x="774" dy="86">{{FEATURE_LINE3}}</tspan>
    </text>
    
    <!-- Camera and Remote labels -->
    <text x="322" y="2000" font-family="Arial, sans-serif" font-size="48" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="322" dy="0">{{CAMERA}}</tspan>
    </text>
    <text x="968" y="2000" font-family="Arial, sans-serif" font-size="48" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="968" dy="0">{{REMOTE}}</tspan>
    </text>
</svg>'''
    
    iphone_template4 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1284" height="2778" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient4" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1284" height="2778" fill="url(#greenGradient4)"/>
    
    <!-- Device mockup - iPhone 15 Pro proportions -->
    <g transform="translate(128,1667) rotate(-15)">
        <rect x="0" y="0" width="423" height="762" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="407" height="746" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPhone 15 Pro positioning -->
    <text x="770" y="555" font-family="Arial, sans-serif" font-size="64" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="770" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="770" dy="86">{{FEATURE_LINE2}}</tspan>
        <tspan x="770" dy="86">{{FEATURE_LINE3}}</tspan>
    </text>
    
    <!-- Camera and Remote labels -->
    <text x="321" y="1995" font-family="Arial, sans-serif" font-size="48" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="321" dy="0">{{CAMERA}}</tspan>
    </text>
    <text x="963" y="1995" font-family="Arial, sans-serif" font-size="48" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="963" dy="0">{{REMOTE}}</tspan>
    </text>
</svg>'''
    
    ipad_template4 = '''<?xml version="1.0" encoding="UTF-8"?>
<svg width="1640" height="2360" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="greenGradient4" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
            <stop offset="100%" style="stop-color:#2E7D32;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <!-- Background -->
    <rect width="1640" height="2360" fill="url(#greenGradient4)"/>
    
    <!-- Device mockup - iPad Pro 11" proportions -->
    <g transform="translate(164,1416) rotate(-15)">
        <rect x="0" y="0" width="541" height="708" rx="20" ry="20" 
              fill="#1a1a1a" stroke="#333" stroke-width="2"/>
        <rect x="8" y="8" width="525" height="692" rx="15" ry="15" 
              fill="#87CEEB"/>
    </g>
    
    <!-- Feature Text - iPad Pro 11" positioning -->
    <text x="987" y="472" font-family="Arial, sans-serif" font-size="82" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="987" dy="0">{{FEATURE_LINE1}}</tspan>
        <tspan x="987" dy="110">{{FEATURE_LINE2}}</tspan>
        <tspan x="987" dy="110">{{FEATURE_LINE3}}</tspan>
    </text>
    
    <!-- Camera and Remote labels -->
    <text x="410" y="1700" font-family="Arial, sans-serif" font-size="60" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="410" dy="0">{{CAMERA}}</tspan>
    </text>
    <text x="1230" y="1700" font-family="Arial, sans-serif" font-size="60" 
          font-weight="bold" fill="white" text-anchor="middle">
        <tspan x="1230" dy="0">{{REMOTE}}</tspan>
    </text>
</svg>'''
    
    # Create all device-specific templates
    templates = {
        "screenshot1_iphone_15_pro_max.svg": iphone_max_template1,
        "screenshot2_iphone_15_pro_max.svg": iphone_max_template2,
        "screenshot3_iphone_15_pro_max.svg": iphone_max_template2,  # Use same layout as screenshot2
        "screenshot4_iphone_15_pro_max.svg": iphone_max_template4,  # Use special template with CAMERA/REMOTE
        "screenshot1_iphone_15_pro.svg": iphone_template1,
        "screenshot2_iphone_15_pro.svg": iphone_template2,
        "screenshot3_iphone_15_pro.svg": iphone_template2,  # Use same layout as screenshot2
        "screenshot4_iphone_15_pro.svg": iphone_template4,  # Use special template with CAMERA/REMOTE
        "screenshot1_ipad_pro_11.svg": ipad_template1,
        "screenshot2_ipad_pro_11.svg": ipad_template2,
        "screenshot3_ipad_pro_11.svg": ipad_template2,  # Use same layout as screenshot2
        "screenshot4_ipad_pro_11.svg": ipad_template4,  # Use special template with CAMERA/REMOTE
        "screenshot1_ipad_pro_12.9.svg": ipad_template1,  # Use same layout as iPad Pro 11
        "screenshot2_ipad_pro_12.9.svg": ipad_template2,  # Use same layout as iPad Pro 11
        "screenshot3_ipad_pro_12.9.svg": ipad_template2,  # Use same layout as iPad Pro 11
        "screenshot4_ipad_pro_12.9.svg": ipad_template4,  # Use same layout as iPad Pro 11
    }
    
    # Only create missing templates
    created_count = 0
    for filename, content in templates.items():
        if filename in missing_templates:
            with open(templates_dir / filename, 'w', encoding='utf-8') as f:
                f.write(content)
            created_count += 1
    
    if created_count > 0:
        print(f"📝 Created {created_count} missing SVG templates:")
        for template in missing_templates:
            print(f"   - {template}")
        print("   Edit these files to create your custom designs for each device!")
    else:
        print("📁 All SVG templates already exist - no new templates created")

def help_with_custom_svg():
    """Provide guidance for using custom Inkscape SVG files"""
    print("\n🔧 Tips for using custom Inkscape SVG files:")
    print("=" * 50)
    print("1. **Export Settings**: When saving from Inkscape, use:")
    print("   - Format: SVG")
    print("   - Optimize SVG: OFF (to preserve placeholders)")
    print("   - Embed fonts: OFF")
    print("   - Convert text to path: OFF")
    print()
    print("2. **Placeholder Format**: Use these exact placeholders:")
    print("   - {{TITLE}} - App title")
    print("   - {{SUBTITLE}} - Subtitle text")
    print("   - {{DESCRIPTION}} - Description text")
    print("   - {{FEATURE}} - Full feature text")
    print("   - {{FEATURE_LINE1}} - First line of feature text")
    print("   - {{FEATURE_LINE2}} - Second line of feature text")
    print("   - {{FEATURE_LINE3}} - Third line of feature text")
    print()
    print("3. **File Naming**: Name your files exactly:")
    print("   - screenshot1_iphone_15_pro_max.svg")
    print("   - screenshot2_iphone_15_pro_max.svg")
    print("   - screenshot3_iphone_15_pro_max.svg")
    print("   - screenshot4_iphone_15_pro_max.svg")
    print("   - screenshot1_iphone_15_pro.svg")
    print("   - screenshot2_iphone_15_pro.svg")
    print("   - screenshot3_iphone_15_pro.svg")
    print("   - screenshot4_iphone_15_pro.svg")
    print("   - screenshot1_ipad_pro_11.svg")
    print("   - screenshot2_ipad_pro_11.svg")
    print("   - screenshot3_ipad_pro_11.svg")
    print("   - screenshot4_ipad_pro_11.svg")
    print("   - screenshot1_ipad_pro_12.9.svg")
    print("   - screenshot2_ipad_pro_12.9.svg")
    print("   - screenshot3_ipad_pro_12.9.svg")
    print("   - screenshot4_ipad_pro_12.9.svg")
    print()
    print("4. **Common Issues**:")
    print("   - If text doesn't replace: Check placeholder spelling")
    print("   - If SVG is corrupted: Re-export from Inkscape")
    print("   - If PNG fails: Ensure SVG is valid XML")
    print("   - Large files are normal and valid!")
    print("   - If rsvg-convert fails: Inkscape will be used as fallback")
    print()
    print("5. **Testing**: You can test your SVG with:")
    print("   rsvg-convert --version")
    print("   rsvg-convert input.svg --output test.png")
    print("   inkscape --export-type=png input.svg")
    print()
    print("6. **Large SVG Files**: If you have large files:")
    print("   python3 generate_screenshots.py --large-svg")
    print()
    print("7. **PNG Conversion**: The script supports:")
    print("   - rsvg-convert (primary)")
    print("   - Inkscape (fallback, more forgiving)")

def help_with_large_svg_files():
    """Provide guidance for handling large SVG files"""
    print("\n📏 Large SVG Files - This is Normal!")
    print("=" * 50)
    print("Large SVG files are NOT corrupted! They can be large due to:")
    print("   - Complex graphics and effects")
    print("   - Embedded fonts and resources")
    print("   - High-quality designs")
    print("   - Multiple layers and objects")
    print()
    print("✅ Your large SVG files are perfectly valid")
    print("✅ The script will now handle them correctly")
    print("✅ PNG conversion will work with large files")
    print()
    print("💡 If you lost work due to the previous bug:")
    print("   1. Check your backup or version control")
    print("   2. Re-export from Inkscape if needed")
    print("   3. The script now preserves large files correctly")

def check_template_compatibility(template_path):
    """Check if a custom template is compatible with the script"""
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check for required placeholders
        required_placeholders = ['{{TITLE}}', '{{SUBTITLE}}', '{{DESCRIPTION}}']
        found_placeholders = []
        
        for placeholder in required_placeholders:
            if placeholder in content:
                found_placeholders.append(placeholder)
        
        if not found_placeholders:
            print(f"⚠️  Template {template_path.name} has no placeholders")
            print("   Add {{TITLE}}, {{SUBTITLE}}, {{DESCRIPTION}} placeholders")
            return False
        
        # Validate SVG structure (without size restrictions)
        is_valid, msg = validate_svg_file(template_path)
        if not is_valid:
            print(f"❌ Template {template_path.name} is not a valid SVG: {msg}")
            return False
        
        # Check file size for informational purposes only
        file_size = len(content)
        if file_size > 1000000:  # More than 1MB
            print(f"✅ Template {template_path.name} is compatible (large file: {file_size/1000000:.1f}MB)")
        else:
            print(f"✅ Template {template_path.name} is compatible")
        print(f"   Found placeholders: {', '.join(found_placeholders)}")
        return True
        
    except Exception as e:
        print(f"❌ Error checking template {template_path.name}: {e}")
        return False

if __name__ == "__main__":
    print("🚀 Remote Shutter Screenshot Generator")
    print("=" * 50)
    
    # Check for help arguments
    if len(sys.argv) > 1:
        if sys.argv[1] in ['--help', '-h', 'help']:
            help_with_custom_svg()
            sys.exit(0)
        elif sys.argv[1] in ['--large-svg', 'large-svg']:
            help_with_large_svg_files()
            sys.exit(0)
    
    # Create localization files
    create_localization_files()
    print()
    
    # Create sample templates if needed
    templates_dir = Path("svg_templates")
    if not list(templates_dir.glob("*.svg")):
        print("📝 Creating sample SVG templates...")
        create_sample_templates()
        print()
    else:
        # Templates exist, check if we need to create any missing ones
        create_sample_templates()
        print()
        
        # Validate existing templates
        print("🔍 Validating existing templates...")
        all_valid = True
        for template_file in templates_dir.glob("*.svg"):
            if not check_template_compatibility(template_file):
                all_valid = False
        
        if not all_valid:
            print("\n💡 For help with custom SVG files, run:")
            print("   python3 generate_screenshots.py --help")
            print("   python3 generate_screenshots.py --large-svg")
        print()
    
    # Generate all screenshots
    generate_all_screenshots() 