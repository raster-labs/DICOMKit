# dicom-ai - AI/ML Integration for DICOM Images

AI/ML integration tool for DICOM image analysis, enhancement, and automated reporting. Supports CoreML models on Apple platforms with support for classification, segmentation, detection, and image enhancement tasks.

## Features

### Model Support
- **CoreML Models**: Native Swift CoreML model inference on Apple platforms
- **ONNX Models**: Support via CoreML conversion (requires coremltools)
- **Custom Models**: Load user-trained models
- **GPU Acceleration**: Automatic use of Metal Performance Shaders and Neural Engine

### Analysis Tasks
- **Classification**: Image classification (modality, anatomy, pathology detection)
- **Segmentation**: Organ/lesion segmentation with mask generation
- **Detection**: Object/lesion detection with bounding boxes
- **Enhancement**: Image denoising, super-resolution, quality improvement
- **Batch Processing**: Efficient batch inference on multiple files

### Output Options
- **JSON**: Structured prediction results
- **Text**: Human-readable formatted output
- **CSV**: Spreadsheet-compatible format
- **DICOM SR**: a PS3.16 TID 1500 Measurement Report (Comprehensive SR): Algorithm Name / Version (TID 4019), and per finding a Measurement Group with the label and its Certainty of Finding (111012, DCM) in percent, inferred from the image or the bounding box
- **DICOM SEG**: Create Segmentation objects from AI masks
- **GSPS**: Grayscale Presentation State with AI annotations (library function; no subcommand writes it yet)
- **Enhanced DICOM**: AI-processed pixel data saved as a derived image (Image Type DERIVED\SECONDARY, Source Image Sequence) of the source SOP Class
- **Markdown**: Markdown-formatted analysis reports

## Installation

```bash
swift build -c release
cp .build/release/dicom-ai /usr/local/bin/
```

## Usage

### Classification

Classify DICOM images using trained CoreML models.

```bash
# Basic classification
dicom-ai classify chest-xray.dcm --model pneumonia-detector.mlmodel

# With confidence threshold and output file
dicom-ai classify chest-xray.dcm \
  --model pneumonia-detector.mlmodel \
  --confidence 0.7 \
  --output results.json

# Get top 10 predictions
dicom-ai classify brain-mri.dcm \
  --model brain-pathology.mlmodel \
  --top-k 10 \
  --format text

# Verbose output for debugging
dicom-ai classify scan.dcm \
  --model classifier.mlmodel \
  --verbose
```

### Segmentation

Segment anatomical structures or lesions using trained models.

```bash
# Basic segmentation
dicom-ai segment abdomen-ct.dcm --model organ-segmentation.mlmodel

# Output as DICOM Segmentation object
dicom-ai segment abdomen-ct.dcm \
  --model organ-segmentation.mlmodel \
  --output segmentation.dcm \
  --format dicom-seg \
  --labels organ-labels.json

# JSON output
dicom-ai segment ct.dcm \
  --model liver-seg.mlmodel \
  --output seg-results.json \
  --format json
```

### Detection

Detect objects or lesions with bounding boxes.

```bash
# Basic detection
dicom-ai detect brain-mri.dcm --model lesion-detector.mlmodel

# With confidence and IoU thresholds
dicom-ai detect brain-mri.dcm \
  --model lesion-detector.mlmodel \
  --confidence 0.7 \
  --iou-threshold 0.5 \
  --max-detections 10

# CSV output
dicom-ai detect chest-xray.dcm \
  --model nodule-detector.mlmodel \
  --output detections.csv \
  --format csv
```

### Enhancement

Enhance image quality using AI models.

```bash
# Denoise image
dicom-ai enhance noisy-image.dcm \
  --model denoising-model.mlmodel \
  --output denoised.dcm

# Super-resolution
dicom-ai enhance low-res.dcm \
  --model super-resolution.mlmodel \
  --output high-res.dcm

# With verbose output
dicom-ai enhance scan.dcm \
  --model enhancer.mlmodel \
  --output enhanced.dcm \
  --verbose
```

