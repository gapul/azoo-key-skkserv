// SPDX-License-Identifier: MIT

import Foundation
import NIOCore
import NIOPosix
import KanaKanjiConverterModuleWithDefaultDictionary
import Logging

/// opcode 5で受け取る文脈の上限文字数。azooKey on macOSの変換時の取得長に合わせている。
let maxContextLength = 30

private func createZenzaiMode(inferenceLimit: Int, leftSideContext: String? = nil, rightSideContext: String? = nil) -> ConvertRequestOptions.ZenzaiMode {
    return .on(
        weight: Bundle.module.url(forResource: "zenz-v3.2-small", withExtension: "gguf")!,
        inferenceLimit: inferenceLimit,
        personalizationMode: nil,
        versionDependentMode: .v3(.init(
            leftSideContext: leftSideContext,
            rightSideContext: rightSideContext,
            maxLeftSideContextLength: maxContextLength,
            maxRightSideContextLength: maxContextLength
        ))
    )
}

private func createConvertOption(inferenceLimit: Int, version: String, requireJapanesePrediction: Bool = false, leftSideContext: String? = nil, rightSideContext: String? = nil) -> ConvertRequestOptions {
    return ConvertRequestOptions(
        // 日本語予測変換
        requireJapanesePrediction: requireJapanesePrediction ? .autoMix : .disabled,
        // 英語予測変換
        requireEnglishPrediction: .disabled,
        // 入力言語
        keyboardLanguage: .ja_JP,
        // 学習タイプ
        learningType: .nothing,
        // TODO: 扱いについて検討
        memoryDirectoryURL: URL(fileURLWithPath: ""),
        sharedContainerURL: URL(fileURLWithPath: ""),
        textReplacer: .withDefaultEmojiDictionary(),
        specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
        zenzaiMode: createZenzaiMode(inferenceLimit: inferenceLimit, leftSideContext: leftSideContext, rightSideContext: rightSideContext),
        metadata: .init(versionString: version)
    )
}

private func sanitizeYomi(yomi: String) -> String {
    return yomi.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacing(/([ぁ-ん])[a-z]$/) { matches in matches.1 }
}

/**
 * opcode 5の文脈を取り出す。
 *
 * 文脈はUTF-8をパーセントエンコードしたもので、空白・改行を含まない。
 * 行の区切りには、1文字として扱われるCRLFも含める。
 * azooKey on macOSと同じく、左文脈はカーソルのある行だけ、右文脈も同じ行だけを使う。
 */
func parseContext(_ field: Substring?, side: ContextSide) -> String? {
    guard let field, !field.isEmpty, let decoded = field.removingPercentEncoding else {
        return nil
    }
    switch side {
    case .left:
        let line = decoded.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? decoded[...]
        let trimmed = line.drop(while: { $0.isWhitespace }).suffix(maxContextLength)
        return trimmed.isEmpty ? nil : String(trimmed)
    case .right:
        let line = decoded.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first ?? decoded[...]
        var trimmed = line.prefix(maxContextLength)
        while trimmed.last?.isWhitespace ?? false {
            trimmed = trimmed.dropLast()
        }
        return trimmed.isEmpty ? nil : String(trimmed)
    }
}

enum ContextSide {
    case left
    case right
}

@MainActor public struct SKKServer {
    let allocator = ByteBufferAllocator()
    let converter: KanaKanjiConverter
    let version: String
    let logger: Logger

    public init(version: String, logger: Logger) {
        self.version = version
        self.logger = logger
        // コンバータ初期化
        converter = KanaKanjiConverter.withDefaultDictionary()
    }

    public func prepare() {
        // HACK: ダミーリクエストを送信してモデルを先読みしておく
        var dummyComposingText = ComposingText()
        dummyComposingText.insertAtCursorPosition("もでるさきよみ", inputStyle: .direct)
        let convertOption = createConvertOption(inferenceLimit: 1, version: version)
        _ = converter.requestCandidates(dummyComposingText, options: convertOption)
    }

    /**
      * SKKServを起動する。
      *
      * Taskの中でrunServerを実行しTask.cancel()を呼び出すことでサーバーを停止できる。
      *
      * ```swift
      * // SKKServを起動
      * let task = Task {
      *     do {
      *         try await run()
      *     } catch is CancellationError {
      *         // タスクがキャンセルされたとき
      *     } catch {
      *         // その他のエラーが発生したとき
      *     }
      * }
      * // SKKServを停止
      * task.cancel()
      * ```
      */
    public func run(host: String = "127.0.0.1", port: Int = 1178, incomingCharset: String.Encoding = .utf8, inferenceLimit: Int = 1) async throws {
        let convertOption = createConvertOption(inferenceLimit: inferenceLimit, version: version)
        let predictionOption = createConvertOption(inferenceLimit: inferenceLimit, version: version, requireJapanesePrediction: true)

        // こちらのガイドを参考に実装した。
        // https://swiftonserver.com/using-swiftnio-channels/
        let server = try await ServerBootstrap(group: NIOSingletons.posixEventLoopGroup)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(
                host: host,
                port: port
            ) { channel in
                channel.eventLoop.makeCompletedFuture {
                    return try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: NIOAsyncChannel.Configuration(
                            inboundType: ByteBuffer.self,
                            outboundType: ByteBuffer.self
                        )
                    )
                }
            }
        logger.notice("Server started on port \(port) with incoming charset \(incomingCharset.rawValue).")

