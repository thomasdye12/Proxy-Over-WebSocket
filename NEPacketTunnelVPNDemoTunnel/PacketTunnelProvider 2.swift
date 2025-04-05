//
//  PacketTunnelProvider 2.swift
//  NEPacketTunnelVPNDemo
//
//  Created by Thomas Dye on 05/04/2025.
//  Copyright © 2025 lxd. All rights reserved.
//


//
//  PacketTunnelProvider.swift
//  NEPacketTunnelVPNDemoTunnel
//
//  Created by lxd on 12/8/16.
//  Updated to use WebSockets for packet transport.
//  Copyright © 2016 lxd. All rights reserved.
//

import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    // WebSocket used for sending/receiving tunnel packets.
    var webSocketTask: URLSessionWebSocketTask?
    
    // VPN configuration parameters.
    let serverAddress = "10.0.2.201"
    let serverPort = "54345"
    let mtu = "1400"
    let ip = "10.8.0.2"
    let subnet = "255.255.255.0"
    let dns = "8.8.8.8,8.4.4.4"
    
    // Configuration dictionary used in network settings.
    var conf = [String: String]()
    
    // Recursively read packets from the tunnel and send them over the WebSocket.
    func readAndSendPackets() {
        self.packetFlow.readPackets { [weak self] (packets, protocols) in
            guard let self = self else { return }
            for packet in packets {
                let message = URLSessionWebSocketTask.Message.data(packet)
                print("Sending packet of \(packet.count) bytes")
                self.webSocketTask?.send(message) { error in
                    if let error = error {
                        print("Error sending packet: \(error)")
                    }
                }
            }
            self.readAndSendPackets() // Continue reading packets.
        }
    }
    
    // Recursively receive messages from the WebSocket and write them to the tunnel.
    func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("Error receiving packet: \(error)")
                // Optionally implement a reconnection strategy.
            case .success(let message):
                switch message {
                case .data(let data):
                    self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
                    print("Received packet of \(data.count) bytes")
                case .string(let str):
                    print("Received string: \(str)")
                @unknown default:
                    break
                }
                self.receiveMessages() // Continue receiving messages.
            }
        }
    }
    
    // Start the WebSocket connection to the VPN server.
    func startWebSocket() {
        let url = URL(string: "ws://\(serverAddress):\(serverPort)")!
        let request = URLRequest(url: url)
        webSocketTask = URLSession(configuration: .default).webSocketTask(with: request)
        webSocketTask?.resume()
        // Begin receiving and sending packets.
        receiveMessages()
        readAndSendPackets()
    }
    
    // Set up the tunnel network settings including IP configuration and DNS.
    func setupPacketTunnelNetworkSettings() {
        guard let serverAddr = self.protocolConfiguration.serverAddress else {
            print("No server address in protocolConfiguration")
            return
        }
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverAddr)
        tunnelNetworkSettings.ipv4Settings = NEIPv4Settings(addresses: [conf["ip"]!], subnetMasks: [conf["subnet"]!])
        // Route all traffic through the tunnel.
        tunnelNetworkSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        tunnelNetworkSettings.mtu = NSNumber(value: Int(conf["mtu"]!)!)
        
        let dnsSettings = NEDNSSettings(servers: conf["dns"]!.components(separatedBy: ","))
        // Override system DNS settings.
        dnsSettings.matchDomains = [""]
        tunnelNetworkSettings.dnsSettings = dnsSettings
        
        self.setTunnelNetworkSettings(tunnelNetworkSettings) { error in
            if let error = error {
                print("Error setting tunnel network settings: \(error)")
            } else {
                print("Tunnel network settings applied.")
            }
        }
    }
    
    // Called when the VPN tunnel is started.
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
        print(conf)
        
        // Configure the tunnel's network settings.
        setupPacketTunnelNetworkSettings()
        // Start the WebSocket connection.
        startWebSocket()
        completionHandler(nil)
    }
    
    // Called when the VPN tunnel is stopped.
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
}
