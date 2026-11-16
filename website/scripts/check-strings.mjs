// Checks the page's strings in every language, and fails on what is wrong:
//
//   npm run check-strings
//
// Missing: a key English has that a translation lacks; a language with no
//   dictionary, or still mapped to English in the index; text in a
//   component that skips the dictionaries (English shown in every language).
// Extra: a key a translation has that English doesn't; an English key the
//   code never reads; an app string (lib/i18n/app-keys.json) the page no
//   longer shows; a dictionary for a language the site doesn't have.
// Wrong: a translation whose <tags> or {placeholders} differ from English,
//   an empty string, or lib/i18n/app-strings.json out of step with the app's
//   catalog.
// It warns, without failing, on a translated sentence identical to English.
//
// It reads the code with the TypeScript compiler, so "never reads" means no
// property access, destructuring or array use reaches the key.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const dictionariesDir = join(site, "lib/i18n/dictionaries");
const errors = [];
const warnings = [];
const rel = (file) => relative(site, file);

/**
 * Text that is English in every language on purpose, with why: a whole
 * file, or "file#Function" for one component in it.
 */
const ENGLISH_BY_DESIGN = {
  "components/demo/RemoteDesktop.tsx": "the remote Windows desktop, not RDPeek",
  "components/demo/SessionWindow.tsx#StatsWindow": "Stats for Nerds stays in English, as in the app",
};

/** The name of the function a node is in, for "file#Function" exemptions. */
function enclosingFunction(node) {
  for (let current = node.parent; current; current = current.parent) {
    if (ts.isFunctionDeclaration(current) && current.name) return current.name.text;
  }
  return null;
}
/** Words that are the same in every language. */
const SAME_IN_EVERY_LANGUAGE = new Set(["RDPeek", "Anees Iqbal", "Windows Laptop"]);

// --- The program -------------------------------------------------------------

const configPath = ts.findConfigFile(site, ts.sys.fileExists, "tsconfig.json");
const config = ts.parseJsonConfigFileContent(ts.readConfigFile(configPath, ts.sys.readFile).config, ts.sys, site);
const program = ts.createProgram(config.fileNames, config.options);
const checker = program.getTypeChecker();
const sourceFile = (file) => program.getSourceFile(join(site, file));

// --- Literal values out of the dictionaries ----------------------------------

/** A dictionary's value: strings, arrays and objects, each with its AST node. */
function literal(node, file) {
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return { kind: "string", value: node.text, node };
  if (ts.isArrayLiteralExpression(node)) return { kind: "array", items: node.elements.map((item) => literal(item, file)), node };
  if (ts.isObjectLiteralExpression(node)) {
    const fields = new Map();
    for (const property of node.properties) {
      if (!ts.isPropertyAssignment(property)) {
        errors.push(`${file}: only plain "key: value" entries are allowed, found ${property.getText().slice(0, 40)}`);
        continue;
      }
      const name = ts.isIdentifier(property.name) || ts.isStringLiteral(property.name) ? property.name.text : property.name.getText();
      fields.set(name, { ...literal(property.initializer, file), declaration: property });
    }
    return { kind: "object", fields, node };
  }
  if (ts.isAsExpression(node) || ts.isSatisfiesExpression(node) || ts.isParenthesizedExpression(node)) return literal(node.expression, file);
  errors.push(`${file}: ${node.getText().slice(0, 50)} is not a plain string, array or object`);
  return { kind: "unknown", node };
}

function exportedObject(file) {
  const source = sourceFile(file);
  if (!source) return null;
  for (const statement of source.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (declaration.initializer && ts.isObjectLiteralExpression(declaration.initializer)) {
        return { name: declaration.name.getText(), value: literal(declaration.initializer, file) };
      }
    }
  }
  return null;
}

/** Every string by path ("demo.grid.caption", "pcs.paragraphs.0"), and every container. */
function flatten(value, path = "", out = new Map()) {
  if (path) out.set(path, value);
  if (value.kind === "object") for (const [key, child] of value.fields) flatten(child, path ? `${path}.${key}` : key, out);
  if (value.kind === "array") value.items.forEach((child, index) => flatten(child, `${path}.${index}`, out));
  return out;
}

// --- Languages ---------------------------------------------------------------

const localesSource = sourceFile("lib/i18n/locales.ts");
let locales = [];
localesSource.forEachChild(function visit(node) {
  if (ts.isVariableDeclaration(node) && node.name.getText() === "LOCALES" && node.initializer) {
    const array = ts.isAsExpression(node.initializer) ? node.initializer.expression : node.initializer;
    locales = array.elements.map((element) => element.text);
  }
  node.forEachChild(visit);
});

