# Homebrew Formula for DICOMKit CLI Tools
class Dicomkit < Formula
  desc "Pure Swift DICOM toolkit with 35 command-line utilities"
  homepage "https://github.com/Raster-Lab/DICOMKit"
  url "https://github.com/Raster-Lab/DICOMKit/archive/refs/tags/v3.1.0.tar.gz"
  sha256 "" # Will be filled in upon first release
  license "MIT"
  head "https://github.com/Raster-Lab/DICOMKit.git", branch: "main"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe

  def install
    # Build all CLI tools using Swift Package Manager
    system "swift", "build", "-c", "release", "--disable-sandbox"
    
    # Install all 35 CLI executables
    cli_tools = [
      "dicom-3d", "dicom-ai", "dicom-anon", "dicom-archive", "dicom-cloud",
      "dicom-compress", "dicom-convert", "dicom-dcmdir", "dicom-diff", "dicom-dump",
      "dicom-echo", "dicom-export", "dicom-image", "dicom-info", "dicom-json",
      "dicom-measure", "dicom-merge", "dicom-mpps", "dicom-mwl", "dicom-pdf",
      "dicom-pixedit", "dicom-qr", "dicom-query", "dicom-report", "dicom-retrieve",
      "dicom-script", "dicom-send", "dicom-split", "dicom-study", "dicom-tags",
      "dicom-uid", "dicom-validate", "dicom-viewer", "dicom-wado", "dicom-xml"
    ]
    
    cli_tools.each do |tool|
      bin.install ".build/release/#{tool}"
    end
    
    # Install documentation
    doc.install "README.md", "CHANGELOG.md", "LICENSE"
    doc.install "Documentation" if File.directory?("Documentation")
  end

  test do
    # Test a few representative CLI tools
    assert_match "DICOMKit", shell_output("#{bin}/dicom-info --version 2>&1")
    assert_match "Usage:", shell_output("#{bin}/dicom-convert --help")
    assert_match "DICOM", shell_output("#{bin}/dicom-validate --help")
  end
end
