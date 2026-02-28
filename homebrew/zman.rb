cask "zman" do
  version "1.2.0"
  sha256 "f6502319e2563250f8763113774ded098d0409ed4dd6ea94b7a579fdf0d3ca9f"

  url "https://github.com/plavrenko/zman/releases/download/v#{version}/Zman-claude-#{version}.zip"
  name "Zman"
  desc "Highlights Calendar.app when viewing timezone differs from team timezone"
  homepage "https://github.com/plavrenko/zman"

  depends_on macos: ">= :tahoe"

  app "Zman-claude.app"

  caveats <<~EOS
    Zman is not notarized. After installation, remove the quarantine attribute:
      xattr -cr "#{appdir}/Zman-claude.app"
  EOS
end
