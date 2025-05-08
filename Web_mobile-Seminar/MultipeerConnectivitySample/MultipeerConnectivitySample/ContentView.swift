import SwiftUI
import MultipeerConnectivity

// メインのビュー
struct ContentView: View {
    // MultipeerManagerをStateObjectとして保持
    @StateObject private var multipeerManager = MultipeerManager()
    // 送信するメッセージを格納する状態変数
    @State private var messageToSend: String = ""
    
    var body: some View {
        VStack {
            // ヘッダー表示
            Text("Received Messages")
                .font(.headline)
            
            // 受信したメッセージをリスト形式で表示
            List(multipeerManager.receivedMessages, id: \.self) { message in
                Text(message)
            }
            
            // メッセージ入力フィールドと送信ボタン
            HStack {
                // テキストフィールドでメッセージを入力
                TextField("Enter message", text: $messageToSend)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                // メッセージ送信ボタン
                Button("Send") {
                    multipeerManager.send(messageToSend)
                    messageToSend = "" // 送信後は入力をクリア
                }
                // 入力が空、または接続されているピアがいない場合はボタンを無効化
                .disabled(messageToSend.isEmpty || multipeerManager.connectedPeers.isEmpty)
            }
            .padding()
            
            // 接続状態を表示（接続ピア数）
            Text("Connected Peers: \(multipeerManager.connectedPeers.count)")
                .font(.caption)
                .foregroundColor(multipeerManager.connectedPeers.isEmpty ? .red : .green)
        }
        // ビューが表示された際にMultipeerManagerを開始
        .onAppear {
            multipeerManager.start()
        }
        // ビューが非表示になる際にMultipeerManagerを停止
        .onDisappear {
            multipeerManager.stop()
        }
    }
}

// MultipeerConnectivityを管理するクラス
class MultipeerManager: NSObject, ObservableObject {
    // サービスの種類を定義
    private let serviceType = "mpc-chat"
    // 自身のMCPeerIDを保持
    private let myPeerId: MCPeerID
    // MCSessionを保持
    private var session: MCSession!
    // ピアを探索するためのブラウザを保持
    private var browser: MCNearbyServiceBrowser!
    // ピアを発見されるためのアドバタイザを保持
    private var advertiser: MCNearbyServiceAdvertiser!
    
    // 受信したメッセージを保持
    @Published var receivedMessages: [String] = []
    // 接続されているピアを保持
    @Published var connectedPeers: [MCPeerID] = []
    
    // 初期化処理
    override init() {
        // デバイス名を加工してMCPeerIDの表示名として使用する
        let deviceName = UIDevice.current.name
            .replacingOccurrences(of: " ", with: "_") // スペースをアンダースコアに変換
            .folding(options: .diacriticInsensitive, locale: .current) // 発音記号を削除
            .components(separatedBy: CharacterSet.alphanumerics.inverted) // 非アルファベット文字を削除
            .joined(separator: "_")
        
        // デバイス名を10文字以内にトリミング
        let truncatedName = String(deviceName.prefix(10))
        
        // MCPeerIDを作成
        myPeerId = MCPeerID(displayName: truncatedName)
        super.init()
        
        // セッションのセットアップ
        setupSession()
    }
    
    // セッションのセットアップを行う
    private func setupSession() {
        session = MCSession(
            peer: myPeerId,
            securityIdentity: nil, // セキュリティ識別子は不要
            encryptionPreference: .required // 通信は暗号化を必須に設定
        )
        session.delegate = self // デリゲートを設定
    }
    
    // ピア探索とアドバタイジングを開始
    func start() {
        print("MultipeerManager: Starting services with peer ID: \(myPeerId.displayName)")
        
        // ブラウザの設定と開始
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers() // ピアの探索を開始
        
        // アドバタイザの設定と開始
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer() // ピアに自身をアナウンス
    }
    
    // ピア探索とアドバタイジングを停止
    func stop() {
        if browser != nil {
            browser.stopBrowsingForPeers() // ピアの探索を停止
            print("MultipeerManager: Stopped browsing")
        }
        
        if advertiser != nil {
            advertiser.stopAdvertisingPeer() // アドバタイジングを停止
            print("MultipeerManager: Stopped advertising")
        }
        
        if !session.connectedPeers.isEmpty {
            session.disconnect() // セッションを切断
            print("MultipeerManager: Disconnected session")
        }
    }
    
    // デイニシャライザで停止処理を呼び出し
    deinit {
        stop()
    }
    
    // メッセージを送信
    func send(_ message: String) {
        // 接続されたピアが存在し、メッセージが有効な場合のみ送信
        guard !session.connectedPeers.isEmpty, let data = message.data(using: .utf8) else {
            print("MultipeerManager: No connected peers or invalid message")
            return
        }
        
        do {
            // メッセージを接続されたすべてのピアに送信
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("MultipeerManager: Sent message to \(session.connectedPeers.count) peer(s)")
        } catch {
            print("MultipeerManager: Error sending message: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerManager: MCSessionDelegate {
    // ピアの状態が変更された場合の処理
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("MultipeerManager: Connected to peer: \(peerID.displayName)")
                self.connectedPeers = session.connectedPeers // 接続されたピアを更新
            case .connecting:
                print("MultipeerManager: Connecting to peer: \(peerID.displayName)")
            case .notConnected:
                print("MultipeerManager: Disconnected from peer: \(peerID.displayName)")
                self.connectedPeers = session.connectedPeers // 接続ピアを更新
            @unknown default:
                print("MultipeerManager: Unknown state for peer: \(peerID.displayName)")
            }
        }
    }
    
    // データを受信した際の処理
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let message = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                // メッセージをフォーマットしてリストに追加
                let formattedMessage = "[\(peerID.displayName)]: \(message)"
                self.receivedMessages.append(formattedMessage)
                print("MultipeerManager: Received: \(formattedMessage)")
            }
        }
    }
    
    // ストリーム受信は未実装
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    // リソース受信開始は未実装
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    // リソース受信完了は未実装
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    // ピアを発見した際の処理
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("MultipeerManager: Found peer: \(peerID.displayName)")
        
        // セッションへの招待を送信
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    // ピアを見失った際の処理
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("MultipeerManager: Lost peer: \(peerID.displayName)")
    }
    
    // ピア探索の開始に失敗した際の処理
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("MultipeerManager: Failed to start browsing: \(error.localizedDescription)")
        printDetailedError(error) // 詳細なエラー情報を表示
    }
    
    // エラー詳細を出力する関数
    private func printDetailedError(_ error: Error) {
        print("Error domain: \((error as NSError).domain)")
        print("Error code: \((error as NSError).code)")
        print("Error description: \(error.localizedDescription)")
        print("User info: \((error as NSError).userInfo)")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    // ピアからの招待を受け取った際の処理
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("MultipeerManager: Invitation from: \(peerID.displayName)")
        invitationHandler(true, session) // 招待を受け入れる
    }
    
    // アドバタイジングの開始に失敗した際の処理
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("MultipeerManager: Failed to start advertising: \(error.localizedDescription)")
        printDetailedError(error) // 詳細なエラー情報を表示
    }
}