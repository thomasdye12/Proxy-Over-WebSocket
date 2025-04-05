const http = require('http');
const WebSocket = require('ws');
const {Tun, Tap} = require('tuntap2');
const { exec } = require('child_process');

// Create a TUN interface named 'tun0'.
// Adjust options as needed (e.g. type, name).
const tun = new Tun();
tun.ipv4 = '10.8.0.1/24';
tun.isUp = true;


// const tun = tuntap({
//   type: 'tun',
//   name: 'tun0'
// });

// Log any data received from the TUN interface (packets coming from the server network).
tun.on('data', (packet) => {
  console.log(`Received packet from TUN interface (${packet.length} bytes)`);

  // Broadcast this packet to every connected WebSocket client.
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(packet);
    }
  });
});


// Create an HTTP server to upgrade connections to WebSocket.
const server = http.createServer();

// Create the WebSocket server on top of the HTTP server.
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  console.log('WebSocket client connected from', req.socket.remoteAddress);

  // When a packet is received from a WebSocket client (i.e. from the VPN client):
  ws.on('message', (message) => {
    // Note: The message is expected to be a Buffer containing a raw IP packet.
    console.log(`Received packet from WebSocket client (${message.length} bytes)`);
    
    // Write the packet into the TUN interface.
    tun.write(message);
  });

  ws.on('close', () => {
    console.log('WebSocket client disconnected');
  });

  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
  });
});

// Start the HTTP/WebSocket server.
const port = 54345; // Make sure this matches the port used in your Swift VPN configuration.
server.listen(port, () => {
  console.log(`Server is listening on port ${port}`);
});
