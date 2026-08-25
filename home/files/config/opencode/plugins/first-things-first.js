const POLICY = `<first-things-first>
Before changing code:
- Understand the real flow and consider materially different approaches. Choose the clearest solution that meets the request with the least code.
- Reuse existing project code, the standard library, platform features, or installed dependencies before adding code.
- Fix the earliest shared root cause. Never hide a known defect with a fallback, silent default, catch-and-continue, compatibility shim, or legacy path.
- At security boundaries, fail closed. For invalid or inconsistent state, fail fast and visibly.
- Add degraded behavior only when it is an explicit current requirement, never as a substitute for fixing an error.
- Do not preserve compatibility for unreleased behavior. When intentionally replacing an obsolete design, remove the old path completely.
- Deliver the smallest necessary diff and remove every unnecessary changed line.
</first-things-first>`;

export const FirstThingsFirst = async () => ({
  "experimental.chat.system.transform": async (_input, output) => {
    output.system.push(POLICY);
  },
});

export default FirstThingsFirst;
