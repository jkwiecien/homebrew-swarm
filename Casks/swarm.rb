cask "swarm" do
  version "1.0.0"
  sha256 "d26863b0e5059f32d1c5e67e2b319ebe60f13f6da994814d783cf95b0df9174f"

  url "https://github.com/jkwiecien/homebrew-swarm/releases/download/v#{version}/SWARM-#{version}.zip"
  name "SWARM"
  desc "Runs SWARM workers under their own app identity on macOS"
  homepage "https://github.com/jkwiecien/homebrew-swarm"

  depends_on macos: ">= :monterey"

  app "SWARM.app"

  # SWARM reads this file whenever it writes a worker LaunchAgent and runs the worker
  # under the program it names (SmartTechBrewery/swarm#1376).
  postflight do
    wrapper = "#{appdir}/SWARM.app/Contents/MacOS/swarm"
    config = File.expand_path("~/.swarm/launchd-wrapper")
    FileUtils.mkdir_p(File.dirname(config))
    File.write(config, "#{wrapper}\n")
  end

  # Only forget the wrapper if it is still ours, so a plist rewrite stops naming it.
  uninstall_postflight do
    config = File.expand_path("~/.swarm/launchd-wrapper")
    if File.exist?(config) && File.read(config).strip == "#{appdir}/SWARM.app/Contents/MacOS/swarm"
      File.delete(config)
    end
  end

  caveats <<~EOS
    Workers pick SWARM.app up the next time their LaunchAgent is written. To switch a
    running worker now (this restarts it):

      swarm-worker agent install --profile <worker-id>

    Before uninstalling, do the same after the uninstall so no LaunchAgent keeps
    naming the removed app.
  EOS
end