const english = exportedObject("lib/i18n/dictionaries/en.ts");
const englishPaths = flatten(english.value);
const markup = (text) =>
  [...text.matchAll(/<\/?\w+>|\{\w+\}/g)]
    .map((match) => match[0])
    .sort()
    .join(" ");

for (const locale of locales.filter((locale) => locale !== "en")) {
  const file = `lib/i18n/dictionaries/${locale}.ts`;
  if (!existsSync(join(site, file))) {
    errors.push(`missing: ${locale} has no dictionary (${file})`);
    continue;
  }
  const translation = exportedObject(file);
  if (!translation) {
    errors.push(`${file}: no exported dictionary object`);
    continue;
  }
  const paths = flatten(translation.value);
  // A section reported missing or extra stands for everything in it.
  const reported = [];
  const within = (path) => reported.some((section) => path.startsWith(`${section}.`));
  for (const [path, value] of englishPaths) {
    const other = paths.get(path);
    if (!other) {
      if (!within(path)) errors.push(`missing: ${locale} has no ${path}`);
      reported.push(path);
    } else if (other.kind !== value.kind) {
      errors.push(`${locale}: ${path} is a ${other.kind}, English has a ${value.kind}`);
    } else if (value.kind === "string") {
      if (!other.value.trim()) errors.push(`${locale}: ${path} is empty`);
      if (markup(other.value) !== markup(value.value)) {
        errors.push(`${locale}: ${path} has markup "${markup(other.value)}", English has "${markup(value.value)}"`);
      }
      if (other.value === value.value && value.value.split(/\s+/).length >= 3) {
        warnings.push(`${locale}: ${path} is the same as English`);
      }
    }
  }
  for (const path of paths.keys()) {
    if (englishPaths.has(path) || within(path)) continue;
    errors.push(`extra: ${locale} has ${path}, which English doesn't`);
    reported.push(path);
  }
}

for (const name of readdirSync(dictionariesDir)) {
  const locale = name.replace(/\.ts$/, "");
  if (name.endsWith(".ts") && name !== "index.ts" && !locales.includes(locale)) {
    errors.push(`extra: lib/i18n/dictionaries/${name} is for a language the site doesn't have`);
  }
}

