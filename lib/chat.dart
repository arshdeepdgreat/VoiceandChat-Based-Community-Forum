import 'dart:async';
import 'package:bubble/bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:dialogflow_grpc/dialogflow_grpc.dart';
import 'package:dialogflow_grpc/generated/google/cloud/dialogflow/v2beta1/session.pb.dart';
import 'package:flutter_tts/flutter_tts.dart';



class Chat extends StatefulWidget {
  Chat({Key key}) : super(key: key);

  @override
  _ChatState createState() => _ChatState();
}

class _ChatState extends State<Chat> {

  final FlutterTts tts = FlutterTts();
  final List<ChatMessage> _messages = <ChatMessage>[];
  final TextEditingController _textController = TextEditingController();
  bool _isRecording = false;

  RecorderStream _recorder = RecorderStream();
  StreamSubscription _recorderStatus;
  StreamSubscription<List<int>> _audioStreamSubscription;
  BehaviorSubject<List<int>> _audioStream;

  // TODO DialogflowGrpc class instance
  DialogflowGrpcV2Beta1 dialogflow;

  @override
  void initState() {
    super.initState();
    initPlugin();
  }

  @override
  void dispose() {
    _recorderStatus?.cancel();
    _audioStreamSubscription?.cancel();
    super.dispose();
  }
  Future talk(String tex) async{
    await tts.setLanguage("en-US");
    await tts.setPitch(1);
    await tts.speak(tex);
    
  }
  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlugin() async {
    _recorderStatus = _recorder.status.listen((status) {
      if (mounted)
        setState(() {
          _isRecording = status == SoundStreamStatus.Playing;
        });
    });

    await Future.wait([
      _recorder.initialize()
    ]);

    // TODO Get a Service account
    // Get a Service account
    final serviceAccount = ServiceAccount.fromString(
        '${(await rootBundle.loadString('assets/credentials.json'))}');
    // Create a DialogflowGrpc Instance
    dialogflow = DialogflowGrpcV2Beta1.viaServiceAccount(serviceAccount);

  }

  void stopStream() async {
    await _recorder.stop();
    await _audioStreamSubscription?.cancel();
    await _audioStream?.close();
  }

  void handleSubmitted(text) async {
    print(text);
    _textController.clear();

    //TODO Dialogflow Code
    ChatMessage message = ChatMessage(
      text: text,
      name: "You",
      type: true,
    );

    setState(() {
      _messages.insert(0, message);
    });

    DetectIntentResponse data = await dialogflow.detectIntent(text, 'en-US');
    String fulfillmentText = data.queryResult.fulfillmentText;
    if(fulfillmentText.isNotEmpty) {
      ChatMessage botMessage = ChatMessage(
        text: fulfillmentText,
        name: "Bot",
        type: false,
      );

      setState(() {
        _messages.insert(0, botMessage);
      });
    }

  }

  void handleStream() async {
    _recorder.start();

    _audioStream = BehaviorSubject<List<int>>();
    _audioStreamSubscription = _recorder.audioStream.listen((data) {
      print(data);
      _audioStream.add(data);
    });


    // TODO Create SpeechContexts
    // Create an audio InputConfig
    var biasList = SpeechContextV2Beta1(
        phrases: [
          'Dialogflow CX',
          'Dialogflow Essentials',
          'Action Builder',
          'HIPAA'
        ],
        boost: 20.0
    );

    // See: https://cloud.google.com/dialogflow/es/docs/reference/rpc/google.cloud.dialogflow.v2#google.cloud.dialogflow.v2.InputAudioConfig
    var config = InputConfigV2beta1(
        encoding: 'AUDIO_ENCODING_LINEAR_16',
        languageCode: 'en-US',
        sampleRateHertz: 16000,
        singleUtterance: false,
        speechContexts: [biasList]
    );

    // TODO Make the streamingDetectIntent call, with the InputConfig and the audioStream
    // TODO Get the transcript and detectedIntent and show on screen

    final responseStream = dialogflow.streamingDetectIntent(config, _audioStream);
    // Get the transcript and detectedIntent and show on screen
    responseStream.listen((data) {
      //print('----');
      setState(() {
        //print(data);
        String transcript = data.recognitionResult.transcript;
        String queryText = data.queryResult.queryText;
        String fulfillmentText = data.queryResult.fulfillmentText;

        if(fulfillmentText.isNotEmpty) {
          ChatMessage message = new ChatMessage(
            text: queryText,
            name: "You",
            type: true,
          );

          ChatMessage botMessage = new ChatMessage(
            text: fulfillmentText,
            name: "Bot",
            type: false,
          );
          talk(fulfillmentText);

          _messages.insert(0, message);
          _textController.clear();
          _messages.insert(0, botMessage);

        }
        if(transcript.isNotEmpty) {
          _textController.text = transcript;
        }

      });
    },onError: (e){
      //print(e);
    },onDone: () {
      //print('done');
    });

  }

