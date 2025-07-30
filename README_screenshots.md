# Remote Shutter Screenshot Generator

This script generates localized SVG screenshots for the Remote Shutter app across different device sizes and languages. It uses device-specific SVG templates to ensure proper proportions without stretching.

## 📱 Supported Devices

- **iPhone 15 Pro Max**: 1290 x 2796 pixels
- **iPhone 15 Pro**: 1284 x 2778 pixels  
- **iPad Pro 11"**: 1640 x 2360 pixels

## 🌍 Supported Languages

- **English (en)**
- **Italian (it)**
- **French (fr)**
- **Spanish (es)**
- **Danish (da)**

## 🖼️ Screenshot Types

### Screenshot 1: "Take pictures from anywhere"
- Main text on left side (title, subtitle, description)
- Device positioned right side, tilted
- Shows people on a cliff formation
- UI overlay with timer and controls

### Screenshot 2: "Works from up to 50 feet away!"
- Device positioned bottom-left, tilted
- Shows landscape with mountains and sky
- Feature text in top-right area
- UI elements (camera and settings icons) on screen

## 🚀 Usage

### Prerequisites
- Python 3.6 or higher
- **rsvg-convert** (optional, for PNG export - will be installed automatically)
- No additional Python dependencies required

### Automatic Installation
The script will automatically detect your system and install the required dependencies:

- **macOS**: Uses Homebrew to install `librsvg`
- **Ubuntu/Debian**: Uses apt to install `librsvg2-bin`
- **RHEL/CentOS**: Uses yum to install `librsvg2`
- **Windows**: Uses Chocolatey to install `librsvg`

### Manual Installation (if automatic fails)
```bash
# macOS (using Homebrew)
brew install librsvg

# Ubuntu/Debian
sudo apt update && sudo apt install librsvg2-bin

# Windows (using Chocolatey)
choco install librsvg
```

### First Run (Creates Device-Specific Templates)
```bash
python3 generate_screenshots.py
```

This will:
- **Check for dependencies** and offer to install them automatically
- Create `svg_templates/` directory with device-specific templates
- Create `localization/` directory with JSON files
- Generate sample screenshots using properly proportioned templates
- **PNG files** (if rsvg-convert is installed) at exact device resolutions

### Template Management
The script intelligently manages SVG templates:

- **First Run**: Creates all required templates
- **Subsequent Runs**: Preserves existing templates, only creates missing ones
- **Custom Designs**: Your modified templates are never overwritten
- **Regeneration**: Delete `svg_templates/` directory to regenerate all templates

**Template Files**:
- `screenshot1_iphone_15_pro_max.svg` (1290 x 2796)
- `screenshot2_iphone_15_pro_max.svg` (1290 x 2796)
- `screenshot1_iphone_15_pro.svg` (1284 x 2778)
- `screenshot2_iphone_15_pro.svg` (1284 x 2778)
- `screenshot1_ipad_pro_11.svg` (1640 x 2360)
- `screenshot2_ipad_pro_11.svg` (1640 x 2360)

### Automatic Installation Process
When you run the script for the first time:

1. **Dependency Detection**: The script detects your operating system and package manager
2. **Permission Request**: Asks if you want to install `librsvg` automatically
3. **Installation**: Uses the appropriate package manager to install dependencies
4. **Verification**: Confirms the installation was successful

**Supported Systems**:
- ✅ macOS (Homebrew)
- ✅ Ubuntu/Debian (apt)
- ✅ RHEL/CentOS (yum)
- ✅ Windows (Chocolatey)

### Customizing Your Design

1. **Edit Device-Specific Templates**: Replace the templates in `svg_templates/` with your own designs
2. **Use Placeholders**: Include these placeholders in your SVG templates:
   - `{{TITLE}}` - App title
   - `{{SUBTITLE}}` - Subtitle text  
   - `{{DESCRIPTION}}` - Description text
   - `{{FEATURE}}` - Full feature text
   - `{{FEATURE_LINE1}}` - First line of feature text
   - `{{FEATURE_LINE2}}` - Second line of feature text
   - `{{FEATURE_LINE3}}` - Third line of feature text

3. **Regenerate Screenshots**: Run the script again to generate with your custom designs

### Using Custom Inkscape SVG Files

