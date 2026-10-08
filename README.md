<div align="center">
    <img src="./App/azoo-key-skkserv/Assets.xcassets/AppIcon.appiconset/Icon-512.png" width="150" height="150">
    <h1>
        azoo-key-skkserv        
    </h1>
</div>

[AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)を変換に利用するskkservです。  
AzooKeyKanaKanjiConverterから参照される、ニューラルかな漢字変換システム「Zenzai」で利用するモデルは[zenz-v1](https://huggingface.co/Miwa-Keita/zenz-v1)を利用させていただいています。

zenz-v1はKeita Miwa ([𝕏](https://x.com/miwa_ensan))さんによって開発され、[CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/deed.ja)で提供されています。

Linux環境向けのバイナリには[llama.cpp](https://github.com/ggml-org/llama.cpp)の[Shared Object](https://github.com/ggml-org/llama.cpp/releases/tag/b4846)を同梱させていただいております。  
かつ `RUNPATH` を `$ORIGIN` にpatchさせていただいております。

## このフォークについて (Linux / NixOS)

[gitusp/azoo-key-skkserv](https://github.com/gitusp/azoo-key-skkserv) の非公開フォークです。Linux 版を NixOS で動かすための Nix flake を足しています。

- `packages.<system>.default`: upstream の Linux リリースを `autoPatchelfHook` で NixOS 向けに組み直したもの (x86_64-linux / aarch64-linux)。
  同梱の llama.cpp は azooKey の fork (`azooKey/llama.cpp` b4846) に差し替えています。upstream 同梱の ggml-org 版は zenz-v1 の
  pre-tokenizer (`gpt2-small-japanese-char`) を知らず、モデルの読み込みに失敗して Zenzai なし (辞書だけ) で動いてしまうためです。
- `homeManagerModules.default`: `services.azoo-key-skkserv` (systemd ユーザーサービス)。
- `overlays.default`: `pkgs.azoo-key-skkserv`。

```nix
# flake.nix
inputs.azoo-key-skkserv.url = "git+ssh://git@github.com/gapul/azoo-key-skkserv";

# home-manager
imports = [ inputs.azoo-key-skkserv.homeManagerModules.default ];
services.azoo-key-skkserv.enable = true; # 127.0.0.1:1178, --incoming-charset UTF-8
```

fcitx5-skk からは `dictionary_list` に次の1行を足します。libskk は要求と応答に同じ文字コードを使い、このサーバーは常に UTF-8 で返すので、両方 UTF-8 にします。

```
type=server,host=127.0.0.1,port=1178,encoding=UTF-8
```

### Linux 版の制限

- **EUC-JP の要求には応答しません。** `--incoming-charset EUC-JP` で起動しても、EUC-JP の要求を受けると候補を返さずに接続が閉じられます (Linux の Foundation が EUC-JP をデコードできないためと思われます)。Linux ではクライアント側も UTF-8 で要求してください (skkeleton なら `skkServerReqEnc = "utf-8"`)。
- **ソースからのビルドは今のところ通りません。** nixpkgs の Swift 6.2.4 では、C++ interop を有効にすると同梱の clang 17 が gcc 16 の libstdc++ ヘッダーを解釈できず、依存の swift-collections の時点で止まります。`nix develop` の devShell は、これが直ったとき用に残しています。

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
