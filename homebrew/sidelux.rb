cask "sidelux" do
  version "1.0.2"
  sha256 "19a2073207aeea8d427555185be6b298dfc11b59c8eaa39c49f9b05a2595f84b"

  url "https://github.com/hellocket/SideLux/releases/download/v#{version}/SideLux-#{version}.zip"
  name "SideLux"
  desc "Menu bar brightness control for external displays"
  homepage "https://github.com/hellocket/SideLux"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "SideLux.app"

  # SideLux isn't notarized by Apple. Clear the download quarantine so it opens
  # without the "can't verify" warning (the caveats below say so).
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/SideLux.app"],
        must_succeed: false
  end

  uninstall quit: "io.github.hellocket.sidelux"

  zap trash: "~/Library/Preferences/io.github.hellocket.sidelux.plist"

  caveats <<~EOS
    SideLux is not notarized by Apple, so this cask removed macOS's download
    quarantine from it. You can open it right away from Applications.

    To use the keyboard shortcuts (⌃F1/⌃F2 brightness, ⌃F10–F12 volume),
    turn on "Keyboard Shortcuts" in the menu and allow SideLux under
    System Settings > Privacy & Security > Accessibility.
  EOS
end
