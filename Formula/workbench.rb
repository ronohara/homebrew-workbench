# Workbench — the macOS distribution of the Statistician's Workbench.
#
# Installs a prebuilt artifact: three executables onto PATH, the standalone
# frontend and the translation extract under libexec, and a licence file. Two
# launchd services run it — the Go backend and the Node frontend — because the
# backend serves no static files.
#
# The version here is the macOS distribution's, from config/workbench-mac.version
# in workbench-mac. Each platform carries its own versioning.
#
# Not installable until the artifact is published: the url 404s and the sha256 is
# a placeholder. See workbench-mac/docs/workbench-tap-plan.html.

class Workbench < Formula
  desc "Self-hosted statistical analysis platform"
  homepage "https://workbench.sentuny.com"
  url "https://workbench-mac.sentuny.com/workbench/0.12.1/workbench-0.12.1-arm64.tar.gz"
  version "0.12.1"
  # Written by the build pipeline (stage 7 of scripts/build-workbench-artifact.sh)
  # once the artifact is confirmed served at this URL with exactly this value.
  # Homebrew verifies it on every install, so a wrong value fails closed rather
  # than installing silently.
  sha256 "18c1edae8030b527f8340ac28f1f39c1d5e12ad14cf02a596aea9e75e6171c2f"
  license "Proprietary"

  # Pinned and keg-only, so it cannot collide with a `node` the user already has
  # and will not move when Homebrew's `node` takes a new major. The frontend
  # service points at this keg by absolute path. Note that `npm` needs `node` on
  # PATH and this keg is unlinked — relevant to the build, not to this formula.
  depends_on "node@24"
  # The schema-model major the Windows installer also enforces.
  depends_on "postgresql@16"

  def install
    check_existing_database!

    bin.install "bin/workbench-backend", "bin/workbench-seed", "bin/sawhorse"
    libexec.install "libexec/workbench/frontend", "libexec/workbench/translations"
    prefix.install "LICENSE-ENDUSER.md"
  end

  # WARNING — database provisioning is not here, and cannot be.
  #
  # The plan puts provisioning in post_install, but `def post_install` is
  # deprecated in favour of `post_install_steps`, and that DSL is declarative file
  # preparation only — mkdir, touch, move, copy, symlink, write. It has no way to
  # run a command, and provisioning must run psql and sawhorse. So the mechanism
  # for provisioning is an open question, not a settled one.
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

  # A hard fail when a `workbench` database exists that this installation did not
  # create. sawhorse's ensureDatabase checks only whether the *name* exists, and
  # the step after it applies every pending migration — so without this guard an
  # unrelated database with that name would have the Workbench schema built inside
  # it. The ownership signal is goose_db_version, which goose creates on the first
  # migration.
  #
  # Runs in `install` rather than `post_install`, so the failure happens before the
  # formula is linked: `install` aborts the whole installation, whereas a
  # post_install failure leaves something that looks installed and is not.
  def check_existing_database!
    psql = formula_opt_bin("postgresql@16")/"psql"
    return unless psql.exist?

    db = "workbench"

    # A psql that cannot connect — server not running, say — yields nil, and the
    # guard then cannot determine anything, so it passes. It protects against a
    # database it can see, which is the case that matters.
    exists = psql_query(psql, "SELECT 1 FROM pg_database WHERE datname = '#{db}'", "postgres")
    return if exists != "1"

    ours = psql_query(psql, "SELECT to_regclass('public.goose_db_version') IS NOT NULL", db)
    return if ours == "t"

    tables = psql_query(psql, "SELECT count(*) FROM information_schema.tables " \
                              "WHERE table_schema = 'public'", db).to_i
    # An empty database is what an interrupted install leaves behind; nothing can
    # be lost by proceeding, and refusing here would leave the flow unable to
    # resume.
    return if tables.zero?

    odie <<~EOS
      Refusing to install: a "#{db}" database already exists on this machine that
      this installation did not create.

      It contains #{tables} tables but has no goose_db_version table, so the
      Workbench has never migrated it. Installing would apply the Workbench schema
      to it.

      If that database is yours, move it aside or remove it, then install again:

        dropdb #{db}

      This installation has changed nothing.
    EOS
  end

  # One query, or nil when psql could not answer at all.
  def psql_query(psql, sql, db)
    Utils.safe_popen_read(psql.to_s, "-tAc", sql, db).strip
  rescue ErrorDuringExecution
    nil
  end

  service do
    run [opt_bin/"workbench-backend"]
    working_dir var/"workbench"
    environment_variables PORT: "8000"
    keep_alive true
    run_at_load true
  end

  service do
    name "frontend"
    run [formula_opt_bin("node@24")/"node", opt_libexec/"frontend/server.js"]
    working_dir opt_libexec/"frontend"
    environment_variables PORT: "3000", HOSTNAME: "127.0.0.1"
    keep_alive true
    run_at_load true
  end

  test do
    assert_path_exists bin/"workbench-backend"
    assert_path_exists bin/"workbench-seed"
    assert_path_exists bin/"sawhorse"
    assert_path_exists libexec/"frontend/server.js"
    assert_path_exists libexec/"translations/translation.sql"
  end
end
