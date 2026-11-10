cask "sidelux" do
  version "1.0.1"
  sha256 "6c39b32f0dea6723ae104b871b3c3343713898d89ed3cb8699e67af6af5da915"

  url "https://github.com/hellocket/SideLux/releases/download/v#{version}/SideLux-#{version}.zip"
  name "SideLux"
  desc "Menu bar brightness control for external displays"
  homepage "https://github.com/hellocket/SideLux"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "SideLux.app"

  # SideLux isn't notarized by Apple. Clear the download quarantine so it opens
  # without the "can't verify" warning (the caveats below say so).
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/SideLux.app"]
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
