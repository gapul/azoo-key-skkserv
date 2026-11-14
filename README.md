<div align="center">
    <img src="./App/azoo-key-skkserv/Assets.xcassets/AppIcon.appiconset/Icon-512.png" width="150" height="150">
    <h1>
        azoo-key-skkserv        
    </h1>
</div>

[AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)を変換に利用するskkservです。  
AzooKeyKanaKanjiConverterから参照される、ニューラルかな漢字変換システム「Zenzai」で利用するモデルは[zenz-v3.2-small](https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf)を利用させていただいています。

zenzはKeita Miwa ([𝕏](https://x.com/miwa_ensan))さんによって開発され、[CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.ja)で提供されています。

Linux環境向けのバイナリには[llama.cpp](https://github.com/ggml-org/llama.cpp)の[Shared Object](https://github.com/ggml-org/llama.cpp/releases/tag/b4846)を同梱させていただいております。  
かつ `RUNPATH` を `$ORIGIN` にpatchさせていただいております。

## このフォークについて (Linux / NixOS)

このリポジトリ（`gapul/azoo-key-skkserv`）は、`gitusp/azoo-key-skkserv`（MIT ライセンス）の個人用フォークです。元リポジトリに対して以下の変更を加えています。

- **Linux / NixOS 用の Nix flake**: `packages.x86_64-linux.default`、`overlays.default`（`pkgs.azoo-key-skkserv`）、および `homeManagerModules.default`（`services.azoo-key-skkserv` の systemd ユーザーサービス。`127.0.0.1:1178`、`--incoming-charset UTF-8` で起動）を提供します。
- **変換エンジンの更新**: `AzooKeyKanaKanjiConverter` を azooKey Desktop と同じリビジョンに更新し、Zenzai のモデルを `zenz-v1` から `zenz-v3.2-small` に変更しています。
- **文脈つき辞書要求（opcode `5`）の追加**: カーソル前後の文脈を含めた変換要求に対応しています（opcode `0`〜`4` は変更ありません）。たとえば「社長の|いこう|を確認する」では先頭候補が「意向」に、「一緒に公園へ|いこう」では「行こう」になります。

Nix パッケージは、このフォークの GitHub Release で配布している Linux `x86_64` のビルド済みバイナリを `autoPatchelfHook` で組み直したものです。`aarch64` と macOS のバイナリはこのフォークでは配布していません。

同梱している `llama.cpp` の共有ライブラリは azooKey のフォーク（`azooKey/llama.cpp` `b4846`）のものです。`ggml-org` 版の `b4846` は `zenz-v1` の pre-tokenizer（`gpt2-small-japanese-char`）を知らずモデルの読み込みに失敗するため、azooKey 版を使用しています。

### Nix flake の使い方

`flake.nix` の `inputs` に追加し、Home Manager から有効化できます。

```nix
# flake.nix
inputs.azoo-key-skkserv.url = "github:gapul/azoo-key-skkserv";
```

```nix
# Home Manager の設定
imports = [ inputs.azoo-key-skkserv.homeManagerModules.default ];
services.azoo-key-skkserv.enable = true;
```

### fcitx5-skk の設定

libskk は要求と応答に同じ文字コードを使い、このサーバーは常に UTF-8 で返すため、`encoding=UTF-8` を指定します。

標準の `fcitx5-skk` / `libskk` は文脈を送らないため opcode `1` のみを使用し、文脈なしの変換としてそのままこのサーバーを使えます。`dictionary_list` には以下の行を設定します。

```text
type=server,host=127.0.0.1,port=1178,encoding=UTF-8
```

文脈つきの変換（opcode `5`）を使うには、同じ作者による `fcitx5-skk` の個人用フォーク（<https://github.com/gapul/fcitx5-skk> の `feature/context-server` ブランチ）を使用し、`dictionary_list` の行に `context=true` を付けます。

```text
type=server,host=127.0.0.1,port=1178,encoding=UTF-8,context=true
```

文脈は `127.0.0.1` のサーバーに送る想定です。入力中の文章の一部がサーバーに送られることに注意してください。

### Linux 版の制限

- **EUC-JP の要求に応答しない**: `--incoming-charset EUC-JP` で起動しても、EUC-JP の opcode `1` の要求を受けると候補を返しません（Linux の Foundation が EUC-JP をデコードできないためと思われます）。Linux ではクライアント側も UTF-8 で要求してください（skkeleton なら `skkServerReqEnc = "utf-8"`）。opcode `5` は常に UTF-8 なので影響しません。
- **ソースからのビルド**: nixpkgs の Swift 6.2.4 ではソースからのビルドが通りません（C++ interop を有効にすると、同梱の clang 17 が gcc 16 の `libstdc++` ヘッダーを解釈できず、依存の `swift-collections` の時点で止まります）。そのため、GitHub Release のバイナリは `swift:6.2-jammy` のコンテナで `swift build -c release --static-swift-stdlib` を実行してビルドしたものです。`nix develop` の `devShell` は、この問題が直ったときのために残してあります。

## azoo-key-skkservについて

受け取った読みをAzooKeyKanaKanjiConverterで漢字変換し、候補を辞書として返すskkservです。  
これにより例えば:

- `配達業者` などそれぞれの熟語は辞書に入っているけれど、繋がったものは登録されていないケースでも候補を表示できます。
- 送り仮名が不明瞭であったりする際、送り仮名ごと入力しても候補が表示されます。
- SKKの流儀とは反しそうですが、Zenzaiの強力な変換力により、長文をそのまま変換することも可能です。
    - SKKの仕様上ユーザー辞書にそのまま登録されてしまうと思うので、その点はご注意ください。
 
### 動作イメージ

https://github.com/user-attachments/assets/614f87b9-062a-4710-92e2-f275eb80703f

## インストール

### macOS

macOS版はGUIアプリケーションを配布しています。([mtgto](https://github.com/mtgto)さんありがとうございます！)  
[Releases](https://github.com/gitusp/azoo-key-skkserv/releases)に `.dmg` ファイルが置いてあるので、そちらからインストールしてください。  
CLI版も配布しているので、お好みでお使いください。(GUI版の方がmacOS App Sandboxが設定されているので、より安全です。)

macSKKから使用する場合にはIncoming CharsetにEUC-JP、macSKKの応答エンコーディングにUTF-8を指定してください。

### Linux

Linux版はCLI版の配布のみです。  
[Releases](https://github.com/gitusp/azoo-key-skkserv/releases)よりご自身のarchに対応したパッケージをダウンロードし、お好きなところに配置してください。  
パッケージ内の `azoo-key-skkserv` が実行ファイルです。

#### ダイナミックライブラリについて

こちらのLinux検証環境だと `libgomp.so.1` が見つからないエラーが出ました。  
もし見つからない場合は、以下のようなコマンドでインストールしてください。

```sh
apt install libgomp1
```

## 使い方

```sh
azoo-key-skkserv [--port <port-number>] [--incoming-charset <charset>] [--inference-limit <limit>] [--help] [--version]
```

_EUC-JP範囲外の候補があるため `--outgoing-charset` オプションはなく、サーバーからは常にUTF-8で返します。_

### バックグラウンド実行

macOSであれば、ログイン項目にGUI版のアプリケーションを登録しておくのが楽です。  
そうでなければ、以下のようなコマンドがログイン時に実行されるようにしてください。

```sh
nohup ~/opt/azoo-key-skkserv/azoo-key-skkserv --incoming-charset EUC-JP >&/dev/null &
```

## 仕様

skkservの標準に準拠しているつもりです。  
入力の1文字目を `opcode` とし、それ以降を `operand` とした場合:

| opcode | operand  | 説明             | 出力                                                                      |
|--------|----------|------------------|---------------------------------------------------------------------------|
| 0      | なし     | コネクション破棄 | なし                                                                      |
| 1      | 見出し語 | 辞書要求         | 候補がある時: `1/{候補1}/{候補2}/.../{候補n}/\n`<br />候補がない時: `4\n` |
| 2      | なし     | サーバー情報要求 | `azoo-key-skkserv/{バージョン} `                                          |
| 3      | なし     | ホスト情報要求   | `{ホスト名}/127.0.0.1:{ポート}/ `                                         |
| 4      | 見出し語 | 補完要求         | 補完がある時: `1/{補完1}/{補完2}/.../{補完n}/\n`<br />補完がない時: `4\n` |
| 5      | 見出し語 左文脈 右文脈 | 文脈つき辞書要求 (拡張) | opcode 1 と同じ |

opcode `5` は、このフォークで追加した文脈つき辞書要求です（opcode `0`〜`4` は変更ありません）。要求の形式は `5{見出し語} {左文脈} {右文脈}\n` です。改行までを1つの要求として読み、見出し語も含めて `--incoming-charset` によらず UTF-8 として扱います。`{左文脈}` と `{右文脈}` はカーソルの前後のテキストを UTF-8 でパーセントエンコードしたもので、空または省略可能です。サーバーはそれぞれカーソルのある行の最大30文字だけを使い、`zenz-v3` のプロンプトに左右の文脈として渡します。応答の形式は opcode `1` と同じです。文脈は `127.0.0.1` のサーバーに送る想定であり、入力中の文章の一部がサーバーに送られることに注意してください。

```console
$ printf '5いこう %s %s\n' "$(jq -rn '"社長の"|@uri')" "$(jq -rn '"を確認する"|@uri')" | nc -q1 127.0.0.1 1178
1/意向/以降/移行/行こう/...
```

## 開発

```sh
swift run azoo-key-skkserv
```

## 動作検証環境

### macOS(Apple silicon)

[macSKK](https://github.com/mtgto/macSKK)と結合して動作確認

### macOS(Intel)

動作未確認

### Ubuntu(arm64)

macOS上で動作するDockerにて、netcatで動作確認

### Ubuntu(amd64)

一応コンパイルできていそうなのですが、エミュレータだとうまく実行できていません。

## 免責

まだまだ使いながら調整したりしてる段階なので、不具合や不安定なところがあるかと思います。  
もし何かございましたら、Issueでご報告いただいたりPRを投げていただけると大変助かります🙇
