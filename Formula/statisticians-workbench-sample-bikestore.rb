# StatisticiansWorkbenchSampleBikestore — the BikeStore sample installer for macOS.
#
# A second formula, not a mode of the first: the sample is independently versioned,
# independently removable, and a user who never installs it never downloads it. That
# mirrors debian/ and sample-bikestore-deb/ on Linux, and it is why this formula
# declares `depends_on "statisticians-workbench"` — the sample registers rows in the
# Workbench's database through its API, so a machine with no Workbench has nothing to
# register against.
#
# THE VERSION HERE IS THE SAMPLE'S OWN, and it is not connected to the Workbench's.
# Two packages, two version files, two set-version scripts, each build reading only
# its own — the convention already used by workbench-win and workbench-linux, and the
# user's rule, 2026-11-24: "the version of the workbench and the sample are set by
# separate scripts ... they are not connected and should not be". The Workbench may
# move to 0.12.2-20 while this stays at 0.12.2-3, and nothing breaks.
#
# THE APP IS ALSO DISTRIBUTED BY CURL (website/…/installer/install-sample.sh), and
# that is not duplication: the bootstrap installs the app for the items before a tap
# existed, and the tap wraps the same binary with the script, the loader and the CSV
# data that provisioning needs. Both paths land in different places — the curl route
# in ~/Library/Application Support/sample-bikestore-concierge, this one in the keg —
# so they cannot overwrite each other.
class StatisticiansWorkbenchSampleBikestore < Formula
  desc "BikeStore sample environment for the Statistician's Workbench"
  homepage "https://workbench.sentuny.com"
  url "https://workbench-mac.sentuny.com/workbench-sample/0.12.2-9/workbench-sample-bikestore-0.12.2-9-arm64.tar.gz"
  version "0.12.2-9"
  # Written by the sample's own build pipeline (stage 7 of
  # scripts/build-sample-artifact.sh) once the artifact is confirmed served at this
  # URL with exactly this value. Homebrew verifies it on every install, so a wrong
  # value fails closed rather than installing silently.
  sha256 "6fcd9be9ece6b0c708814e00f8215bc55a126c108715e2fa6d2128ed703f83d2"
  # Proprietary — all rights reserved, under the Workbench's end-user licence.
  license :cannot_represent

  # The sample registers an account, a connection and datasets in the Workbench, so
  # the Workbench must be present. Homebrew refuses to uninstall a formula another
  # depends on, and prints `--ignore-dependencies` as the override — which is why the
  # Workbench panel gained R4e in the rebuild plan: it detects this formula and
  # refuses the removal with the order in the message, rather than letting the user
  # discover Homebrew's refusal (or an orphaned sample) for themselves.
  depends_on "statisticians-workbench"

  def install
    bin.install "bin/sample-bikestore-concierge"
    libexec.install "libexec/workbench-sample-provision",
                    "libexec/workbench-load-bikestore"
    # The nine CSVs, as Linux stages them under usr/lib/workbench/sample-bikestore.
    # They travel with the formula because the app needs them at provisioning time and
    # a user should not have to find them.
    libexec.install "libexec/sample-data"
  end

  def caveats
    <<~EOS
      The sample database is not created by the install. Provision it once the
      Workbench itself is provisioned and running:

        #{opt_libexec}/workbench-sample-provision

      It asks nothing: you supply the ordinary PostgreSQL cluster's host, port and
      administrator in the environment (SAMPLE_DB_HOST, SAMPLE_DB_PORT,
      SAMPLE_DB_ADMIN_USER, SAMPLE_DB_ADMIN_PASSWORD), or you run the app and answer
      its five questions. The sample is created in an ordinary cluster of its own —
      never in the Workbench's private one.

      Before uninstalling, unregister the sample so the Workbench does not keep an
      account pointing at a database nobody owns:

        #{opt_libexec}/workbench-sample-provision --purge

      The purge unregisters the sample and leaves its data in place.
    EOS
  end

  test do
    assert_path_exists bin/"sample-bikestore-concierge"
    assert_path_exists libexec/"workbench-sample-provision"
    assert_path_exists libexec/"workbench-load-bikestore"
    assert_path_exists libexec/"sample-data/bike-store/orders.csv"
    # Nine CSVs, because the loader expects nine and a short set loads a partial
    # sample silently. Asserted as a count rather than by name so a renamed file is
    # caught here rather than at a user's provisioning.
    assert_equal 9, Dir[libexec/"sample-data/bike-store/*.csv"].length
  end
end
