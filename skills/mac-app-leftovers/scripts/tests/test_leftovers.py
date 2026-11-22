"""Classification tests using real cases seen on this machine."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import leftovers as L  # noqa: E402

INV = {
    "ids": {"com.spotify.client", "com.microsoft.teams2", "com.vng.zalo", "com.jetbrains.datagrip",
            "org.gpgtools.gpgkeychain", "com.google.chrome"},
    "names": {"spotify", "microsoftteams", "zalo", "datagrip", "gpgkeychain", "googlechrome"},
}
INV["id_words"] = {"spotify", "client", "microsoft", "teams2", "zalo", "jetbrains", "datagrip",
                   "gpgtools", "gpgkeychain", "google", "chrome"}


class BundleTests(unittest.TestCase):
    def test_helper_of_installed_app_is_kept(self):
        self.assertTrue(L.bundle_installed("com.spotify.client-launcher", INV))

    def test_renamed_bundle_of_installed_app_is_kept(self):
        self.assertTrue(L.bundle_installed("com.microsoft.teams", INV))

    def test_vendor_shared_group_container_is_kept(self):
        self.assertTrue(L.bundle_installed("com.microsoft.oneauth", INV, vendor_shared=True))
        self.assertTrue(L.bundle_installed("org.gpgtools.common", INV))

    def test_uninstalled_app_from_installed_vendor_is_flagged(self):
        self.assertFalse(L.bundle_installed("com.google.antigravity", INV))

    def test_uninstalled_apps_are_flagged(self):
        for bid in ("com.facebook.archon.developerID", "org.RedisLabs.RedisInsight-V2",
                    "com.todesktop.230313mzl4w4u92", "ch.protonvpn.mac"):
            self.assertFalse(L.bundle_installed(bid, INV), bid)

    def test_strip_bundle(self):
        self.assertEqual(L.strip_bundle("W5W395V82Y.group.com.nordvpn"), "com.nordvpn")
        self.assertEqual(L.strip_bundle("com.yuki.DevToys.savedState"), "com.yuki.DevToys")
        self.assertEqual(L.strip_bundle("com.brave.Browser.plist"), "com.brave.Browser")


class NameTests(unittest.TestCase):
    def test_vendor_data_folder_of_installed_app_is_kept(self):
        self.assertTrue(L.name_installed("ZaloData", INV))
        self.assertTrue(L.name_installed("JetBrains", INV))

    def test_dev_caches_are_not_leftovers(self):
        for n in ("ms-playwright", "Homebrew", "go-build", "typescript"):
            self.assertTrue(L.name_installed(n, INV), n)

    def test_unknown_name_is_flagged(self):
        self.assertFalse(L.name_installed("RedisInsight", INV))


class GroupTests(unittest.TestCase):
    def test_aliases_and_merge(self):
        self.assertEqual(L.group_key("com.todesktop.230313mzl4w4u92.ShipIt")[1], "Cursor")
        items = [
            {"keys": L.group_key(o)[0], "app": L.group_key(o)[1], "kb": kb, "confidence": c, "path": o,
             "kind": "x"}
            for o, kb, c in [("org.RedisLabs.RedisInsight-V2", 10, "high"),
                             ("RedisInsight", 5, "review"), (".redis-insight", 1, "review")]
        ]
        groups = L.merge_groups(items)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["kb"], 16)
        self.assertTrue(all(i["confidence"] == "high" for i in groups[0]["items"]))

    def test_clean_refuses_paths_outside_home_library(self):
        self.assertFalse(L.allowed(Path("/Applications/Foo.app")))
        self.assertFalse(L.allowed(L.HOME / "Library"))
        self.assertFalse(L.allowed(L.HOME / "Documents"))
        self.assertTrue(L.allowed(L.HOME / "Library" / "Caches" / "x"))


if __name__ == "__main__":
    unittest.main()