// The index must give each language its own dictionary.
const indexSource = sourceFile("lib/i18n/dictionaries/index.ts");
const imports = new Map();
for (const statement of indexSource.statements) {
  if (ts.isImportDeclaration(statement) && statement.importClause?.namedBindings && ts.isNamedImports(statement.importClause.namedBindings)) {
    for (const element of statement.importClause.namedBindings.elements) {
      imports.set(element.name.text, statement.moduleSpecifier.text.replace(/^\.\//, ""));
    }
  }
}
indexSource.forEachChild(function visit(node) {
  if (ts.isVariableDeclaration(node) && node.name.getText() === "DICTIONARIES" && node.initializer) {
    const mapped = new Set();
    for (const property of node.initializer.properties) {
      const locale = ts.isStringLiteral(property.name) ? property.name.text : property.name.getText();
      const identifier = ts.isShorthandPropertyAssignment(property) ? property.name.text : property.initializer.getText();
      mapped.add(locale);
      if (imports.get(identifier) !== locale) {
        errors.push(`missing: DICTIONARIES gives ${locale} the dictionary from "./${imports.get(identifier) ?? identifier}"`);
      }
    }
    for (const locale of locales) if (!mapped.has(locale)) errors.push(`missing: DICTIONARIES has no ${locale}`);
  }
  node.forEachChild(visit);
});

// --- Which English keys the code reads ---------------------------------------

const englishFile = join(site, "lib/i18n/dictionaries/en.ts");
const pathOfDeclaration = new Map();
for (const [path, value] of englishPaths) if (value.declaration) pathOfDeclaration.set(value.declaration, path);
const used = new Set();
const pattern = (path) => path.replace(/\.\d+(?=\.|$)/g, ".*");

function markUsed(symbol) {
  for (const declaration of symbol?.declarations ?? []) {
    if (declaration.getSourceFile().fileName !== englishFile) continue;
    const path = pathOfDeclaration.get(declaration);
    if (!path) continue;
    used.add(pattern(path));
    // An array is read as a whole: its strings with it.
    if (englishPaths.get(path).kind === "array") used.add(`${pattern(path)}.*`);
  }
}

const codeFiles = program
  .getSourceFiles()
  .filter((file) => !file.isDeclarationFile && !file.fileName.includes("/node_modules/"))
  .filter((file) => !file.fileName.startsWith(dictionariesDir));

const stringLiterals = new Set();
const uiCalls = [];
for (const file of codeFiles) {
  file.forEachChild(function visit(node) {
    if (ts.isPropertyAccessExpression(node)) {
      markUsed(checker.getSymbolAtLocation(node.name));
    } else if (ts.isElementAccessExpression(node) && ts.isStringLiteral(node.argumentExpression)) {
      markUsed(checker.getTypeAtLocation(node.expression).getProperty(node.argumentExpression.text));
    } else if (ts.isBindingElement(node) && ts.isObjectBindingPattern(node.parent)) {
      const name = (node.propertyName ?? node.name).getText();
      markUsed(checker.getTypeAtLocation(node.parent).getProperty(name));
    }
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) stringLiterals.add(node.text);
    if (ts.isCallExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === "ui") {
      let [key] = node.arguments;
      while (key && (ts.isAsExpression(key) || ts.isParenthesizedExpression(key) || ts.isSatisfiesExpression(key))) key = key.expression;
      if (key && ts.isStringLiteral(key)) uiCalls.push({ key: key.text, where: `${rel(file.fileName)}:${file.getLineAndCharacterOfPosition(node.getStart()).line + 1}` });
    }
    node.forEachChild(visit);
  });
}

for (const [path, value] of englishPaths) {
  if (value.kind !== "string") continue;
  if (!used.has(pattern(path))) errors.push(`extra: no code reads ${path}; remove it from every dictionary, or use it`);
}

// --- App strings -------------------------------------------------------------

const appKeys = JSON.parse(readFileSync(join(site, "lib/i18n/app-keys.json"), "utf8"));
const appStrings = JSON.parse(readFileSync(join(site, "lib/i18n/app-strings.json"), "utf8"));
for (const key of appKeys) {
  if (!stringLiterals.has(key)) errors.push(`extra: the page never shows the app string ${JSON.stringify(key)} (lib/i18n/app-keys.json)`);
  if (!(key in appStrings)) errors.push(`missing: ${JSON.stringify(key)} is listed but not in app-strings.json; run node scripts/extract-app-strings.mjs`);
}
for (const key of Object.keys(appStrings)) {
  if (!appKeys.includes(key)) errors.push(`extra: app-strings.json has ${JSON.stringify(key)}, which app-keys.json doesn't list`);
}
for (const { key, where } of uiCalls) {
  if (!appKeys.includes(key)) errors.push(`missing: ${where} shows ${JSON.stringify(key)}, which isn't in lib/i18n/app-keys.json`);
}
// The app's catalog lives outside the site; check it when it's there.
if (existsSync(join(site, "../Sources/Resources/Localizable.xcstrings"))) {
  const result = spawnSync(process.execPath, [join(site, "scripts/extract-app-strings.mjs"), "--check"], { encoding: "utf8" });
  if (result.status !== 0) errors.push(`stale: ${(result.stderr || result.stdout).trim()}`);
}

// --- Text that skips the dictionaries ----------------------------------------

const LABEL_ATTRIBUTES = new Set(["aria-label", "title", "placeholder", "alt", "label", "closeLabel", "increaseLabel", "decreaseLabel", "help", "footer", "copyLabel", "copiedLabel"]);
const isWords = (text) => /\p{L}{2,}/u.test(text) && !SAME_IN_EVERY_LANGUAGE.has(text.trim());
for (const file of codeFiles) {
  const path = rel(file.fileName);
  if (!path.endsWith(".tsx") || path in ENGLISH_BY_DESIGN || path === "app/opengraph-image.tsx") continue;
  file.forEachChild(function visit(node) {
    let text = null;
    if (ts.isJsxText(node) && isWords(node.text)) text = node.text.trim();
    if (ts.isJsxAttribute(node) && LABEL_ATTRIBUTES.has(node.name.getText()) && node.initializer && ts.isStringLiteral(node.initializer) && isWords(node.initializer.text)) {
      text = node.initializer.text;
    }
    if (text && !(`${path}#${enclosingFunction(node)}` in ENGLISH_BY_DESIGN)) {
      const line = file.getLineAndCharacterOfPosition(node.getStart()).line + 1;
      errors.push(`missing: ${path}:${line} shows "${text.replace(/\s+/g, " ").slice(0, 60)}" in every language; put it in the dictionaries`);
    }
    node.forEachChild(visit);
  });
}

// --- Report ------------------------------------------------------------------

for (const warning of warnings) console.warn(`warning: ${warning}`);
for (const error of errors) console.error(error);
if (errors.length) {
  console.error(`\n${errors.length} problem${errors.length === 1 ? "" : "s"} with the page's strings.`);
  process.exit(1);
}
const strings = [...englishPaths.values()].filter((value) => value.kind === "string").length;
console.log(`Strings check out: ${locales.length} languages, ${strings} page strings each, ${appKeys.length} app strings.`);