### Batch Processing

Process multiple DICOM files efficiently.

```bash
# Batch classification
dicom-ai batch series/*.dcm \
  --model classifier.mlmodel \
  --output results.csv \
  --format csv

# JSON output
dicom-ai batch study/*.dcm \
  --model pathology-detector.mlmodel \
  --output batch-results.json \
  --format json \
  --confidence 0.6

# With batch size
dicom-ai batch large-series/*.dcm \
  --model classifier.mlmodel \
  --output results.csv \
  --batch-size 16 \
  --verbose
```

## Model Preparation

### CoreML Models

dicom-ai works with CoreML models (.mlmodel or .mlmodelc files). 

#### Converting ONNX to CoreML

If you have an ONNX model, convert it to CoreML using Apple's coremltools:

```python
import coremltools as ct

# Load ONNX model
model = ct.converters.onnx.convert(
    model='model.onnx',
    minimum_ios_deployment_target='17.0'
)

# Save as CoreML model
model.save('model.mlmodel')
```

#### Model Input Requirements

Models should accept image inputs in one of these formats:
- **Image**: Standard image input (height × width × channels)
- **MultiArray**: Numerical array input (for preprocessed data)
- **PixelBuffer**: CVPixelBuffer input

Models should output:
- **Classification**: Dictionary of {label: probability} or MultiArray of probabilities
- **Segmentation**: MultiArray with shape (height, width, num_classes)
- **Detection**: MultiArray or structured output with bounding boxes and confidence
- **Enhancement**: MultiArray or Image with enhanced pixel data

### Labels File

For segmentation with class labels, provide a JSON file:

```json
{
  "labels": [
    "background",
    "liver",
    "kidney",
    "spleen",
    "pancreas"
  ]
}
```

Or simply:

```json
["background", "liver", "kidney", "spleen", "pancreas"]
```

## Common Options

