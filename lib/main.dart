import 'dart:convert';
// import 'dart:html';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;


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
      home: BlindVSVolunteer(),
    );
  }
}
bool isBlind = false;
late var  id;


class BlindVSVolunteer extends StatelessWidget{

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(

        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                isBlind=true;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MyHomePage(),
                  ),);
              },
              style: ElevatedButton.styleFrom(
                  primary: Colors.blue,
                  minimumSize: Size.fromWidth(double.infinity),
              ),
              child: Text(
                  'Blind',
                  style: TextStyle(
                    fontWeight:FontWeight.bold,
                    fontSize: 32.0,
                    color: Colors.white,

                  ),
                ),
              ),
            ),
          Expanded(
            child: ElevatedButton(

              onPressed: () {
                isBlind=false;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MyHomePage(),
                  ),);
              },
              style: ElevatedButton.styleFrom(
                  primary: Colors.purple,
                  minimumSize: Size.fromWidth(double.infinity),
              ),
              child: Text(
                  'Volunteer',
                  style: TextStyle(
                    fontWeight:FontWeight.bold,
                    fontSize: 32.0,
                    color: Colors.white,

                  ),
                ),
              ),
            ),

        ],

      ),
    );

  }

}

class MyHomePage extends StatefulWidget {



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
    socket!.disconnect();

    super.dispose();
  }

  @override
  void initState() {
    initRenderer();
    connect();
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

  void connect() {
    socket = IO.io("",<String, dynamic>{
      "transports":["websocket"],
      "autoConnect":false,
    });
    socket!.connect();
    socket!.onConnect((_) {
      print("connected to server");
    });
    print(socket!.connected);
     id = socket!.id;
    print(id);
    socket!.emit('ID to server','$id'+' '+'$isBlind');

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

    int counter = 0;
    pc.onIceCandidate = (e) {
      if (e.candidate != null) {
        var temp=json.encode({
          'candidate': e.candidate.toString(),
          'sdpMid': e.sdpMid.toString(),
          'sdpMlineIndex': e.sdpMlineIndex,

        });
        print(temp);
        if(counter==0) {
          socket!.emit('get ICE', '$temp' + ' ' + '$id' + ' ' + '$isBlind');
        }
        counter ++;

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
    socket!.emit('on offer','$session'+' '+'$id'+'$isBlind');
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
    socket!.emit('on answer','$session'+' '+'$id'+'$isBlind');
    // print(json.encode({
    //       'sdp': description.sdp.toString(),
    //       'type': description.type.toString(),
    //     }));

    _peerConnection!.setLocalDescription(description);
  }

  void _setRemoteDescription() async {
    String? jsonString;
    if(isBlind!){
      socket!.on('getting Second side SDP of Blind', (data) => {
        jsonString= data,
      });
    }
    else{
      socket!.on('getting Second side SDP of volunteer', (data) => {
        jsonString= data,
      });
    }


    //sdpController.text;
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
    String? jsonString;
    // TODO: for more than one blind person we need to set id
    socket!.on('getting ICE from blind', (data) => {
      jsonString= data,
    });


        //sdpController.text;
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
          onPressed: (){
            _createOffer();
            _setRemoteDescription();
          },
          child: Text('Offer'),
           style: ElevatedButton.styleFrom(primary: Colors.green),
        ),
        ElevatedButton(
          onPressed: (){
            _createAnswer();
            _setRemoteDescription();
            _addCandidate();
          },
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