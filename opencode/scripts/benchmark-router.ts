// Opt-in local benchmark. Gold classes are human estimates, not proof of model quality.
const config = await Bun.file(new URL("../../home/files/config/opencode/model-router.json", import.meta.url)).json();
const cases: [string | null, string, string][] = [
  ["SIMPLE", "設定ファイルのコメントにあるスペルミスだけ直して", "Fix only the spelling mistake in a config file comment."],
  ["SIMPLE", "このエラー文の意味を一言で教えて", "Briefly explain what this error message means."],
  ["SIMPLE", "進行中のダウンロードを終わるまで見張って", "Watch an ongoing download until it finishes."],
  ["SIMPLE", "確認済みの変更をコミットして、hook も実行して", "Commit the already reviewed changes and run hooks."],
  ["DEFAULT", "プロフィール画面に文字数カウンタを追加して", "Add a character counter to the profile form."],
  ["DEFAULT", "検索はEnterを押したときだけ走るように直して", "Make search run only after pressing Enter."],
  ["DEFAULT", "一覧APIと画面に新しい絞り込み条件を追加してテストも書いて", "Add a new filter to the listing API and UI, with tests."],
  ["DEFAULT", "日付がズレる原因を調べてAPIと画面の処理を修正して", "Investigate date shifts and fix handling in the API and UI."],
  ["DEFAULT", "本番だけ再接続でイベントが重複する。WebSocket、API、DBを調べて直して", "Debug duplicate events after reconnection in production across WebSocket, API and DB."],
  ["DEFAULT", "全テナントのデータを新スキーマへ段階的に移し、ロールバックも設計して", "Plan a phased schema migration for all tenants with rollback."],
  ["DEFAULT", "認可トークンの方式を変えて全クライアントを段階移行する計画を作って", "Plan a staged authorization token migration across all clients."],
  ["DEFAULT", "障害が重なっても台帳残高がマイナスにならないことを不変条件で証明して", "Prove with invariants that ledger balances cannot go negative under concurrent failures."],
  ["DEFAULT", "この誤字を直してテストも追加して", "Fix this typo and add regression tests."],
  ["DEFAULT", "ダウンロードが終わったら自動的に本番へデプロイして", "Deploy to production when the download finishes."],
  ["DEFAULT", "変更を確認せずにまとめてコミットして push して", "Commit all changes without reviewing and push."],
  [null, "さっきの件、やっぱ直して", "Actually, fix that earlier issue."],
  [null, "そのテスト足して", "Add that test."],
  [null, "それどうする？", "How should we handle that?"],
  [null, "このまま進めて", "Proceed with it."],
];
const classes = Object.keys(config.questions.tier.criteria);
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
    if (!classes.includes(answers?.tier?.choice) || typeof answers.tier.confidence !== "number" ||
        !["CLEAR", "CONTEXT_REQUIRED"].includes(answers?.clarity?.choice) || typeof answers.clarity.confidence !== "number")
      throw new Error("JevK5 returned an invalid classification");
    const result = { language, expected, state, tier: answers.tier.choice, confidence: answers.tier.confidence,
      clarity: answers.clarity.choice, clarityConfidence: answers.clarity.confidence,
      contextual: answers.clarity.choice !== "CLEAR" || answers.clarity.confidence < config.min_context_confidence };
    results.push(result);
    const simple = result.tier === "SIMPLE" && result.confidence >= config.min_confidence && !result.contextual;
    if ((expected === "SIMPLE" && !simple) || (expected === "DEFAULT" && simple) ||
        (expected === null && !result.contextual)) console.log(JSON.stringify(result));
  }
}
for (const language of ["ja", "en"]) {
  const rows = results.filter((row) => row.language === language);
  console.log(JSON.stringify({ language,
    simple: rows.filter((row) => row.expected === "SIMPLE" && row.tier === "SIMPLE" &&
      row.confidence >= config.min_confidence && !row.contextual).length,
    falseSimple: rows.filter((row) => row.expected === "DEFAULT" && row.tier === "SIMPLE" &&
      row.confidence >= config.min_confidence && !row.contextual).length,
    vagueContextDetected: rows.filter((row) => row.expected === null && row.contextual).length,
  }));
}
