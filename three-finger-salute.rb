cask "three-finger-salute" do
  version "1.1"
  sha256 "2a8dd9e570dc8a77299ce4d41861792c985c66b156ecf70cc5c0b7764fee4ee8"

  url "https://github.com/axolotl-industries/three-finger-salute/releases/download/v#{version}/ThreeFingerSalute.zip"
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
