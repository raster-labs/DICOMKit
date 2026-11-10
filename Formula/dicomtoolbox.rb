# Homebrew Cask for DICOMToolbox GUI Application
cask "dicomtoolbox" do
  version "3.0.0"
  sha256 "" # Will be filled in upon first release

  url "https://github.com/Raster-Lab/DICOMKit/releases/download/v#{version}/DICOMToolbox-#{version}.dmg"
  name "DICOMToolbox"
  desc "Native macOS GUI for DICOMKit command-line tools"
  homepage "https://github.com/Raster-Lab/DICOMKit"

  depends_on macos: ">= :tahoe"

  app "DICOMToolbox.app"

  zap trash: [
    "~/Library/Preferences/com.dicomkit.DICOMToolbox.plist",
    "~/Library/Caches/com.dicomkit.DICOMToolbox",
    "~/Library/Saved Application State/com.dicomkit.DICOMToolbox.savedState",
  ]
end
