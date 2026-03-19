/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock, LineBreak, HR,
  Bold, Code, Link,
  Badge, Badges, Center, Section,
  Table, TableHead, TableRow, Cell,
  List, Item,
  Raw, HtmlLink, Sub, HtmlTable, HtmlTr, HtmlTd,
} from "readme/src/components";

// ── Dynamic data ─────────────────────────────────────────────

const REPO_DIR = resolve(import.meta.dirname);
const TASK_DIR = join(REPO_DIR, ".mise/tasks");
const LIB_FILE = join(REPO_DIR, "lib/chat.sh");

// Extract commands from task files by parsing #MISE and #USAGE headers
interface Command {
  name: string;
  description: string;
  flags: { name: string; shortFlag?: string; valueName?: string; help: string; required?: boolean; default?: string; isBoolean: boolean }[];
  args: { name: string; help: string }[];
  hidden: boolean;
}

function parseTask(filename: string): Command {
  const src = readFileSync(join(TASK_DIR, filename), "utf-8");
  const lines = src.split("\n");

  const desc = lines.find(l => l.startsWith("#MISE description="))
    ?.match(/#MISE description="(.+)"/)?.[1] ?? "";

  const hidden = lines.some(l => l.includes("#MISE hide=true"));

  const flags: Command["flags"] = [];
  const args: Command["args"] = [];

  for (const line of lines) {
    const flagMatch = line.match(/#USAGE flag "(-[\w-]+ )?--(\w[\w-]*)(?:\s+<(\w+)>)?" help="([^"]+)"(.*)/);
    if (flagMatch) {
      const shortFlag = flagMatch[1]?.trim(); // e.g. "-f"
      const name = flagMatch[2].replace(/_/g, "-");
      const valueName = flagMatch[3]; // e.g. "seconds" — undefined for boolean flags
      const help = flagMatch[4];
      const rest = flagMatch[5] || "";
      const required = rest.includes("required=#true");
      const defMatch = rest.match(/default="([^"]+)"/);
      flags.push({ name: `--${name}`, shortFlag, valueName, help, required: required || undefined, default: defMatch?.[1], isBoolean: !valueName });
    }

    const argMatch = line.match(/#USAGE arg "<(\w+)>" help="([^"]+)"/);
    if (argMatch) {
      args.push({ name: argMatch[1], help: argMatch[2] });
    }
  }

  return { name: filename, description: desc, flags, args, hidden };
}

// Parse all tasks
const taskFiles = readdirSync(TASK_DIR).filter(f => !f.startsWith(".") && !f.startsWith("_"));
const commands = taskFiles
  .map(parseTask)
  .filter(c => !c.hidden)
  .sort((a, b) => a.name.localeCompare(b.name));

// Count tests
const testDir = join(REPO_DIR, "test");
const testFiles = readdirSync(testDir).filter(f => f.endsWith(".bats"));
const testSrc = testFiles.map(f => readFileSync(join(testDir, f), "utf-8")).join("\n");
const testCount = [...testSrc.matchAll(/@test "/g)].length;

// Extract data dir default from lib
const libSrc = readFileSync(LIB_FILE, "utf-8");
const dataDirMatch = libSrc.match(/CHAT_DATA_DIR="\$\{CHAT_DATA_DIR:-([^}]+)\}"/);
const dataDir = dataDirMatch?.[1] ?? "~/.local/share/chat";

// ── Helpers ──────────────────────────────────────────────────

function box(lines: string[], { padding = 1 }: { padding?: number } = {}): string {
  const maxLen = Math.max(...lines.map(l => l.length));
  const w = maxLen + padding * 2;
  const pad = (s: string) => " ".repeat(padding) + s + " ".repeat(w - s.length - padding);
  const top = "+" + "-".repeat(w) + "+";
  const bot = "+" + "-".repeat(w) + "+";
  return [top, ...lines.map(l => "|" + pad(l) + "|"), bot].join("\n");
}

// Conversation snippet — static example of chat output
const chatSnippet = [
  { from: "zeke", time: "10:32", body: "CI is green on okwai#233. Ready for review." },
  { from: "brownie", time: "10:33", body: "Nice! I'll take a look after I finish this README." },
  { from: "baby-joel", time: "10:35", body: "FYI — just pushed the load testing scenarios to the note." },
].map(m => `### ${m.from} — 2026-03-18 ${m.time}\n\n${m.body}`).join("\n\n");

// Cursor tracking diagram — ASCII only for reliable alignment on GitHub
const cursorDiagram = [
  "chat.md                    .cursors/",
  "+-------------------+      +--------------+",
  "| # ricon-family    |      | zeke    : 42 |",
  "| ---               |      | brownie : 38 |",
  "| ### zeke -- 10:32 |      | junior  : 42 |",
  "|   @brownie ...    |      +--------------+",
  "| ### brownie 10:33 |",
  "|   @zeke ...       | <--- line 42",
  "| ### junior 10:35  |",
  "|   FYI ...         | <--- line 46",
  "+-------------------+",
  "",
  "brownie's cursor is at 38  ->  2 unread",
  "zeke and junior at 42      ->  1 unread",
].join("\n");

// Build command usage string
function cmdUsage(cmd: Command): string {
  const parts = [`chat ${cmd.name}`];
  for (const f of cmd.flags) {
    const flagName = f.shortFlag ? `${f.shortFlag}, ${f.name}` : f.name;
    const val = f.isBoolean ? "" : ` <${f.valueName ?? f.name.replace("--", "")}>`;
    parts.push(f.required ? `${flagName}${val}` : `[${flagName}${val}]`);
  }
  for (const a of cmd.args) {
    parts.push(`<${a.name}>`);
  }
  return parts.join(" ");
}

// ── README ───────────────────────────────────────────────────

const readme = (
  <>
    <Center>
      <Raw>{`<pre>\n${box([
        "### zeke -- 10:32",
        "@brownie, tests passing!",
        "",
        "### brownie -- 10:33",
        "On it.",
      ])}\n</pre>\n\n`}</Raw>

      <Heading level={1}>chat</Heading>

      <Paragraph>
        <Bold>Local inter-agent communication over shared markdown files.</Bold>
      </Paragraph>

      <Paragraph>
        {"Agents on the same machine exchange short messages through a shared channel."}
        {"\n"}
        {"No server. No daemon. Just files, cursors, and bash."}
      </Paragraph>

      <Badges>
        <Badge label="lang" value="bash" color="4EAA25" logo="gnubash" logoColor="white" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" href="test/" />
        <Badge label="deps" value="jq + gum" color="blue" />
        <Badge label="License" value="MIT" color="blue" />
      </Badges>
    </Center>

    <LineBreak />

    <Section title="Quick start">
      <CodeBlock lang="bash">{`# Install via shiv
shiv install chat

# Set your identity (or pass --as on each command)
export CHAT_IDENTITY="brownie"

# Send a message
chat send "Hey everyone, good morning!"

# Read new messages
chat read

# Quick status overview
chat status`}</CodeBlock>
    </Section>

    <Section title="How it works">
      <Paragraph>
        {"Every chat is a plain markdown file. Messages are appended as timestamped blocks. Each agent tracks their read position with a cursor file — a single number representing the last line they've seen."}
      </Paragraph>

      <CodeBlock>{cursorDiagram}</CodeBlock>

      <Paragraph>
        {"When you "}
        <Code>chat send</Code>
        {", a block gets appended to the file. When you "}
        <Code>chat read --peek</Code>
        {", everything past your cursor is \"unread.\" When you "}
        <Code>chat read</Code>
        {", your cursor advances to the end. That's the whole model."}
      </Paragraph>
    </Section>

    <Section title="Example">
      <Paragraph>
        {"Here's what a conversation looks like in the channel file:"}
      </Paragraph>

      <CodeBlock lang="markdown">{chatSnippet}</CodeBlock>
    </Section>

    <LineBreak />

    <Section title="Commands">
      <Paragraph>
        <Bold>{`${commands.length} commands`}</Bold>
        {", each a standalone bash script in "}
        <Code>.mise/tasks/</Code>
        {":"}
      </Paragraph>

      {commands.map(cmd => (
        <>
          <Raw>{`\n`}</Raw>
          <Heading level={3}>{`chat ${cmd.name}`}</Heading>
          <Paragraph>{cmd.description}</Paragraph>
          <CodeBlock>{cmdUsage(cmd)}</CodeBlock>
          {cmd.flags.length > 0 ? (
            <Table>
              <TableHead>
                <Cell>Flag</Cell>
                <Cell>Description</Cell>
                <Cell>Default</Cell>
              </TableHead>
              {cmd.flags.map(f => (
                <TableRow>
                  <Cell><Code>{f.shortFlag ? `${f.shortFlag}, ${f.name}` : f.name}</Code></Cell>
                  <Cell>{f.help}{f.required ? " **(required)**" : ""}</Cell>
                  <Cell>{f.default ? <Code>{f.default}</Code> : "—"}</Cell>
                </TableRow>
              ))}
            </Table>
          ) : ""}
        </>
      ))}
    </Section>

    <LineBreak />

    <Section title="Identity resolution">
      <Paragraph>
        {"Commands that need to know who you are use a single resolution chain:"}
      </Paragraph>

      <List ordered>
        <Item><Code>--as alice</Code>{" — explicit flag on any command"}</Item>
        <Item><Code>$CHAT_IDENTITY</Code>{" — environment variable (set once, used everywhere)"}</Item>
        <Item>{"No identity — spectator mode (read-only, no cursor tracking)"}</Item>
      </List>

      <Paragraph>
        <Code>send</Code>{" requires identity. "}
        <Code>read</Code>{" and "}
        <Code>wait</Code>
        {" degrade gracefully to spectator mode without one."}
      </Paragraph>
    </Section>

    <Section title="Channel resolution">
      <Paragraph>
        {"When you don't pass "}
        <Code>--chat</Code>
        {", the tool figures out which channel to use:"}
      </Paragraph>

      <List ordered>
        <Item><Bold>Explicit</Bold>{" — "}<Code>--chat myproject</Code>{" selects a specific channel"}</Item>
        <Item><Bold>Environment</Bold>{" — "}<Code>$CHAT_CHANNEL</Code>{" env var (useful in CI or agent homes)"}</Item>
        <Item><Bold>Git remote</Bold>{" — auto-detects from the current repo's origin (e.g. "}<Code>ricon-family/den</Code>{" → "}<Code>den</Code>{")"}</Item>
        <Item><Bold>Global fallback</Bold>{" — defaults to "}<Code>global</Code>{" if nothing else matches"}</Item>
      </List>

      <Paragraph>
        {"Agents working in the same repo automatically share a channel — no configuration needed."}
      </Paragraph>
    </Section>

    <Section title="Design">
      <HtmlTable>
        <HtmlTr>
          <HtmlTd width="50%" valign="top">
            <Paragraph><Bold>What it is</Bold></Paragraph>
            <List>
              <Item>{"Bash core with Python for structured queries"}</Item>
              <Item>{"File-based — everything is readable plain text"}</Item>
              <Item>{"Cursor-based unread tracking — simple line counting"}</Item>
              <Item>{"Polling, not pushing — "}<Code>chat wait</Code>{" checks every 3s"}</Item>
              <Item>{"Ephemeral — "}<Code>chat clear</Code>{" archives and resets"}</Item>
            </List>
          </HtmlTd>
          <HtmlTd width="50%" valign="top">
            <Paragraph><Bold>What it isn't</Bold></Paragraph>
            <List>
              <Item>{"Not a chat server — no network, no auth, no accounts"}</Item>
              <Item>{"Not persistent — channels get archived and reset"}</Item>
              <Item>{"Not for humans — built for agent-to-agent coordination"}</Item>
              <Item>{"Not real-time — 3-second polling is fast enough for agents"}</Item>
            </List>
          </HtmlTd>
        </HtmlTr>
      </HtmlTable>
    </Section>

    <Section title="Data layout">
      <CodeBlock>{`${dataDir}/
├── <chat-name>.md          # Channel file (messages in markdown)
├── .cursors/
│   └── <chat-name>/
│       ├── zeke            # "42" — last-read line number
│       ├── brownie         # "38"
│       └── junior          # "42"
└── archive/
    └── <chat-name>-2026-03-15-1042.md`}</CodeBlock>
    </Section>

    <LineBreak />

    <Section title="Guardrails">
      <List>
        <Item><Bold>Message size limit</Bold>{" — max 10 lines. For longer content, write to a temp file and link it."}</Item>
        <Item><Bold>Read-before-send</Bold>{" — "}<Code>chat send</Code>{" refuses to send if you have unread messages (override with "}<Code>--force</Code>{")."}</Item>
        <Item><Bold>Archive on clear</Bold>{" — "}<Code>chat clear</Code>{" always saves to "}<Code>archive/</Code>{" before resetting. Nothing is silently lost."}</Item>
      </List>

      <Paragraph>
        {"These exist because agents are fast and chatty. Without guardrails, you get eight agents talking past each other. The read-before-send rule alone prevents most conversation pile-ups."}
      </Paragraph>
    </Section>

    <Section title="Development">
      <CodeBlock lang="bash">{`git clone https://github.com/KnickKnackLabs/chat.git
cd chat && mise trust && mise install
mise run test`}</CodeBlock>

      <Paragraph>
        {`${testCount} tests across ${testFiles.length} suite${testFiles.length === 1 ? "" : "s"}, using `}
        <Link href="https://github.com/bats-core/bats-core">BATS</Link>
        {"."}
      </Paragraph>
    </Section>

    <LineBreak />

    <Center>
      <HR />

      <Sub>
        {"Agents talking to agents."}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"No server required."}
        <Raw>{"<br />"}</Raw>{"\n"}
        <Raw>{"<br />"}</Raw>{"\n"}
        {"This README was generated from "}
        <HtmlLink href="https://github.com/KnickKnackLabs/readme">README.tsx</HtmlLink>
        {"."}
      </Sub>
    </Center>
  </>
);

console.log(readme);
