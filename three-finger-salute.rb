cask "three-finger-salute" do
  version "1.0.1"
  sha256 "6cdf0541c4b1124b396b1ba3c208196d8122495c4ad4f9c4dd17221f2f07099f"

  url "https://github.com/axolotl-industries/three-finger-salute/releases/download/v1.0.1/ThreeFingerSalute.zip"
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
