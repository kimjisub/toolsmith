#!/usr/bin/env python3
"""Keeps the string catalogs in step with the code. See CONTRIBUTING.md, "Text and languages".

    scripts/localization.py lint            Korean string literals left in Swift code (no build needed)
    scripts/localization.py check           lint, plus every catalog entry translated into every language
    scripts/localization.py check --built [Dev|Release]
                                            check, plus the last build's strings all in the catalogs
    scripts/localization.py sync            adds the last builds' new strings to the catalogs (to translate)
                                            and drops the ones no configuration uses any more

English is the development language: code holds English, the catalogs hold the other languages.
The compiler lists every localizable literal it sees (String(localized:), Text("..."), Kit's
localized(...), LocalizedStringResource) in .stringsdata files when it builds, which `--built` and
`sync` read from build/DerivedData (scripts/build.sh). Xcode's editor does the same sync on build;
from the command line this script does it.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGUAGES = ["ko"]
# Catalog -> the target whose compiled .stringsdata feed it.
CATALOGS = {
    ROOT / "App/Kit/Localizable.xcstrings": "ToolsmithKit",
    ROOT / "App/Main/Localizable.xcstrings": "Toolsmith",
}
# Translated by hand; their keys are Info.plist keys, not code.
STATIC_CATALOGS = [ROOT / "App/Main/InfoPlist.xcstrings"]
DERIVED = ROOT / "build/DerivedData/Build/Intermediates.noindex/Toolsmith.build"

HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')
# Search words may be Korean whatever the app's language: on a line that names `keywords` (an argument,
# a property, a constant named *Keywords), literals after that word are search words.
KEYWORDS = re.compile(r"(?i)keywords")
# A line that says why its text is not translated (a language's own name, sample content).
NOT_LOCALIZED = "// not localized:"
# Files whose Korean is data, not text shown to people: the Hangul search tables, development-only aids, tests.
LINT_SKIP = re.compile(r"^App/(Tests/|Kit/Search/HangulText\.swift$|Main/.*DevelopmentAids\.swift$)")


def lint() -> list[str]:
    problems = []
    for path in sorted((ROOT / "App").rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        if LINT_SKIP.search(relative):
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if NOT_LOCALIZED in line:
                continue
            code = line.split("//", 1)[0] if not line.lstrip().startswith("//") else ""
            code = KEYWORDS.split(code, 1)[0]
            if any(HANGUL.search(literal) for literal in STRING_LITERAL.findall(code)):
                problems.append(f"  {relative}:{number}: {line.strip()}")
    return problems


def load(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: pathlib.Path, catalog: dict) -> None:
    """Writes the catalog the way Xcode does, so opening it in Xcode changes nothing."""
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n", encoding="utf-8")


def untranslated(catalog: dict) -> list[str]:
    missing = []
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            missing.append(f"{key!r}: no longer in the code (stale); remove it")
            continue
        for language in LANGUAGES:
            localization = entry.get("localizations", {}).get(language)
            if localization is None:
                missing.append(f"{key!r}: no {language} translation")
            elif "stringUnit" in localization and localization["stringUnit"].get("state") != "translated":
                missing.append(f"{key!r}: {language} translation not marked translated")
    return missing


CONFIGURATION = "Dev"


def stringsdata(target: str, configuration: str) -> list[pathlib.Path]:
    """The compiler's lists for `target`; "*" reads every configuration built (Dev and Release
    differ: Release leaves out the development aids, and a few strings exist only there)."""
    files = sorted(DERIVED.glob(f"{configuration}/{target}.build/**/*.stringsdata"))
    if not files:
        sys.exit(f"no .stringsdata for {target} under {DERIVED.relative_to(ROOT)}; build first (scripts/build.sh)")
    return files


def synced(catalog: pathlib.Path, target: str, folder: pathlib.Path, configuration: str = "*") -> dict:
    """The catalog as Xcode would leave it after a build: new strings added, vanished ones marked stale."""
    copy = folder / catalog.name
    shutil.copy(catalog, copy)
    files = stringsdata(target, configuration)
    arguments = ["xcrun", "xcstringstool", "sync", str(copy)]
    for file in files:
        arguments += ["--stringsdata", str(file)]
    subprocess.run(arguments, check=True, capture_output=True)
    return load(copy)


def built_differences() -> list[str]:
    problems = []
    with tempfile.TemporaryDirectory() as folder:
        for catalog, target in CATALOGS.items():
            before = load(catalog)["strings"]
            after = synced(catalog, target, pathlib.Path(folder), CONFIGURATION)["strings"]
            name = catalog.relative_to(ROOT)
            for key in sorted(after.keys() - before.keys()):
                problems.append(f"  {name}: {key!r} is in the code but not in the catalog")
            # A string is unused only if neither configuration has it; with one built, that is unknown.
            both_built = all(list(DERIVED.glob(f"{c}/{target}.build")) for c in ("Dev", "Release"))
            everywhere = synced(catalog, target, pathlib.Path(folder))["strings"] if both_built else {}
            for key in sorted(before.keys() & everywhere.keys()):
                if everywhere[key].get("extractionState") == "stale" and before[key].get("extractionState") != "stale":
                    problems.append(f"  {name}: {key!r} is no longer in the code")
    return problems


def sync() -> None:
    with tempfile.TemporaryDirectory() as folder:
        for catalog, target in CATALOGS.items():
            updated = synced(catalog, target, pathlib.Path(folder))
            updated["strings"] = {k: v for k, v in updated["strings"].items() if v.get("extractionState") != "stale"}
            save(catalog, updated)
            print(f"synced {catalog.relative_to(ROOT)}")


def main(arguments: list[str]) -> int:
    global CONFIGURATION
    command = arguments[0] if arguments else "check"
    CONFIGURATION = next((a for a in arguments[1:] if not a.startswith("-")), CONFIGURATION)
    if command == "sync":
        sync()
        return 0
    if command not in ("lint", "check"):
        print(__doc__)
        return 2

    failed = False
    problems = lint()
    if problems:
        failed = True
        print("localization: Korean text written in code (write English and translate it in a string catalog):")
        print("\n".join(problems))
    if command == "check":
        for catalog in [*CATALOGS, *STATIC_CATALOGS]:
            missing = untranslated(load(catalog))
            if missing:
                failed = True
                print(f"localization: {catalog.relative_to(ROOT)} needs translating:")
                print("\n".join("  " + line for line in missing))
        if "--built" in arguments:
            differences = built_differences()
            if differences:
                failed = True
                print("localization: the catalogs differ from the code (run scripts/localization.py sync, then translate):")
                print("\n".join(differences))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
