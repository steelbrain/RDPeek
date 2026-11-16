// Copies the app's own wording for the strings the redrawn UI shows, from
// Sources/Resources/Localizable.xcstrings, into lib/i18n/app-strings.json.
// The keys are listed in lib/i18n/app-keys.json. Run it after changing that
// list, or when the app's translations change:
//
//   node scripts/extract-app-strings.mjs          # rewrite the JSON
//   node scripts/extract-app-strings.mjs --check  # fail if it is out of date
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const catalogPath = join(site, "../Sources/Resources/Localizable.xcstrings");
const keysPath = join(site, "lib/i18n/app-keys.json");
const outPath = join(site, "lib/i18n/app-strings.json");

/** The app's localizations, by catalog code, as CFBundleLocalizations lists them. */
const LANGUAGES = ["en", "es", "fr", "it", "ja", "pt-BR", "ru", "zh-Hans"];

const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
const keys = JSON.parse(readFileSync(keysPath, "utf8"));
const problems = [];

function entryFor(localization) {
  if (localization.stringUnit) return localization.stringUnit.value;
  const plural = localization.variations?.plural;
  if (plural) {
    return Object.fromEntries(Object.entries(plural).map(([form, value]) => [form, value.stringUnit.value]));
  }
  return null;
}

const strings = {};
for (const key of [...keys].sort()) {
  const source = catalog.strings[key];
  if (!source) {
    problems.push(`not in the app's catalog: ${JSON.stringify(key)}`);
    continue;
  }
  const entries = {};
  for (const language of LANGUAGES) {
    const localization = source.localizations?.[language];
    if (!localization) {
      // English is the key itself unless the catalog gives it plural forms.
      if (language === "en") entries.en = key;
      else problems.push(`no ${language} for ${JSON.stringify(key)}`);
      continue;
    }
    const entry = entryFor(localization);
    if (entry === null) problems.push(`unreadable ${language} for ${JSON.stringify(key)}`);
    else entries[language] = entry;
  }
  strings[key] = entries;
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}

const output = `${JSON.stringify(strings, null, 2)}\n`;
if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(outPath, "utf8");
  } catch {}
  if (current !== output) {
    console.error("lib/i18n/app-strings.json is out of date: run node scripts/extract-app-strings.mjs");
    process.exit(1);
  }
  console.log("lib/i18n/app-strings.json matches the app's catalog.");
} else {
  writeFileSync(outPath, output);
  console.log(`Wrote ${Object.keys(strings).length} strings to lib/i18n/app-strings.json.`);
}
