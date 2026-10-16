# StatisticiansWorkbench — the macOS distribution of the Statistician's Workbench.
#
# The formula is named `statisticians-workbench`, not `workbench`, because Homebrew
# already has an unrelated cask called `workbench`: a bare `brew install workbench`
# resolves to the cask and never reaches this formula. The product's own name is the
# collision-free one. Only the Homebrew name differs — the artifact, its URL and the
# paths inside it all keep the `workbench` prefix.
#
# Installs a prebuilt artifact: three executables onto PATH, and under libexec the
# standalone frontend, the translation extract, the two-process service wrapper and the
# provisioning script, plus a licence file. ONE launchd service runs the wrapper, which
# starts the Go backend and the Node frontend together, because the backend serves
# no static files and Homebrew allows a formula only one service block.
#
# The version here is the macOS distribution's, from config/workbench-mac.version
# in workbench-mac. Each platform carries its own versioning. Database provisioning
# — including the existing-database guard — is not a formula step at all; it lives
# in the shipped workbench-provision script. See
# workbench-mac/docs/workbench-tap-plan.html.

class StatisticiansWorkbench < Formula
  desc "Self-hosted statistical analysis platform"
  homepage "https://workbench.sentuny.com"
  url "https://workbench-mac.sentuny.com/workbench/0.12.1/workbench-0.12.1-arm64.tar.gz"
  version "0.12.1"
  # Written by the build pipeline (stage 7 of scripts/build-workbench-artifact.sh)
  # once the artifact is confirmed served at this URL with exactly this value.
  # Homebrew verifies it on every install, so a wrong value fails closed rather
  # than installing silently. This is the sha256 of the published 0.12.1 artifact,
  # recomputed from the fetched bytes.
  sha256 "00f260b19d5b6d143242ad95ea1dbc37590d8848b1eafaa396196477f2713d5f"
  # Proprietary — all rights reserved. The terms ship in the keg as
  # LICENSE-ENDUSER.md; :cannot_represent is Homebrew's value for a licence that is
  # not an SPDX identifier, which the audit requires (the literal "Proprietary" is
  # rejected as non-standard).
  license :cannot_represent

  # Pinned and keg-only, so it cannot collide with a `node` the user already has
  # and will not move when Homebrew's `node` takes a new major. The frontend
  # service points at this keg by absolute path. Note that `npm` needs `node` on
  # PATH and this keg is unlinked — relevant to the build, not to this formula.
  depends_on "node@24"
  # The schema-model major the Windows installer also enforces.
  depends_on "postgresql@16"

  def install
    bin.install "bin/workbench-backend", "bin/workbench-seed", "bin/sawhorse"
    libexec.install "libexec/workbench/frontend", "libexec/workbench/translations",
                    "libexec/workbench/workbench-services",
                    "libexec/workbench/workbench-provision"
    prefix.install "LICENSE-ENDUSER.md"
  end

  # WARNING — database provisioning is not here, and cannot be.
  #
  # The plan puts provisioning in post_install, but `def post_install` is
  # deprecated in favour of `post_install_steps`, and that DSL is declarative file
  # preparation only — mkdir, touch, move, copy, symlink, write. It has no way to
  # run a command, and provisioning must run psql and sawhorse. So the mechanism
  # for provisioning is the shipped workbench-provision script, which the concierge
  # runs and the formula's caveats name (workbench-mac plan item W13).
  #
  # The existing-database guard is in that script too, as its first step. It cannot
  # live in this formula: Homebrew runs `install` inside a network sandbox, and a
  # unix-domain socket is network, so a psql here cannot reach PostgreSQL at all —
  # it raises, and any rescue turns the failure into "cannot determine", which
  # passes. Searching for the guard in this file is a dead end by design.
  #
  # What belongs here is what the steps DSL can express: the state directories.
  post_install_steps do
    mkdir_p "workbench", base: :var
    mkdir_p "log/workbench", base: :var
  end

  # The runtime configuration, in the one place a formula may keep state. Homebrew
  # forbids writing outside its prefix at install time, so this is not /etc.
  def env_file
    var/"workbench/workbench.env"
  end

  def caveats
    <<~EOS
      The database is not provisioned by the install. Do that once, then start the
      services:

        #{opt_libexec}/workbench-provision
        brew services start #{name}

      workbench-provision creates the database, applies the migrations, writes the
      runtime configuration under #{var}/workbench and seeds the reference data. It is
      idempotent, so it is also the step to re-run after an upgrade. It refuses to run
      if a "workbench" database already exists that this product did not create.
    EOS
  end

  # ONE service, not two. Homebrew stores a single service block per formula
  # (`Formula.service` → `@service_block`, read back by
  # `Service.new(self, &self.class.service)`), and there is no plural API — so a
  # second `service do` silently REPLACES the first rather than adding to it. Two
  # blocks once sat here, and the survivor was the frontend: the formula would then
  # have reported a successful install and started a frontend with no backend behind
  # it, which is worse than not starting at all.
  #
  # So the one service is the wrapper, which brings both processes up, waits for the
  # backend to listen before starting the frontend, and keeps the pair together —
  # exiting non-zero if either dies, which is what restarts it under `keep_alive`.
  # The script is in the keg (it arrives in the artifact) and takes its paths from the
  # environment below, so it follows this keg rather than hard-coding a prefix.
  service do
    run [opt_libexec/"workbench-services"]
    working_dir var/"workbench"
    environment_variables WORKBENCH_BACKEND:       opt_bin/"workbench-backend",
                          WORKBENCH_FRONTEND_DIR:  opt_libexec/"frontend",
                          WORKBENCH_NODE:          formula_opt_bin("node@24")/"node",
                          WORKBENCH_ENV_FILE:      var/"workbench/workbench.env",
                          WORKBENCH_BACKEND_PORT:  "8000",
                          WORKBENCH_FRONTEND_PORT: "3000"
    keep_alive true
    run_at_load true
  end

  test do
    assert_path_exists bin/"workbench-backend"
    assert_path_exists bin/"workbench-seed"
    assert_path_exists bin/"sawhorse"
    assert_path_exists libexec/"frontend/server.js"
    assert_path_exists libexec/"translations/translation.sql"
    assert_path_exists libexec/"workbench-services"
    assert_path_exists libexec/"workbench-provision"
  end
end