        try await withThrowingDiscardingTaskGroup { group in
            try await server.executeThenClose { clients in
                for try await client in clients {
                    group.addTask {
                        await handleClient(client: client, host: host, port: port, incomingCharset: incomingCharset, convertOption: convertOption, predictionOption: predictionOption, inferenceLimit: inferenceLimit)
                    }
                }
            }
        }
    }

    /// 読みを変換し、skkservの辞書要求への応答を返す
    func convert(yomi: String, options: ConvertRequestOptions) -> String {
        // 要求ごとに独立して変換する。前の要求の入力状態を引き継ぐと、同じ読みで文脈だけ違うときに前の結果が使われうる。
        converter.stopComposition()
        var composingText = ComposingText()
        composingText.insertAtCursorPosition(yomi, inputStyle: .direct)
        let results = converter.requestCandidates(composingText, options: options)
        let excludeTexts = yomi.applyingTransform(.hiraganaToKatakana, reverse: false)
            .map { katakana in katakana != yomi ? Set([yomi, katakana]) : Set([yomi]) }
            ?? Set([yomi])
        let candidates = results.mainResults
            // 読み全文に対応するもの以外・読みと完全一致するもの・読みのカタカナ版と一致するものは除去
            .filter({ result in result.rubyCount == yomi.count && !excludeTexts.contains(result.text) })
        return candidates.count == 0
        ? "4\n"
        : "1/"
        + candidates.map({ result in result.text }).joined(by: "/")
        + "/\n"
    }

    func handleClient(client: NIOAsyncChannel<ByteBuffer, ByteBuffer>, host: String, port: Int, incomingCharset: String.Encoding, convertOption: ConvertRequestOptions, predictionOption: ConvertRequestOptions, inferenceLimit: Int) async {
        // クライアントが先にソケットを閉じている状態でソケットへの書き込みを行ったりすると例外が発生し、
        // そのあとの接続でinboundMessagesからメッセージが取得できなくなってしまう。
        // それを防ぐため例外をキャッチする必要がある。
        do {
            try await client.executeThenClose { inboundMessages, outbound in
                // opcode 5は改行までを1つの要求とする。文脈が長いと1回の読み取りに収まらず、
                // 分かれて届いた残りを別の要求として扱うと、以降の応答がずれてしまう。
                // それ以外のopcodeは従来どおり1回の読み取りを1つの要求とする。
                var pending: [UInt8] = []
                for try await inboundMessage in inboundMessages {
                    guard let received = inboundMessage.getBytes(at: 0, length: inboundMessage.readableBytes) else {
                        continue
                    }
                    pending += received
                    while let first = pending.first {
                        let request: [UInt8]
                        if first == UInt8(ascii: "5") {
                            guard let newline = pending.firstIndex(of: UInt8(ascii: "\n")) else {
                                break
                            }
                            request = Array(pending[..<newline])
                            pending.removeSubrange(...newline)
                        } else {
                            request = pending
                            pending = []
                        }
                        // opcode 5の見出し語と文脈は、incoming charsetによらずUTF-8とする
                        guard let message = first == UInt8(ascii: "5")
                            ? String(bytes: request, encoding: .utf8)
                            : String(bytes: request, encoding: incomingCharset) else {
                            logger.warning("Undecodable request")
                            continue
                        }
                        let opcode = message.prefix(1)
                        switch (opcode) {
                        case "0":
                            return
                        case "1":
                            let yomi = sanitizeYomi(yomi: String(message.suffix(message.count - 1)))
                            try await outbound.write(allocator.buffer(string: convert(yomi: yomi, options: convertOption)))
                        case "2":
                            try await outbound.write(allocator.buffer(string: "azoo-key-skkserv/" + version + " "))
                        case "3":
                            let hostname = Host.current().localizedName ?? ""
                            try await outbound.write(allocator.buffer(string: "\(hostname)/\(host):\(port) "))
                        case "4":
                            let yomi = sanitizeYomi(yomi: String(message.suffix(message.count - 1)))
                            var composingText = ComposingText()
                            composingText.insertAtCursorPosition(yomi, inputStyle: .direct)
                            let results = converter.requestCandidates(composingText, options: predictionOption)
                            var seen = Set<String>()
                            let candidates = results.mainResults
                                // 読み全文以下の文字長の候補・result.dataが複数の候補は除外
                                .filter({ result in result.data.count == 1 && result.rubyCount > yomi.count })
                                // ひらがなに変換(できないものは除外)
                                .compactMap({ result in result.data.map({ d in d.ruby }).joined().applyingTransform(.hiraganaToKatakana, reverse: true)})
                                // 重複を除去(最初の出現を保持)
                                .filter({ seen.insert($0).inserted })
                            let content = candidates.count == 0
                            ? "4\n"
                            : "1/"
                            + candidates.joined(by: "/")
                            + "/\n"
                            try await outbound.write(allocator.buffer(string: content))
                        case "5":
                            // 拡張: 文脈つき辞書要求。`5{見出し語} {左文脈} {右文脈}\n`
                            // 文脈はUTF-8のパーセントエンコードで、省略・空文字列も可。応答はopcode 1と同じ。
                            let fields = message.dropFirst().split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                            let yomi = sanitizeYomi(yomi: String(fields.first ?? ""))
                            let options = createConvertOption(
                                inferenceLimit: inferenceLimit,
                                version: version,
                                leftSideContext: parseContext(fields.count > 1 ? fields[1] : nil, side: .left),
                                rightSideContext: parseContext(fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespacesAndNewlines)[...] : nil, side: .right)
                            )
                            try await outbound.write(allocator.buffer(string: convert(yomi: yomi, options: options)))
                        default:
                            logger.warning("Unsupported opcode: \(opcode)")
                            break
                        }
                    }
                }
            }
            logger.notice("Connection is closed")
        } catch {
            logger.warning("Hit error: \(error)")
        }
    }
}
