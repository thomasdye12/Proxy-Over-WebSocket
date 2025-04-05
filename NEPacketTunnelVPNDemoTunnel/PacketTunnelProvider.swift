
//
//  PacketTunnelProvider.swift
//  NEPacketTunnelVPNDemoTunnel
//
//  Created by lxd on 12/8/16.
//  Updated to use WebSockets for packet transport with a full client implementation.
//  Copyright © 2016 lxd. All rights reserved.
//

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider, URLSessionWebSocketDelegate {
    
    // WebSocket used for sending/receiving tunnel packets.
    var webSocketTask: URLSessionWebSocketTask?
    var urlSession: URLSession?
    
    // VPN configuration parameters.
    let serverAddress = "54.90.235.134"
    let serverPort = "54345"
    let mtu = "1400"
    let ip = "10.8.0.2"
    let subnet = "255.255.255.0"
    let dns = "8.8.8.8,8.4.4.4"
    
    // Configuration dictionary used in network settings.
    var conf = [String: String]()
    
    // MARK: - WebSocket Connection and Messaging
    
    /// Creates and starts the WebSocket connection.
    func connectWebSocket() {
        let urlString = "ws://\(serverAddress):\(serverPort)"
        guard let url = URL(string: urlString) else {
            print("Invalid WebSocket URL")
            return
        }
        let config = URLSessionConfiguration.default
        // Set self as delegate to receive connection events.
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue())
        self.webSocketTask = self.urlSession?.webSocketTask(with: url)
        self.webSocketTask?.resume()
        print("WebSocket connecting to \(urlString)")
        // Start listening for incoming messages.
        receiveMessages()
    }
    
    /// Recursively reads packets from the tunnel and sends them over the WebSocket.
    func readAndSendPackets() {
        self.packetFlow.readPackets { [weak self] (packets, protocols) in
            guard let self = self else { return }
            for packet in packets {
                let message = URLSessionWebSocketTask.Message.data(packet)
                self.webSocketTask?.send(message) { error in
                    if let error = error {
                        print("Error sending packet: \(error)")
                    }
                }
            }
            // Continue reading packets.
            self.readAndSendPackets()
        }
    }
    
    /// Recursively receives messages from the WebSocket and writes them to the tunnel.
    func receiveMessages() {
        self.webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("Error receiving message: \(error)")
                // Optionally handle reconnection or error cleanup.
            case .success(let message):
                switch message {
                case .data(let data):
                    // Write the received data to the tunnel.
                    self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
                case .string(let text):
                    // Optionally handle string messages (for control messages, logging, etc.).
                    print("Received string message: \(text)")
                @unknown default:
                    print("Received unknown message type")
                }
                // Continue receiving messages.
                self.receiveMessages()
            }
        }
    }
    
    // MARK: - Tunnel Network Settings
    
    /// Sets up the tunnel's network settings.
    func setupPacketTunnelNetworkSettings() {
        guard let serverAddr = self.protocolConfiguration.serverAddress else {
            print("No server address in protocolConfiguration")
            return
        }
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverAddr)
        
        // Set the tunnel's IP address and subnet.
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [conf["ip"]!], subnetMasks: [conf["subnet"]!])
        
        // Route all IPv4 traffic through the tunnel.
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        tunnelNetworkSettings.mtu = NSNumber(value: Int(conf["mtu"]!)!)
        
        // Override DNS settings to ensure DNS queries are tunneled.
        let dnsSettings = NEDNSSettings(servers: conf["dns"]!.components(separatedBy: ","))
        dnsSettings.matchDomains = [""]
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        // Exclude VPN server’s IP from the tunnel.
        if let serverIP = conf["server"] {
            let serverRoute = NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255")
            tunnelNetworkSettings.ipv4Settings?.excludedRoutes = [serverRoute]
        }
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                print("Error setting tunnel network settings: \(error)")
            } else {
                print("Tunnel network settings applied.")
            }
        }
    }
    
    // MARK: - Tunnel Lifecycle Methods
    
    /// Called when the VPN tunnel is started.
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        // Log the provider configuration.
        print("Provider Configuration: \((self.protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration)")
        
        // Set up configuration dictionary.
        conf = ["port": serverPort,
                "server": serverAddress,
                "ip": ip,
                "subnet": subnet,
                "mtu": mtu,
                "dns": dns]
        print("Tunnel configuration: \(conf)")
        
        // Configure the tunnel's network settings.
        setupPacketTunnelNetworkSettings()
        // Connect to the VPN server via WebSocket.
        connectWebSocket()
        // Start reading and sending packets from the tunnel.
        readAndSendPackets()
        completionHandler(nil)
    }
    
    /// Called when the VPN tunnel is stopped.
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        super.stopTunnel(with: reason, completionHandler: completionHandler)
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)? = nil) {
        if let handler = completionHandler {
            handler(messageData)
        }
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    override func wake() {
    }
    
    // MARK: - URLSessionWebSocketDelegate Methods
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket did open")
    }
    

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket did close with code: \(closeCode)")
        
        // Prepare an alert message as JSON.
        let alertMessage = "Socket disconnected with code: \(closeCode.rawValue)"
        if let alertData = try? JSONSerialization.data(withJSONObject: ["alert": alertMessage], options: []) {
//            // Send the message to the containing app.
//            self.sendProviderMessage(alertData) { response in
//                print("Alert message sent to the app.")
//            }
        }
    }
}
