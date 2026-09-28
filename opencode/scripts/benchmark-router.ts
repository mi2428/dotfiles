// Opt-in local benchmark. Gold tiers are human estimates, not proof of model quality.
const config = await Bun.file(new URL("../../home/files/config/opencode/model-router.json", import.meta.url)).json();
const cases: [string | null, string, string][] = [
  ["SIMPLE", "設定ファイルのコメントにあるスペルミスだけ直して", "Fix only the spelling mistake in a config file comment."],
  ["SIMPLE", "このエラー文の意味を一言で教えて", "Briefly explain what this error message means."],
  ["LOW", "プロフィール画面に文字数カウンタを追加して", "Add a character counter to the profile form."],
  ["LOW", "検索はEnterを押したときだけ走るように直して", "Make search run only after pressing Enter."],
  ["MEDIUM", "一覧APIと画面に新しい絞り込み条件を追加してテストも書いて", "Add a new filter to the listing API and UI, with tests."],
  ["MEDIUM", "日付がズレる原因を調べてAPIと画面の処理を修正して", "Investigate date shifts and fix handling in the API and UI."],
  ["HIGH", "本番だけ再接続でイベントが重複する。WebSocket、API、DBを調べて直して", "Debug duplicate events after reconnection in production across WebSocket, API and DB."],
  ["HIGH", "依存ライブラリの更新で複数画面が壊れた。互換性を調査し回帰テストも直して", "Investigate a library update breaking multiple views and fix compatibility and regression tests."],
  ["COMPLEX", "全テナントのデータを新スキーマへ段階的に移し、ロールバックも設計して", "Plan a phased schema migration for all tenants with rollback."],
  ["COMPLEX", "認可トークンの方式を変えて全クライアントを段階移行する計画を作って", "Plan a staged authorization token migration across all clients."],
  ["REASONING", "障害が重なっても台帳残高がマイナスにならないことを不変条件で証明して", "Prove with invariants that ledger balances cannot go negative under concurrent failures."],
  ["REASONING", "敵対者が鍵を盗んでも権限拡大しない設計を形式的に検証して", "Formally verify that stolen keys cannot escalate privileges."],
  [null, "さっきの件、やっぱ直して", "Actually, fix that earlier issue."],
  [null, "そのテスト足して", "Add that test."],
  [null, "それどうする？", "How should we handle that?"],
  [null, "このまま進めて", "Proceed with it."],
];
const tiers = Object.keys(config.tiers);
const results = [];
for (const [expected, jp, en] of cases) {
  for (const [language, state] of [["ja", jp], ["en", en]] as const) {
    const response = await fetch(config.endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(process.env.OLLAYA_API_KEY ? { Authorization: `Bearer ${process.env.OLLAYA_API_KEY}` } : {}),
      },
      body: JSON.stringify({ model: config.model, state, questions: config.questions, keep_alive: config.keep_alive }),
      signal: AbortSignal.timeout(config.timeout_ms),
    });
    if (!response.ok) throw new Error(`JevK5 HTTP ${response.status}`);
    const answers = (await response.json()).answers;
    if (!tiers.includes(answers?.tier?.choice) || typeof answers.tier.confidence !== "number" ||
        !["CLEAR", "CONTEXT_REQUIRED"].includes(answers?.clarity?.choice) || typeof answers.clarity.confidence !== "number")
      throw new Error("JevK5 returned an invalid classification");
    const result = { language, expected, state, tier: answers.tier.choice, confidence: answers.tier.confidence,
      contextual: answers.clarity.choice === "CONTEXT_REQUIRED" && answers.clarity.confidence >= config.min_context_confidence };
    results.push(result);
    if ((expected !== null && (result.tier !== expected || result.confidence < config.min_confidence || result.contextual)) ||
        (expected === null && !result.contextual)) console.log(JSON.stringify(result));
  }
}
for (const language of ["ja", "en"]) {
  const rows = results.filter((row) => row.language === language);
  const explicit = rows.filter((row) => row.expected !== null);
  const vague = rows.filter((row) => row.expected === null);
  console.log(JSON.stringify({ language, explicit: explicit.length,
    exact: explicit.filter((row) => row.tier === row.expected && row.confidence >= config.min_confidence && !row.contextual).length,
    fallback: explicit.filter((row) => row.confidence < config.min_confidence || row.contextual).length,
    severeUnderroute: explicit.filter((row) => !row.contextual && row.confidence >= config.min_confidence &&
      tiers.indexOf(row.expected!) - tiers.indexOf(row.tier) >= 2).length,
    vagueContextDetected: vague.filter((row) => row.contextual).length,
  }));
}
