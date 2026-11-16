import type { Locale } from "../locales";
import { en, type Dictionary } from "./en";
import { es } from "./es";
import { fr } from "./fr";
import { it } from "./it";
import { ja } from "./ja";
import { ptBr } from "./pt-br";
import { ru } from "./ru";
import { zhHans } from "./zh-hans";

/** Every language's page text. Imported by server code only, so a page ships its own. */
export const DICTIONARIES: Record<Locale, Dictionary> = {
  en,
  "zh-hans": zhHans,
  fr,
  it,
  ja,
  "pt-br": ptBr,
  ru,
  es,
};
