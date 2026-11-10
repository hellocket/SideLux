cask "sidelux" do
  version "1.0.0"
  sha256 "b40c465f142ed165fcc7cf4a37e2b82bfd2b609fbc76213f10148a384b98a9f0"

  url "https://github.com/hellocket/SideLux/releases/download/v#{version}/SideLux-#{version}.zip"
  name "SideLux"
  desc "Menu bar brightness control for external displays"
  homepage "https://github.com/hellocket/SideLux"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "SideLux.app"

  uninstall quit: "io.github.hellocket.sidelux"

  zap trash: "~/Library/Preferences/io.github.hellocket.sidelux.plist"

  caveats <<~EOS
    SideLux is not notarized by Apple. If macOS says it can't be opened,
    go to System Settings > Privacy & Security and click "Open Anyway".

    To use the keyboard shortcuts (⌃F1/⌃F2 brightness, ⌃F10–F12 volume),
    turn on "Keyboard Shortcuts" in the menu and allow SideLux under
    System Settings > Privacy & Security > Accessibility.
  EOS
end
