cask "three-finger-salute" do
  version "1.0.3"
  sha256 "616595c8539497b4a9de77df4fd7a28417137908b9af894422f8f22cccec208b"

  url "https://github.com/axolotl-industries/three-finger-salute/releases/download/v1.0.3/ThreeFingerSalute.zip"
  name "Three Finger Salute"
  desc "Trackpad gestures for volume control and middle-click"
  homepage "https://ko-fi.com/axolotlindustries"

  app "Three Finger Salute.app"

  postflight do
    system_command "xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/Three Finger Salute.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Three Finger Salute",
    "~/Library/Preferences/Axolotl-Industries.Three-Finger-Salute.plist",
  ]

  caveats "If you experience issues opening the app, right-click 'Three Finger Salute' in your Applications folder and select 'Open'."
end
