import { existsSync, readFileSync, readdirSync } from "fs";
import { join } from "path";

export interface MiseCommand {
  name: string;
  description: string;
  flags: {
    name: string;
    shortFlag?: string;
    valueName?: string;
    help: string;
    required?: boolean;
    default?: string;
    isBoolean: boolean;
  }[];
  args: { name: string; help: string; optional: boolean }[];
  hidden: boolean;
}

type UsageAttrs = Record<string, string | boolean>;

function parseUsageAttrs(rest: string): UsageAttrs {
  const attrs: UsageAttrs = {};
  const attrRe = /(\w[\w-]*)=(?:"([^"]*)"|#(true|false)|([^\s]+))/g;
  for (const match of rest.matchAll(attrRe)) {
    const [, key, quoted, bool, bare] = match;
    if (bool) {
      attrs[key] = bool === "true";
    } else {
      attrs[key] = quoted ?? bare ?? "";
    }
  }
  return attrs;
}

function stringAttr(attrs: UsageAttrs, key: string): string | undefined {
  const value = attrs[key];
  return typeof value === "string" ? value : undefined;
}

function parseMiseTask(taskDir: string, filename: string, name = filename): MiseCommand {
  const src = readFileSync(join(taskDir, filename), "utf-8");
  const lines = src.split("\n");

  const desc = lines.find(l => l.startsWith("#MISE description="))
    ?.match(/#MISE description="(.+)"/)?.[1] ?? "";

  const hidden = lines.some(l => l.includes("#MISE hide=true"));

  const flags: MiseCommand["flags"] = [];
  const args: MiseCommand["args"] = [];

  for (const line of lines) {
    const flagMatch = line.match(/#USAGE flag "(-[\w-]+ )?--(\w[\w-]*)(?:\s+<(\w+)>)?"(.*)$/);
    if (flagMatch) {
      const shortFlag = flagMatch[1]?.trim();
      const name = flagMatch[2].replace(/_/g, "-");
      const valueName = flagMatch[3];
      const attrs = parseUsageAttrs(flagMatch[4] || "");
      const help = stringAttr(attrs, "help") ?? "";
      const required = attrs.required === true;
      const defaultValue = stringAttr(attrs, "default");
      flags.push({
        name: `--${name}`,
        shortFlag,
        valueName,
        help,
        required: required || undefined,
        default: defaultValue,
        isBoolean: !valueName,
      });
    }

    const argMatch = line.match(/#USAGE arg "([<\[])(\w+)([>\]])"(.*)$/);
    if (argMatch) {
      const attrs = parseUsageAttrs(argMatch[4] || "");
      args.push({
        name: argMatch[2],
        help: stringAttr(attrs, "help") ?? "",
        optional: argMatch[1] === "[",
      });
    }
  }

  return { name, description: desc, flags, args, hidden };
}

export function parseMiseTasks(taskDir: string): MiseCommand[] {
  return readdirSync(taskDir, { withFileTypes: true })
    .filter(entry => !entry.name.startsWith("."))
    .flatMap(entry => {
      if (entry.isFile() && !entry.name.startsWith("_")) {
        return [parseMiseTask(taskDir, entry.name)];
      }

      if (entry.isDirectory() && !entry.name.startsWith("_")) {
        const defaultTask = join(entry.name, "_default");
        if (existsSync(join(taskDir, defaultTask))) {
          return [parseMiseTask(taskDir, defaultTask, entry.name)];
        }
      }

      return [];
    })
    .filter(command => !command.hidden)
    .sort((a, b) => a.name.localeCompare(b.name));
}
