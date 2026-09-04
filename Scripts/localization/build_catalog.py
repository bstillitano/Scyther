#!/usr/bin/env python3
"""Merge Scripts/localization/strings/*.json into Sources/Scyther/Resources/Localizable.xcstrings.

Fragments are the source of truth. Run after editing any fragment:
    python3 Scripts/localization/build_catalog.py
Exit status is non-zero on any validation failure; the catalog is not written in that case.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRAGMENTS = ROOT / "Scripts" / "localization" / "strings"
CATALOG = ROOT / "Sources" / "Scyther" / "Resources" / "Localizable.xcstrings"

SOURCE = "en"
LANGUAGES = ["fr", "de", "es", "it", "pt-BR", "nl", "ja", "zh-Hans", "zh-Hant", "ko", "ru", "ar"]
PLURAL_CATEGORIES = {
    "en": ["one", "other"], "fr": ["one", "other"], "de": ["one", "other"], "es": ["one", "other"],
    "it": ["one", "other"], "pt-BR": ["one", "other"], "nl": ["one", "other"],
    "ja": ["other"], "zh-Hans": ["other"], "zh-Hant": ["other"], "ko": ["other"],
    "ru": ["one", "few", "many", "other"],
    "ar": ["zero", "one", "two", "few", "many", "other"],
}
PLACEHOLDER = re.compile(r"%(\d+\$)?[@dlfsu]|%lld|%\.\d+f")


def placeholders(text):
    return sorted(m.group(0) for m in PLACEHOLDER.finditer(text))


def fail(message):
    print(f"build_catalog: {message}", file=sys.stderr)
    sys.exit(1)


def unit(value, state="needs_review"):
    return {"stringUnit": {"state": state, "value": value}}


def main():
    strings = {}
    owner = {}
    for fragment in sorted(FRAGMENTS.glob("*.json")):
        try:
            data = json.loads(fragment.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"{fragment.name}: invalid JSON: {error}")
        for key, entry in data.items():
            if key in owner:
                fail(f"duplicate key {key!r} in {fragment.name} and {owner[key]}")
            owner[key] = fragment.name
            if not isinstance(entry, dict):
                fail(f"{fragment.name}: {key!r} must be an object")
            plural = bool(entry.get("plural", False))
            localizations = {}
            if plural:
                if "en" not in entry:
                    fail(f"{fragment.name}: plural key {key!r} needs an 'en' entry")
                source_forms = entry["en"]
                base_placeholders = placeholders(source_forms.get("other", ""))
                for language in [SOURCE] + LANGUAGES:
                    forms = entry.get(language)
                    if not isinstance(forms, dict):
                        fail(f"{fragment.name}: {key!r} missing plural forms for {language}")
                    missing = [c for c in PLURAL_CATEGORIES[language] if c not in forms or not forms[c]]
                    if missing:
                        fail(f"{fragment.name}: {key!r} {language} missing plural categories {missing}")
                    variations = {}
                    for category, text in forms.items():
                        if category == "other" and placeholders(text) != base_placeholders:
                            fail(f"{fragment.name}: {key!r} {language}.{category} placeholders {placeholders(text)} != {base_placeholders}")
                        variations[category] = unit(text, "translated" if language == SOURCE else "needs_review")
                    localizations[language] = {"variations": {"plural": variations}}
            else:
                base_placeholders = placeholders(key)
                for language in LANGUAGES:
                    text = entry.get(language)
                    if not isinstance(text, str) or not text.strip():
                        fail(f"{fragment.name}: {key!r} missing translation for {language}")
                    if placeholders(text) != base_placeholders:
                        fail(f"{fragment.name}: {key!r} {language} placeholders {placeholders(text)} != {base_placeholders}")
                    localizations[language] = unit(text)
            record = {"localizations": localizations}
            if entry.get("comment"):
                record["comment"] = entry["comment"]
            strings[key] = record

    catalog = {"sourceLanguage": SOURCE, "strings": dict(sorted(strings.items())), "version": "1.0"}
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"build_catalog: wrote {len(strings)} keys × {len(LANGUAGES)} languages to {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