  // The chat interface
  //
  //------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Center(
        child: Container(
          padding: EdgeInsets.only(top: 15,bottom: 10),
          child: Text(
            "Today, ${DateFormat("Hm").format(DateTime.now())}",
            style: TextStyle(
                fontSize: 20
            ),
          ),
        ),
      ),
      Flexible(
          child: ListView.builder(
            padding: EdgeInsets.all(8.0),
            reverse: true,
            itemBuilder: (_, int index) => _messages[index],
            itemCount: _messages.length,
          )),
      Divider(height: 1.0),
      Container(
          decoration: BoxDecoration(color: Theme.of(context).cardColor),
          child: IconTheme(
            data: IconThemeData(color: Theme.of(context).accentColor),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8.0,vertical: 5.0),
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Container(
                      height: 35,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(15)),
                        color: Color.fromRGBO(220, 220, 220, 1),
                      ),
                      padding: EdgeInsets.only(left: 15,top: 4),
                      child: TextField(
                        controller: _textController,
                        onSubmitted: handleSubmitted,
                        decoration: InputDecoration.collapsed(
                            hintText: "Ask a question...",
                            hintStyle: TextStyle(
                            color: Colors.black54,fontSize: 20,
                          ),
                        ),
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 32.0,
                    color: Color.fromRGBO(0, 191, 255, 1),
                    icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
                    onPressed: _isRecording ? stopStream : handleStream,
                  ),
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 4.0),
                    child: IconButton(
                      color: Color.fromRGBO(0, 191, 255, 1),
                      iconSize: 32.0,
                      icon: Icon(Icons.send),
                      onPressed: () => handleSubmitted(_textController.text),
                    ),
                  ),
                ],
              ),
            ),
          )
      ),
    ]);
  }
}


//------------------------------------------------------------------------------------
// The chat message balloon
//
//------------------------------------------------------------------------------------
class ChatMessage extends StatelessWidget {
  ChatMessage({this.text, this.name, this.type});

  final String text;
  final String name;
  final bool type;

  List<Widget> otherMessage(context) {
    return <Widget>[
      new Container(
        margin: const EdgeInsets.only(right: 16.0),
        height: 60,
        width: 60,
        child: CircleAvatar(
            backgroundImage: AssetImage("assets/robot.jpg"),
        ),
      ),

      new Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(this.name,
                style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              margin: const EdgeInsets.only(top: 5.0),
              child: Bubble(
                radius: Radius.circular(15),
                color: Colors.orangeAccent,
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                      ),
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: 200,
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> myMessage(context) {
    return <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(this.name, style: Theme.of(context).textTheme.subtitle1),
            Container(
              margin: const EdgeInsets.only(top: 5.0),
              child: Bubble(
                radius: Radius.circular(15),
                color: Color.fromRGBO(23,57, 139, 1),
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                      ),
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: 200,
                          ),
                          child: Text(
                            text,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        height: 60,
        width: 60,
        margin: const EdgeInsets.only(left: 16.0),
        child: CircleAvatar(
          backgroundImage: AssetImage("assets/default.jpg"),
          ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: this.type ? myMessage(context) : otherMessage(context),
      ),
    );
  }
}