If you're creating SVG files with Inkscape or other design tools:

```bash
# Get help with custom SVG files
python3 generate_screenshots.py --help
```

**Key Tips**:
- Export as plain SVG (not optimized)
- Don't convert text to paths
- Use exact placeholder names: `{{TITLE}}`, `{{SUBTITLE}}`, etc.
- Name files exactly: `screenshot1_iphone_15_pro_max.svg`

### Troubleshooting

**SVG Validation**: The script now validates generated SVG files and warns about potential issues.

**Common Issues**:
- **Corrupted SVG**: Regenerate templates by deleting `svg_templates/` directory
- **Text not replacing**: Check placeholder spelling and format
- **PNG conversion fails**: Ensure SVG is valid XML
- **Large file sizes**: Re-export from Inkscape with optimization off

## 📁 File Structure

```
svg_templates/
├── screenshot1_iphone_15_pro_max.svg    # iPhone 15 Pro Max template (1290x2796)
├── screenshot2_iphone_15_pro_max.svg    # iPhone 15 Pro Max template (1290x2796)
├── screenshot1_iphone_15_pro.svg        # iPhone 15 Pro template (1284x2778)
├── screenshot2_iphone_15_pro.svg        # iPhone 15 Pro template (1284x2778)
├── screenshot1_ipad_pro_11.svg          # iPad Pro 11" template (1640x2360)
└── screenshot2_ipad_pro_11.svg          # iPad Pro 11" template (1640x2360)

localization/
├── en.json
├── it.json
├── fr.json
├── es.json
└── da.json

screenshots/
├── screenshot1_iphone_15_pro_max_en.svg
├── screenshot1_iphone_15_pro_max_en.png
├── screenshot1_iphone_15_pro_max_it.svg
├── screenshot1_iphone_15_pro_max_it.png
├── screenshot1_iphone_15_pro_max_fr.svg
├── screenshot1_iphone_15_pro_max_fr.png
├── screenshot1_iphone_15_pro_max_es.svg
├── screenshot1_iphone_15_pro_max_es.png
├── screenshot1_iphone_15_pro_max_da.svg
├── screenshot1_iphone_15_pro_max_da.png
├── screenshot2_iphone_15_pro_max_en.svg
├── screenshot2_iphone_15_pro_max_en.png
├── screenshot2_iphone_15_pro_max_it.svg
├── screenshot2_iphone_15_pro_max_it.png
├── screenshot2_iphone_15_pro_max_fr.svg
├── screenshot2_iphone_15_pro_max_fr.png
├── screenshot2_iphone_15_pro_max_es.svg
├── screenshot2_iphone_15_pro_max_es.png
├── screenshot2_iphone_15_pro_max_da.svg
├── screenshot2_iphone_15_pro_max_da.png
├── screenshot1_iphone_15_pro_en.svg
├── screenshot1_iphone_15_pro_en.png
├── screenshot1_iphone_15_pro_it.svg
├── screenshot1_iphone_15_pro_it.png
├── screenshot1_iphone_15_pro_fr.svg
├── screenshot1_iphone_15_pro_fr.png
├── screenshot1_iphone_15_pro_es.svg
├── screenshot1_iphone_15_pro_es.png
├── screenshot1_iphone_15_pro_da.svg
├── screenshot1_iphone_15_pro_da.png
├── screenshot2_iphone_15_pro_en.svg
├── screenshot2_iphone_15_pro_en.png
├── screenshot2_iphone_15_pro_it.svg
├── screenshot2_iphone_15_pro_it.png
├── screenshot2_iphone_15_pro_fr.svg
├── screenshot2_iphone_15_pro_fr.png
├── screenshot2_iphone_15_pro_es.svg
├── screenshot2_iphone_15_pro_es.png
├── screenshot2_iphone_15_pro_da.svg
├── screenshot2_iphone_15_pro_da.png
├── screenshot1_ipad_pro_11_en.svg
├── screenshot1_ipad_pro_11_en.png
├── screenshot1_ipad_pro_11_it.svg
├── screenshot1_ipad_pro_11_it.png
├── screenshot1_ipad_pro_11_fr.svg
├── screenshot1_ipad_pro_11_fr.png
├── screenshot1_ipad_pro_11_es.svg
├── screenshot1_ipad_pro_11_es.png
├── screenshot1_ipad_pro_11_da.svg
├── screenshot1_ipad_pro_11_da.png
├── screenshot2_ipad_pro_11_en.svg
├── screenshot2_ipad_pro_11_en.png
├── screenshot2_ipad_pro_11_it.svg
├── screenshot2_ipad_pro_11_it.png
├── screenshot2_ipad_pro_11_fr.svg
├── screenshot2_ipad_pro_11_fr.png
├── screenshot2_ipad_pro_11_es.svg
├── screenshot2_ipad_pro_11_es.png
├── screenshot2_ipad_pro_11_da.svg
└── screenshot2_ipad_pro_11_da.png
```

