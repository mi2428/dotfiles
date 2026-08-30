# Deep Research

1. 依頼全体を`deep_research`へ渡し、1回だけ呼ぶ。
2. 通常は`standard`、短い確認は`quick`、網羅性や反証確認が必要な場合だけ`deep`を選ぶ。
3. 完了まで待ち、通常のWeb検索、URL取得、サブエージェント、コード実行、Note、同じ調査の再呼び出しは使わない。
4. tool resultの`answer_markdown`を、引用記号、URL、数値、日付、事実関係を変えずにそのまま返す。
5. toolが失敗した場合は成功したように補完せず、エラーを伝える。
