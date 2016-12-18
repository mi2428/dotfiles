bindkey -e                          # Emacsバインド

export HISTSIZE=10000               # 10000行の履歴を記録
export SAVEHIST=10000
export HISTFILE=$HOME/.zhistory     # ヒストリファイルの指定
setopt BANG_HIST                    # cshのヒストリ拡張を使う
#setopt HIST_IGNORE_DUPS            # 重複するコマンドを記憶しない
setopt HIST_IGNORE_ALL_DUPS         # 重複するコマンドが来たら古いものを削除
setopt HIST_IGNORE_SPACE            # 先頭スペースは記憶しない
setopt HIST_REDUCE_BLANKS           # 空白は削除して記憶
setopt SHARE_HISTORY                # 履歴の共有

setopt ALWAYS_TO_END                # 補完時にカーソルを末尾に移動させる
setopt NO_BEEP                      # 端末ベルを使用しない
setopt AUTO_CD                      # ディレクトリ名で移動
setopt AUTOPUSHD                    # cdするときpushdする
setopt PUSHD_IGNORE_DUPS            # 同じディレクトリはpushdしない
setopt CORRECT                      # コマンドの入力ミスを指摘させる
#setopt CORRECT_ALL                 # 全引数に修正を加えさせる
setopt MAGIC_EQUAL_SUBST            # =以降も補完させる
setopt PROMPT_SUBST                 # プロンプトで変数拡張 コマンド置換 計算拡張を実行
setopt NOTIFY                       # バックグラウンドジョブの状態を通知する
setopt AUTO_LIST                    # 曖昧入力時にリストを表示する
setopt AUTO_MENU                    # 
setopt LIST_PACKED                  # 補完候補をなるべく短く表示
setopt LIST_TYPES                   # 補完候補を種類別表示する
setopt NO_LIST_BEEP                 # 曖昧補完時にビープ音を鳴らさない
setopt IGNORE_EOF                   # <C-d>でログアウトしない

autoload -U compinit                # 補完機能をロード
compinit -u
zstyle ':completion:*:default' menu select=2
zstyle ':completion:*' verbose yes
zstyle ':completion:*' completer _expand _complete _match _prefix _approximate _list _history
zstyle ':completion:*:messages' format '%F{YELLOW}%d'$DEFAULT
zstyle ':completion:*:warnings' format '%F{RED}No matches for:''%F{YELLOW} %d'$DEFAULT
zstyle ':completion:*:descriptions' format '%F{YELLOW}completing %B%d%b'$DEFAULT
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:descriptions' format '%F{yellow}Completing %B%d%b%f'$DEFAULT
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-separator '-->'
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
