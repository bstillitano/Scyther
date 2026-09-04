#!/usr/bin/env python3
"""Unit tests for build_catalog.py's validation and merge behaviour.

Run from the repo root:
    python3 -m unittest Scripts/localization/test_build_catalog.py -v

Uses only the standard library. build_catalog is imported by file path (rather than as a
package) since Scripts/localization has no __init__.py.
"""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parent / "build_catalog.py"
SPEC = importlib.util.spec_from_file_location("build_catalog", MODULE_PATH)
build_catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_catalog)


def valid_simple_entry():
    """A complete, valid non-plural fragment entry: "Language" translated into all 12 languages."""
    return {
        "Language": {
            "comment": "Menu row and page title for the app language override",
            "fr": "Langue", "de": "Sprache", "es": "Idioma", "it": "Lingua", "pt-BR": "Idioma", "nl": "Taal",
            "ja": "言語", "zh-Hans": "语言", "zh-Hant": "語言", "ko": "언어", "ru": "Язык", "ar": "اللغة",
        }
    }


def valid_plural_entry():
    """A complete, valid plural fragment entry: "%lld selected" with every required CLDR category."""
    return {
        "%lld selected": {
            "comment": "Accessibility suffix for a filter chip with a selection count",
            "plural": True,
            "en":      {"one": "%lld selected", "other": "%lld selected"},
            "fr":      {"one": "%lld sélectionné", "other": "%lld sélectionnés"},
            "de":      {"one": "%lld ausgewählt", "other": "%lld ausgewählt"},
            "es":      {"one": "%lld seleccionado", "other": "%lld seleccionados"},
            "it":      {"one": "%lld selezionato", "other": "%lld selezionati"},
            "pt-BR":   {"one": "%lld selecionado", "other": "%lld selecionados"},
            "nl":      {"one": "%lld geselecteerd", "other": "%lld geselecteerd"},
            "ja":      {"other": "%lld件選択済み"},
            "zh-Hans": {"other": "已选择 %lld 项"},
            "zh-Hant": {"other": "已選取 %lld 項"},
            "ko":      {"other": "%lld개 선택됨"},
            "ru":      {"one": "Выбран %lld", "few": "Выбрано %lld", "many": "Выбрано %lld", "other": "Выбрано %lld"},
            "ar":      {
                "zero": "لم يتم تحديد شيء", "one": "تم تحديد عنصر واحد", "two": "تم تحديد عنصرين",
                "few": "تم تحديد %lld عناصر", "many": "تم تحديد %lld عنصرًا", "other": "تم تحديد %lld عنصر",
            },
        }
    }


class BuildCatalogTests(unittest.TestCase):
    def setUp(self):
        self._fragments_tmp = tempfile.TemporaryDirectory()
        self._catalog_tmp = tempfile.TemporaryDirectory()
        self.fragments_dir = Path(self._fragments_tmp.name)
        self.catalog_path = Path(self._catalog_tmp.name) / "Localizable.xcstrings"

    def tearDown(self):
        self._fragments_tmp.cleanup()
        self._catalog_tmp.cleanup()

    def write_fragment(self, name, data):
        (self.fragments_dir / name).write_text(json.dumps(data), encoding="utf-8")

    def run_main(self):
        return build_catalog.main(fragments_dir=self.fragments_dir, catalog_path=self.catalog_path)

    # MARK: - Happy path

    def test_happy_path_writes_complete_catalog(self):
        self.write_fragment("Core.json", {**valid_simple_entry(), **valid_plural_entry()})

        self.run_main()

        self.assertTrue(self.catalog_path.exists())
        catalog = json.loads(self.catalog_path.read_text(encoding="utf-8"))
        self.assertEqual(catalog["sourceLanguage"], "en")
        self.assertEqual(set(catalog["strings"].keys()), {"Language", "%lld selected"})

        simple_localizations = catalog["strings"]["Language"]["localizations"]
        self.assertEqual(set(simple_localizations.keys()), set(build_catalog.LANGUAGES))
        self.assertEqual(simple_localizations["fr"]["stringUnit"]["value"], "Langue")

        plural_localizations = catalog["strings"]["%lld selected"]["localizations"]
        self.assertEqual(set(plural_localizations.keys()), {build_catalog.SOURCE} | set(build_catalog.LANGUAGES))
        for language, categories in build_catalog.PLURAL_CATEGORIES.items():
            variations = plural_localizations[language]["variations"]["plural"]
            self.assertEqual(set(variations.keys()), set(categories))

    # MARK: - Rejections

    def test_duplicate_key_across_two_fragments_fails(self):
        self.write_fragment("A.json", valid_simple_entry())
        self.write_fragment("B.json", valid_simple_entry())

        with self.assertRaises(SystemExit):
            self.run_main()

        self.assertFalse(self.catalog_path.exists())

    def test_missing_language_fails(self):
        entry = valid_simple_entry()
        del entry["Language"]["de"]
        self.write_fragment("Core.json", entry)

        with self.assertRaises(SystemExit):
            self.run_main()

        self.assertFalse(self.catalog_path.exists())

    def test_empty_value_fails(self):
        entry = valid_simple_entry()
        entry["Language"]["de"] = ""
        self.write_fragment("Core.json", entry)

        with self.assertRaises(SystemExit):
            self.run_main()

        self.assertFalse(self.catalog_path.exists())

    def test_plural_missing_category_fails(self):
        entry = valid_plural_entry()
        del entry["%lld selected"]["ru"]["few"]
        self.write_fragment("Core.json", entry)

        with self.assertRaises(SystemExit):
            self.run_main()

        self.assertFalse(self.catalog_path.exists())

    def test_placeholder_mismatch_fails(self):
        entry = valid_simple_entry()
        entry["%lld selected"] = {
            "fr": "%@ selected", "de": "%lld selected", "es": "%lld selected", "it": "%lld selected",
            "pt-BR": "%lld selected", "nl": "%lld selected", "ja": "%lld selected", "zh-Hans": "%lld selected",
            "zh-Hant": "%lld selected", "ko": "%lld selected", "ru": "%lld selected", "ar": "%lld selected",
        }
        self.write_fragment("Core.json", entry)

        with self.assertRaises(SystemExit):
            self.run_main()

        self.assertFalse(self.catalog_path.exists())


if __name__ == "__main__":
    unittest.main()
