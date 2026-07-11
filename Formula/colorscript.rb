class Colorscript < Formula
  desc "Terminal color scripts runner"
  homepage "https://github.com/charitarthchugh/shell-color-scripts"
  url "https://codeload.github.com/charitarthchugh/shell-color-scripts/tar.gz/refs/heads/master"
  version "0.1.0"
  sha256 "cba68333f28921232eb2aba7a5757ef4b7d8bdad75f20f42743c184c942a6b93"
  license "MIT"

  def install
    libexec.install Dir["colorscripts"]
    inreplace "colorscript.sh", "/opt/shell-color-scripts/colorscripts", libexec/"colorscripts"
    inreplace "colorscript.sh", "#!/usr/bin/bash", "#!/bin/bash"
    inreplace "colorscript.sh", "/usr/bin/ls", "/bin/ls"
    bin.install "colorscript.sh" => "colorscript"
    zsh_completion.install "zsh_completion/_colorscript"
  end

  test do
    assert_match "Usage: colorscript", shell_output("#{bin}/colorscript --help")
  end
end
