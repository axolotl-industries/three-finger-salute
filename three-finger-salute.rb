cask "three-finger-salute" do
  version "1.0.2"
  sha256 "7439fbfff9a6f68099c69760d3dd44502cfe13415453d22b1567b65f98789b56"

  url "https://github.com/axolotl-industries/three-finger-salute/releases/download/v1.0.2/ThreeFingerSalute.zip"
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
