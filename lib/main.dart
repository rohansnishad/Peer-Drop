
//////////////////////////   NEW BUILD    /////////////////////////

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  static final FlutterLocalNotificationsPlugin notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: EnterNameScreen(),
    );
  }
}

class EnterNameScreen extends StatefulWidget {
  @override
  State<EnterNameScreen> createState() => _EnterNameScreenState();
}

class _EnterNameScreenState extends State<EnterNameScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    requestPermissions();
    initializeNotifications();
  }

  void initializeNotifications() {
    final initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    MyApp.notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermissions() async {
    var permissions = [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ];
    var statuses = await permissions.request();

    if (statuses.values.any((e) => e.isPermanentlyDenied)) {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Your Name')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0),
                  ),
                  elevation: 5,
                ),
                onPressed: () {
                  final name = _nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RadarScreen(userName: name),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a name.')),
                    );
                  }
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RadarScreen extends StatefulWidget {
  final String userName;

  const RadarScreen({super.key, required this.userName});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  final Strategy strategy = Strategy.P2P_STAR;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<Map<String, String>> detectedDevices = [];
  final Map<String, ConnectionInfo> connectedDevices = {};
  final Map<String, List<String>> conversations = {}; // Store conversation per device

  late AnimationController _controller;
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    Nearby().stopDiscovery();
    Nearby().stopAdvertising();
    super.dispose();
  }

  Future<void> startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        widget.userName,
        strategy,
        onEndpointFound: (id, name, serviceId) {
          setState(() {
            detectedDevices.add({'id': id, 'name': name});
          });
        },
        onEndpointLost: (id) {
          setState(() {
            detectedDevices.removeWhere((device) => device['id'] == id);
          });
        },
      );
      setState(() {
        isScanning = true;
        _controller.repeat();
      });
    } catch (e) {
      print('Discovery failed: $e');
    }
  }

  void stopDiscovery() {
    Nearby().stopDiscovery();
    _controller.stop();
    setState(() {
      isScanning = false;
    });
  }

  Future<void> startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        widget.userName,
        strategy,
        onConnectionInitiated: (id, info) {
          // Accept the connection and store the ConnectionInfo
          connectedDevices[id] = info;

          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endid, payload) {
              if (payload.type == PayloadType.BYTES) {
                String message = String.fromCharCodes(payload.bytes!);

                if (_chatScreens.containsKey(endid)) {
                  _chatScreens[endid]?.receiveMessage(message, connectedDevices[endid]?.endpointName ?? 'Unknown');
                }

                conversations.putIfAbsent(endid, () => []).add(message);
                showNotification(endid, message);
              }
            },
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            setState(() {
              detectedDevices.removeWhere((device) => device['id'] == id);
            });
          }
          print('Advertising connection result: $status with ${connectedDevices[id]?.endpointName}');
        },
        onDisconnected: (id) {
          setState(() {
            connectedDevices.remove(id);
          });
          print('Disconnected from ${connectedDevices[id]?.endpointName}');
        },
      );
    } catch (e) {
      print('Advertising failed: $e');
    }
  }

  Future<void> showNotification(String endid, String message) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your_channel_id', 'your_channel_name',
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );
    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await MyApp.notificationsPlugin.show(
      0,
      'New message from ${connectedDevices[endid]?.endpointName ?? 'Unknown'}',
      message,
      platformChannelSpecifics,
    );
  }

  void stopAdvertising() {
    Nearby().stopAdvertising();
  }

  void requestConnection(String id, String name) {
    Nearby().requestConnection(
      widget.userName,
      id,
      onConnectionInitiated: (id, info) {
        // Accept the connection and handle the ConnectionInfo
        connectedDevices[id] = info;
        setState(() {
          detectedDevices.removeWhere((device) => device['id'] == id);
        });

        Nearby().acceptConnection(
          id,
          onPayLoadRecieved: (endid, payload) {
            if (payload.type == PayloadType.BYTES) {
              String message = String.fromCharCodes(payload.bytes!);

              if (_chatScreens.containsKey(endid)) {
                _chatScreens[endid]?.receiveMessage(message, connectedDevices[endid]?.endpointName ?? 'Unknown');
              }

              conversations.putIfAbsent(endid, () => []).add(message);
              showNotification(endid, message);
            }
          },
        );
      },
      onConnectionResult: (id, status) {
        if (status == Status.CONNECTED) {
          setState(() {
            connectedDevices[id] = connectedDevices[id]!; // Ensures UI update
          });
          print('Connection result: $status with ${connectedDevices[id]?.endpointName}');
        }
      },
      onDisconnected: (id) {
        setState(() {
          connectedDevices.remove(id);
        });
        print('Disconnected from ${connectedDevices[id]?.endpointName}');
      },
    );
  }

  void navigateToPrivateChat(String id) {
    if (connectedDevices.containsKey(id)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            targetName: connectedDevices[id]?.endpointName ?? 'Unknown',
            targetId: id,
            userName: widget.userName,
            conversation: conversations[id] ?? [],
          ),
        ),
      );
    }
  }

  void navigateToPublicChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PublicChatScreen(
          userName: widget.userName,
          connectedDevices: connectedDevices.map((id, info) =>
              MapEntry(id, {'id': id, 'name': info.endpointName})),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text('${widget.userName}'),
        actions: [
          IconButton(
            icon: Icon(Icons.devices),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            tooltip: 'Connected Devices',
          ),
          IconButton(
            icon: Icon(Icons.chat),
            onPressed: navigateToPublicChat,
            tooltip: 'Public Chat',
          ),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(
                'Connected Devices',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ...connectedDevices.entries.map((entry) {
              final id = entry.key;
              final info = entry.value;
              return ListTile(
                title: Text(info.endpointName),
                onTap: () => navigateToPrivateChat(id),
              );
            }).toList(),
          ],
        ),
      ),
      body: Center(
        child: isScanning
            ? Stack(
          children: [
            CustomPaint(
              painter: RadarPainter(animation: _controller),
              child: Container(),
            ),
            ...detectedDevices.map((device) => _buildDeviceMarker(device['id']!, device['name']!)),
          ],
        )
            : const Text('Tap Scan to start discovering devices'),
      ),
      floatingActionButton: Wrap(
        direction: Axis.horizontal,
        children: [
          FloatingActionButton.extended(
            onPressed: startDiscovery,
            label: const Text("Scan"),
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            onPressed: isScanning ? stopDiscovery : stopAdvertising,
            label: const Text("Stop"),
            icon: const Icon(Icons.stop),
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            onPressed: startAdvertising,
            label: const Text("Go"),
            icon: const Icon(Icons.wifi_tethering),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceMarker(String id, String name) {
    Random rand = Random();
    return Positioned(
      left: rand.nextDouble() * (MediaQuery.of(context).size.width - 50),
      top: rand.nextDouble() * (MediaQuery.of(context).size.height - 200),
      child: GestureDetector(
        onTap: () => requestConnection(id, name),
        child: Chip(
          label: Text(name),
          backgroundColor: Colors.blue.withOpacity(0.7),
        ),
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final Animation<double> animation;

  RadarPainter({required this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.blue.withOpacity(0.2);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 * animation.value;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class ChatScreen extends StatefulWidget {
  final String userName;
  final String targetName;
  final String targetId;
  final List<String> conversation;

  ChatScreen({required this.userName, required this.targetName, required this.targetId, required this.conversation});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  late List<String> _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;

    _chatScreens[widget.targetId] = this;
  }

  @override
  void dispose() {
    _chatScreens.remove(widget.targetId);
    super.dispose();
  }

  void receiveMessage(String message, String senderName) {
    setState(() {
      _conversation.add('$senderName: $message');
    });
  }

  void sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    Nearby().sendBytesPayload(widget.targetId, Uint8List.fromList(message.codeUnits));
    setState(() {
      _conversation.add('${widget.userName}: $message');
    });
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.targetName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _conversation.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_conversation[index]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(labelText: 'Enter message'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PublicChatScreen extends StatefulWidget {
  final String userName;
  final Map<String, Map<String, String>> connectedDevices;

  PublicChatScreen(
      {required this.userName, required this.connectedDevices});

  @override
  _PublicChatScreenState createState() => _PublicChatScreenState();
}

class _PublicChatScreenState extends State<PublicChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<String> _conversation = [];

  void sendPublicMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    widget.connectedDevices.forEach((id, device) {
      Nearby().sendBytesPayload(id, Uint8List.fromList(message.codeUnits));
    });

    setState(() {
      _conversation.add('${widget.userName}: $message');
    });
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Public Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(
                'Connected Devices',
                style: TextStyle(color: Colors.white),
              ),
            ),
            ...widget.connectedDevices.values.map((device) {
              return ListTile(
                title: Text(device['name']!),
              );
            }).toList(),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _conversation.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_conversation[index]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration:
                    const InputDecoration(labelText: 'Enter message for everyone'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendPublicMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Global map to track active chat screens
Map<String, _ChatScreenState> _chatScreens = {};




