import 'dart:convert';
// import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(

      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final WebSocketChannel channel;
  MyHomePage(this.channel);


  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _offer = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();

  final sdpController = TextEditingController();

   IO.Socket? socket;

  @override
  dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    sdpController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    initRenderer();
    _createPeerConnection().then((pc) {
      _peerConnection = pc;
    });
    // _getUserMedia();
    super.initState();
  }

  initRenderer() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _createPeerConnection() async {
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final Map<String, dynamic> offerSdpConstraints = {
      "mandatory": {
        "OfferToReceiveAudio": true,
        "OfferToReceiveVideo": true,
      },
      "optional": [],
    };

    _localStream = await _getUserMedia();

    RTCPeerConnection pc =
    await createPeerConnection(configuration, offerSdpConstraints);

    pc.addStream(_localStream!);

    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        print(json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMlineIndex,
        }));
      }
    };

    pc.onIceConnectionState = (e) {
      print(e);
    };

    pc.onAddStream = (stream) {
      print('addStream: ' + stream.id);
      _remoteRenderer.srcObject = stream;
    };

    return pc;
  }

  _getUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': false,
      'video': {
        'facingMode': 'user',
      },
    };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(constraints);

    _localRenderer.srcObject = stream;
    // _localRenderer.mirror = true;

    return stream;
  }

  void _createOffer() async {
    RTCSessionDescription description =
    await _peerConnection!.createOffer({'offerToReceiveVideo': 1, 'offerToReceiveAudio' :1});
    var session = parse(description.sdp.toString());
    print(json.encode(session));
    _offer = true;

    // print(json.encode({
    //       'sdp': description.sdp.toString(),
    //       'type': description.type.toString(),
    //     }));

    _peerConnection!.setLocalDescription(description);
  }

  void _createAnswer() async {
    RTCSessionDescription description =
    await _peerConnection!.createAnswer({'offerToReceiveVideo': 1, 'offerToReceiveAudio' :1});

    var session = parse(description.sdp.toString());
    print(json.encode(session));
    // print(json.encode({
    //       'sdp': description.sdp.toString(),
    //       'type': description.type.toString(),
    //     }));

    _peerConnection!.setLocalDescription(description);
  }

  void _setRemoteDescription() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');

    String sdp = write(session, null);

    // RTCSessionDescription description =
    //     new RTCSessionDescription(session['sdp'], session['type']);
    RTCSessionDescription description =
    new RTCSessionDescription(sdp, _offer ? 'answer' : 'offer');
    print(description.toMap());

    await _peerConnection!.setRemoteDescription(description);
  }

  void _addCandidate() async {
    String jsonString = sdpController.text;
    dynamic session = await jsonDecode('$jsonString');
    print(session['candidate']);
    dynamic candidate =
    new RTCIceCandidate(session['candidate'], session['sdpMid'], session['sdpMlineIndex']);
    await _peerConnection!.addCandidate(candidate);
  }

  SizedBox videoRenderers() =>
      SizedBox(
      height: 210,
      child: Row(children: [
        Flexible(
          child: new Container(
              key: new Key("local"),
              margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: new BoxDecoration(color: Colors.black),
              child: new RTCVideoView(_localRenderer)),
        ),
        Flexible(
          child: new Container(
              key: new Key("remote"),
              margin: new EdgeInsets.fromLTRB(5.0, 5.0, 5.0, 5.0),
              decoration: new BoxDecoration(color: Colors.black),
              child: new RTCVideoView(_remoteRenderer)),
        )
      ]));

  Row offerAndAnswerButtons() =>
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
         ElevatedButton(
          // onPressed: () {
          //   return showDialog(
          //       context: context,
          //       builder: (context) {
          //         return AlertDialog(
          //           content: Text(sdpController.text),
          //         );
          //       });
          // },
          onPressed: _createOffer,
          child: Text('Offer'),
           style: ElevatedButton.styleFrom(primary: Colors.green),
        ),
        ElevatedButton(
          onPressed: _createAnswer,
          child: Text('Answer'),
          style: ElevatedButton.styleFrom(primary: Colors.blue),
        ),
      ]);

  Row sdpCandidateButtons() =>
      Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
        ElevatedButton(
          onPressed: _setRemoteDescription,
          child: Text('Set Remote Desc'),
          style: ElevatedButton.styleFrom(primary: Colors.deepOrange),
        ),
        ElevatedButton(
          onPressed: _addCandidate,
          child: Text('Add Candidate'),
          style: ElevatedButton.styleFrom(primary: Colors.blueGrey),
        )
      ]);

  Padding sdpCandidatesTF() =>
      Padding(
    padding: const EdgeInsets.all(16.0),
    child: TextField(
      controller: sdpController,
      keyboardType: TextInputType.multiline,
      maxLines: 4,
      maxLength: TextField.noMaxLength,
    ),
  );

  // void connect()
  // {
  //   socket = IO.io('http://192.168.43.92:5000''heshk beshk ',<String,dynamic>{
  //     'transports':['websocket'],
  //     'autoConnect':false,
  //   });
  //   socket!.connect();
  //   socket!.onConnect((data)=> print('connected'));
  //   print(socket!.connected);
  //   socket!.emit('/test','hello world');
  //
  // }

  // connectSocket() {
  //   socket = IO.io('baseURL', {
  //     'query': {
  //       'name': 'myName',
  //     }
  //   });
  //
  //   socket.on('newCall', data => {
  //   otherUser = data.caller;
  //   remoteRTCMessage = data.rtcMessage
  //
  //   //DISPLAY ANSWER SCREEN
  //   })
  //
  //   socket.on('callAnswered', data => {
  //   remoteRTCMessage = data.rtcMessage
  //   peerConnection.setRemoteDescription(new RTCSessionDescription(remoteRTCMessage));
  //
  //   callProgress()
  //   })
  //
  //   socket.on('ICEcandidate', data => {
  //   let message = data.rtcMessage
  //
  //   let candidate = new RTCIceCandidate({
  //   sdpMLineIndex: message.label,
  //   candidate: message.candidate
  //   });
  //
  //   if (peerConnection) {
  //   peerConnection.addIceCandidate(candidate);
  //   }
  //   })
  // }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Video Conference'),
        ),
        body: Container(
            child: Container(
                child: Column(
                  children: [
                    videoRenderers(),
                    offerAndAnswerButtons(),
                    sdpCandidatesTF(),
                    sdpCandidateButtons(),
                  ],
                ))
          // new Stack(
          //   children: [
          //     new Positioned(
          //       top: 0.0,
          //       right: 0.0,
          //       left: 0.0,
          //       bottom: 0.0,
          //       child: new Container(
          //         child: new RTCVideoView(_localRenderer)
          //       )
          //     )
          //   ],
          // ),
        ));
  }
}