- `--model, -m`: Path to CoreML model file (.mlmodel or .mlmodelc)
- `--output, -o`: Output file path (default: print to stdout)
- `--format, -f`: Output format (json, text, csv, dicom-sr, dicom-seg)
- `--confidence`: Minimum confidence threshold (0.0-1.0, default: 0.5)
- `--frame`: Frame index for multi-frame images (default: 0)
- `--algorithm-version`: Algorithm Version (111003, DCM) written in dicom-sr output (default: the model's CoreML version metadata, else "unknown")
- `--force`: Force parsing of files without DICM prefix
- `--verbose`: Verbose output for debugging

## Output Formats

### JSON Output (Classification)

```json
{
  "file": "chest-xray.dcm",
  "predictions": [
    {
      "label": "pneumonia",
      "confidence": 0.87
    },
    {
      "label": "normal",
      "confidence": 0.13
    }
  ]
}
```

### CSV Output (Classification)

```csv
file,label,confidence
chest-xray.dcm,pneumonia,0.87
chest-xray.dcm,normal,0.13
```

### JSON Output (Detection)

```json
{
  "file": "brain-mri.dcm",
  "detections": [
    {
      "label": "lesion",
      "confidence": 0.92,
      "bbox": [120, 150, 45, 38]
    }
  ]
}
```

### CSV Output (Detection)

```csv
file,label,confidence,x,y,width,height
brain-mri.dcm,lesion,0.92,120,150,45,38
```

## Platform Support

- **macOS 14.0+**: Full support with CoreML, Metal, and Neural Engine
- **iOS 17.0+**: Full support (when compiled for iOS)
- **visionOS 1.0+**: Full support (when compiled for visionOS)
- **Linux**: Not supported (CoreML not available)

## Advanced Features (Phase B)

### Model Registry (Phase D)

Manage AI models with versioning and metadata tracking:

```bash
# Add a model to the registry
dicom-ai registry add \
  --name pneumonia-detector \
  --path /path/to/model.mlmodel \
  --version 1.0.0 \
  --type classification \
  --description "Pneumonia detection from chest X-rays" \
  --input-width 224 \
  --input-height 224 \
  --output-type classification \
  --tags chest,xray,pneumonia

# List all models in registry
dicom-ai registry list

# List models by type
dicom-ai registry list --type classification

# Get detailed info about a model
dicom-ai registry info --name pneumonia-detector

# Search models by tags
dicom-ai registry search --tags chest,xray

# Remove a model from registry
dicom-ai registry remove --name old-model

# Clear all models (requires confirmation)
dicom-ai registry clear --confirm
```

### Performance Profiling (Phase D)

Track inference performance metrics:

```bash
# Enable performance profiling
dicom-ai classify image.dcm \
  --model classifier.mlmodel \
  --profile

# Save metrics to file
dicom-ai classify image.dcm \
  --model classifier.mlmodel \
  --profile \
  --profile-output metrics.json

# Profiling output includes:
# - Preprocessing time
# - Inference time
# - Postprocessing time
# - Total time
# - Memory usage
```

### Enhanced Preprocessing

Control image preprocessing with various normalization strategies:

```bash
# Use ImageNet normalization (mean/std)
dicom-ai classify image.dcm \
  --model resnet50.mlmodel \
  --preprocessing imagenet

# Min-max normalization
dicom-ai classify image.dcm \
  --model custom-model.mlmodel \
  --preprocessing minmax \
  --min 0.0 --max 1.0

# Z-score normalization
dicom-ai classify image.dcm \
  --model custom-model.mlmodel \
  --preprocessing zscore \
  --mean 0.485 --std 0.229
```

### Ensemble Inference

Combine predictions from multiple models for improved accuracy:

```bash
# Average ensemble (default)
dicom-ai classify image.dcm \
  --models model1.mlmodel,model2.mlmodel,model3.mlmodel \
  --ensemble average \
  --output results.json

# Voting ensemble
dicom-ai classify image.dcm \
  --models model1.mlmodel,model2.mlmodel,model3.mlmodel \
  --ensemble voting

# Weighted ensemble
dicom-ai classify image.dcm \
  --models model1.mlmodel,model2.mlmodel,model3.mlmodel \
  --ensemble weighted \
  --weights 0.5,0.3,0.2

# Max confidence ensemble
dicom-ai classify image.dcm \
  --models model1.mlmodel,model2.mlmodel \
  --ensemble max
```

### Batch Processing

Efficiently process multiple files with batch inference:

```bash
# Batch classify with CSV output
dicom-ai batch series/*.dcm \
  --model classifier.mlmodel \
  --output results.csv \
  --format csv \
  --batch-size 8

# Batch with custom confidence
dicom-ai batch studies/**/*.dcm \
  --model detector.mlmodel \
  --confidence 0.8 \
  --output batch-results.json
```

### Post-Processing

Apply post-processing to refine results:

```bash
# Detection with NMS (Non-Maximum Suppression)
dicom-ai detect image.dcm \
  --model detector.mlmodel \
  --confidence 0.7 \
  --iou-threshold 0.5 \
  --max-detections 10

# Confidence filtering
dicom-ai classify image.dcm \
  --model classifier.mlmodel \
  --confidence 0.9 \
  --top-k 3
```

## Performance Tips

1. **Use Compiled Models**: Pre-compile .mlmodel files to .mlmodelc for faster loading
2. **GPU Acceleration**: Ensure models are configured to use GPU/Neural Engine
3. **Batch Processing**: Use the batch command for processing multiple files
4. **Model Optimization**: Use Core ML model optimization tools for better performance
5. **Ensemble Size**: Balance accuracy vs. performance (3-5 models recommended)
6. **Preprocessing**: Use appropriate normalization for your model's training data

## Examples

### Medical Imaging Workflows

#### Pneumonia Detection Pipeline

```bash
# 1. Classify chest X-rays
dicom-ai classify chest-xray.dcm \
  --model pneumonia-detector.mlmodel \
  --output classification.json \
  --confidence 0.8

# 2. If positive, segment affected areas
dicom-ai segment chest-xray.dcm \
  --model lung-segmentation.mlmodel \
  --output segmentation.json
```

#### Brain Lesion Analysis

```bash
# 1. Detect lesions
dicom-ai detect brain-mri.dcm \
  --model lesion-detector.mlmodel \
  --output detections.json \
  --confidence 0.75

# 2. Segment detected lesions
dicom-ai segment brain-mri.dcm \
  --model lesion-segmentation.mlmodel \
  --output lesion-mask.json
```

#### Image Quality Enhancement

```bash
# Enhance low-quality scans
dicom-ai enhance noisy-scan.dcm \
  --model denoising-model.mlmodel \
  --output enhanced-scan.dcm
```

## Limitations

### Current Limitations

1. **Python Bridge**: Direct TensorFlow/PyTorch inference not yet supported (use ONNX→CoreML conversion)
2. **Model Formats**: Only CoreML models supported on Apple platforms
3. **Preprocessing**: Advanced image transformations (rotation, augmentation) not yet implemented

### Phase B Features (✅ Completed)

- ✅ Enhanced preprocessing pipelines with normalization strategies
- ✅ Ensemble inference (multiple models with averaging, voting, weighted)
- ✅ Batch processing with parallel inference
- ✅ Post-processing (NMS, confidence filtering, thresholding)

### Phase C Features (✅ Completed)

- ✅ DICOM Structured Report (SR) generation from classification and detection predictions
- ✅ DICOM Segmentation (SEG) object creation from AI segmentation masks
- ✅ GSPS (Grayscale Presentation State) with AI annotations (bounding boxes, labels) — library function, not yet reachable from a subcommand
- ✅ Enhanced DICOM file creation with AI-processed pixel data
- ✅ Text, detection, and markdown report generation

### Planned Features (Phase D) - 🚧 IN PROGRESS

#### Completed:
- ✅ Model registry and versioning system (ModelRegistry class with add/remove/list/search operations)
- ✅ Performance profiling and metrics tracking (PerformanceMetrics and PerformanceProfiler classes)
- ✅ Model caching for faster repeated loads (ModelCache class with LRU eviction)
- ✅ Registry CLI subcommands (add, list, remove, search, info, clear)
- ✅ Performance profiling CLI flags (--profile, --profile-output)
- ✅ 9 additional unit tests for Phase D functionality

#### Remaining:
- Sample models for demo/testing purposes (requires creating example CoreML models)
- Full integration testing on macOS (current implementation is Linux-incompatible as expected for CoreML)
- Documentation updates for registry and profiling features

## Troubleshooting

### Model Loading Issues

```
Error: Failed to load CoreML model
```

**Solutions:**
- Ensure model file exists and has correct extension (.mlmodel or .mlmodelc)
- Verify model is compatible with target platform (macOS 14+, iOS 17+)
- Check model was saved with correct minimum deployment target

### Memory Issues with Large Images

```
Error: Out of memory during inference
```

**Solutions:**
- Process images one at a time instead of batch mode
- Reduce image resolution if model supports it
- Use models optimized for memory efficiency

### Incorrect Predictions

**Debugging steps:**
1. Use `--verbose` flag to see preprocessing steps
2. Verify DICOM image is correctly parsed (check dimensions, pixel spacing)
3. Ensure model was trained on similar data
4. Check confidence threshold isn't filtering out results

## See Also

- `dicom-info` - Display DICOM metadata
- `dicom-convert` - Convert between formats
- `dicom-report` - Generate clinical reports from DICOM SR
- `dicom-measure` - Medical image measurements

## Version

dicom-ai v1.4.0 - Part of DICOMKit Phase 7 CLI Tools

## License

See LICENSE file in the DICOMKit repository.