## 🎨 Device-Specific Template System

### Why Device-Specific Templates?
- **No Stretching**: Each template is designed for its specific resolution
- **Proper Proportions**: Device mockups and text positioning optimized for each size
- **Better Quality**: No distortion or scaling artifacts
- **Design Control**: You can fine-tune layouts for each device type

### Template Naming Convention
- `screenshot1_iphone_15_pro_max.svg` - iPhone 15 Pro Max (1290 x 2796)
- `screenshot1_iphone_15_pro.svg` - iPhone 15 Pro (1284 x 2778)
- `screenshot1_ipad_pro_11.svg` - iPad Pro 11" (1640 x 2360)

### Template Requirements
- Valid SVG format
- Include placeholders for text replacement
- **Already sized correctly** for the target device
- No dimension adjustment needed

## 🔧 Customization

### Adding New Languages
1. Edit the `LOCALIZATIONS` dictionary in `generate_screenshots.py`
2. Add your new language with the required text fields
3. Run the script again

### Modifying Text
1. Edit the JSON files in the `localization/` directory
2. Run the script again to regenerate all screenshots

### Creating Custom Templates
1. Design your SVG in any vector editor (Illustrator, Figma, etc.)
2. **Create separate designs for each device size** to maintain proper proportions
3. Export as SVG with the correct dimensions
4. Add placeholders where you want text to be replaced
5. Save with the correct naming convention in `svg_templates/`
6. Run the script

### Changing Device Sizes
1. Modify the `DEVICES` dictionary in `generate_screenshots.py`
2. Create new templates for the new device sizes
3. Update the width and height values as needed

## 🎨 SVG Features

- **Device-Specific**: Each template designed for its target resolution
- **No Stretching**: Proper proportions maintained across all devices
- **Text Replacement**: Placeholders automatically replaced with localized text
- **Professional Quality**: No scaling artifacts or distortion
- **Design Flexibility**: Full control over layout for each device type

## 📊 Generated Files Summary

- **Total Screenshots**: 30 SVG + 30 PNG (60 total files)
- **Devices**: 3 (iPhone Max, iPhone, iPad)
- **Languages**: 5 (English, Italian, French, Spanish, Danish)
- **Screenshot Types**: 2 (Feature showcase, Main app)
- **Formats**: SVG (scalable vector graphics) + PNG (raster images)
- **Quality**: No stretching or distortion
- **PNG Resolutions**: Exact device specifications

## 🔄 Regeneration

To regenerate all screenshots after making changes:
```bash
rm -rf screenshots/ localization/
python3 generate_screenshots.py
```

## 💡 Tips for Custom Templates

1. **Design for each device separately** to maintain proper proportions
2. **Use the exact dimensions** specified for each device
3. **Test placeholders** with different text lengths
4. **Keep designs simple** for better readability
5. **Use vector graphics** for crisp scaling
6. **Consider device aspect ratios** when positioning elements

## 🎯 Example Template Placeholder Usage

```xml
<!-- In your device-specific SVG template -->
<text x="774" y="559" font-family="Arial, sans-serif" font-size="64" 
      font-weight="bold" fill="white" text-anchor="middle">
    <tspan x="774" dy="0">{{FEATURE_LINE1}}</tspan>
    <tspan x="774" dy="86">{{FEATURE_LINE2}}</tspan>
    <tspan x="774" dy="86">{{FEATURE_LINE3}}</tspan>
</text>
```

This will be replaced with localized text when the script runs, maintaining the exact positioning for each device size. 