import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
class ChatProvider extends ChangeNotifier {
  final gemini = Gemini.instance;
  TextEditingController questionController=TextEditingController();
  String? geminiResponse;
  FlutterTts flutterTts=FlutterTts();
  stt.SpeechToText speechToText = stt.SpeechToText();
  ChatUser currentUser = ChatUser(id: '0', firstName: 'user');
  ChatUser geminiUser = ChatUser(id: '1', firstName: 'gemma');
  List<ChatMessage> messages = [];
  double speechRate = 0.5;
  double speechPitch = 1.0;
  String language = "en-US";
  String? lastSpokenText;
  bool isListening=false;
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;
  bool _isPaused = false; // Add a state variable to track pausing
  bool get isPaused => _isPaused;
  List<DropdownMenuItem<Map<String, String>>> voiceItems = [];
  Map<String, String>? selectedVoice;
  List<ChatUser>  typingUser=[];
  List<Content> chatConversationHistory=[];
  ChatProvider() {
    getVoices();
    flutterTts=FlutterTts();
  }
  void addUserTyping(String userId, String username) {
    typingUser.add(ChatUser(id: userId, firstName: username));
    notifyListeners();
  }

  void removeUserTyping(String userId) {
    typingUser.removeWhere((user) => user.id == userId);
    notifyListeners();
  }
Future<void> settings()async{

    await flutterTts.setSpeechRate(speechRate);
  await flutterTts.setPitch(speechPitch);
  await flutterTts.setLanguage(language);

}
  Future<void> getVoices() async {
    List<dynamic>? voices = await flutterTts.getVoices;

    voiceItems = voices!.map((voice) {
      return DropdownMenuItem<Map<String, String>>(
        value: {"name": voice['name'], "locale": voice['locale']},
        child: Text("${voice['name']} (${voice['locale']})"),
      );
    }).toList();
    // Set the default voice (optional)
    selectedVoice = voiceItems.first.value;
     // speak("Default selected voice is $selectedVoice");
    notifyListeners(); // Notify UI of changes
  }
  Future<void> setVoice(Map<String, String>? voice) async {
    await flutterTts.setVoice({
      'name': voice!["name"]!,
      'locale': voice['locale']!,
    });
    notifyListeners();
    selectedVoice = voice;
    speak("you select $selectedVoice voice");
    notifyListeners();
  }

  Future<void> play() async {
    _isSpeaking = true;
    _isPaused = false;
    notifyListeners(); // Notify *before* starting to speak
    await flutterTts.setVoice(selectedVoice!);
    await flutterTts.speak(geminiResponse!);
  }

  Future<void> speak(String text) async {
    _isSpeaking = true;
    _isPaused = false;
    notifyListeners(); // Notify *before* starting to speak
    await flutterTts.speak(text);
  }

  Future<void> stop() async {
    await flutterTts.stop();
    _isSpeaking = false;
    _isPaused = false;
    notifyListeners();
  }

  Future<void> repeatSpeak() async {
    if (lastSpokenText != null && lastSpokenText!.isNotEmpty) {
      await stop(); // Stop before repeating
      await speak(lastSpokenText!);
    }
  }

  Future<void> pause() async {
    if (_isSpeaking) { // Only pause if currently speaking
      _isSpeaking = false;
      _isPaused = true;
      notifyListeners(); // Notify *before* pausing
      await flutterTts.pause();
    }
  }

  Future<void> resume() async {
    if (_isPaused) {
      _isPaused = false;
      _isSpeaking = true;
      notifyListeners(); // Notify *before* resuming
      await play(); // Use play() to resume – it will handle setup
    } else if (!_isSpeaking && !_isPaused) {
      await play();
    }

  }
  Future<void> onSend(ChatMessage chatMessage) async {
    ChatMessage markDownMessage=ChatMessage(
        user: currentUser,
        createdAt: DateTime.now(),
      isMarkdown: true,
      text: chatMessage.text,
    );
    messages=[markDownMessage,...messages];
    notifyListeners();
      String question = chatMessage.text;
      //this will generate response from gemini in stream
      geminiResponses(question);

  }

  Future<void> extractedContent(String extractedText) async {
    ChatMessage extractedMessage = ChatMessage(
        text: extractedText,
        user: currentUser,
        createdAt: DateTime.now(),
        isMarkdown: true);
    messages=[extractedMessage,...messages];
    notifyListeners();
      geminiResponses(extractedText);
  }
  Future<void> geminiResponses(String data) async {
    String accumulatedResponse = "";

    addUserTyping(geminiUser.id, geminiUser.firstName!);
    chatConversationHistory.add(Content(role: "user", parts: [Parts(text: data)]));

    gemini.streamChat(chatConversationHistory).listen((event) {
      String? responsePart = event.content?.parts?.fold(
          "", (previous, current) => "$previous ${current.text}") ??
          "";
      accumulatedResponse += responsePart;

      ChatMessage? lastMessage = messages.firstOrNull;
      if (lastMessage != null && lastMessage.user == geminiUser) {
        lastMessage.text = accumulatedResponse; // Use accumulated response
        messages[0] = lastMessage;  // Update in place
      } else {
        ChatMessage message = ChatMessage(
          isMarkdown: true,
          user: geminiUser,
          createdAt: DateTime.now(),
          text: accumulatedResponse,
        );
        messages.insert(0, message);
         // Update history
      }

      notifyListeners();

    }, onDone: () {
      chatConversationHistory.add(Content(role: "model", parts: [Parts(text: accumulatedResponse)]));
      removeUserTyping(geminiUser.id);
      geminiResponse = accumulatedResponse;
      lastSpokenText = accumulatedResponse;
      play();
      accumulatedResponse = ""; // Clear for next response
    }, onError: (error) {
      speak("Connection error please make sure you are connected to internet ");
    });
  }
  Future<void> pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String fileName=result.files.first.name;
      String extension = file.path.split('.').last;
      if (extension.toLowerCase() == 'pdf' || extension.toLowerCase() == 'docx' || extension.toLowerCase() == 'pptx') {
        try {
          speak( "You Selected $fileName file ");
          String? extractedData = await extractTextFromFile(file, extension);
          extractedContent(extractedData);
        } catch (e){
          speak("Faild to extract text from $fileName file with erro $e");
        }
      }else{
        speak("The allowed files are pptx pdf docx but you select $fileName file");
      }
    }
  }

  Future<String> extractTextFromFile(File file, String extension) async {
    String apiUrl = 'http://zohaibaziz977.pythonanywhere.com/upload'; // Replace with your Flask server URL

    var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    try {
      var response = await request.send().timeout(const Duration(minutes: 3));

      if (response.statusCode == 200) {
        var responseBody = await http.Response.fromStream(response);
        var data = jsonDecode(responseBody.body);

        if (data.containsKey('extracted_data') && data['extracted_data'] is List) {
          List extractedData = data['extracted_data'];

          if (extension.toLowerCase() == 'pptx') {
            StringBuffer result = StringBuffer();
            for (var slideData in extractedData) { // Iterate through slides
              result.writeln('Slide ${slideData['slide_number']}:');
              if (slideData['title'] != null) {
                result.writeln('Title: ${slideData['title']}');
              }
              if (slideData['subtitle'] != null) {
                result.writeln('Subtitle: ${slideData['subtitle']}');
              }
              if (slideData['content'] != null && slideData['content'].isNotEmpty) {
                result.writeln('Content:');
                for (var content in slideData['content']) {
                  result.writeln('- $content');
                }
              }
              if (slideData['tables'] != null && slideData['tables'].isNotEmpty) {
                result.writeln('Tables:');
                for (var table in slideData['tables']) {
                  result.writeln('Table: ');
                  for(var cellData in table){
                    result.writeln('Row: ${cellData['row']}, Column: ${cellData['column']}, Text: ${cellData['text']}');
                  }
                }
              }
            }
            return result.toString();
          }
          else if(extension.toLowerCase()=="docx"){
            StringBuffer result = StringBuffer();
            for (var pageData in extractedData) { //Iterate through pages
              if (pageData.containsKey('headings') && pageData['headings'] is List) {
                for (var headingData in pageData['headings']) {
                  if (headingData.containsKey('chapter')) {
                    result.writeln('Chapter ${headingData['chapter']}: ${headingData['heading']}');
                  } else {
                    result.writeln('Heading: ${headingData['heading']}');
                  }
                  if (headingData.containsKey('paragraphs') && headingData['paragraphs'] is List) {
                    for (var paragraph in headingData['paragraphs']) {
                      if (paragraph['type'] == 'bullet') {
                        result.writeln('  - ${paragraph['text']}');
                      } else {
                        result.writeln('  ${paragraph['text']}');
                      }
                    }
                  }
                }
                result.writeln('Page: ${pageData['page_number']}');
              }
            }
            return result.toString();
          }
          else if (extension.toLowerCase() == 'pdf') {
            StringBuffer result = StringBuffer();
            for (var pageData in extractedData) {
              result.writeln('Page ${pageData['page_number']}:');
              if (pageData['chapter'] != 0) { //Check if the chapter is available for the current page or not
                result.writeln('Chapter ${pageData['chapter']}');
              }

              if (pageData.containsKey("headings") && pageData["headings"] is List) {
                for (var heading in pageData['headings']) {
                  result.writeln("Heading ${heading['heading']}");
                }
              }
              if (pageData.containsKey('paragraphs') &&
                  pageData['paragraphs'] is List) {
                for (var paragraph in pageData['paragraphs']) {
                  if (paragraph['type'] == 'bullet') {
                    result.writeln('- ${paragraph['text']}');
                  } else {
                    result.writeln(paragraph['text']);
                  }
                }
              }
            }
            return result.toString();
          }
          else {
            return extractedData.map((e) => e['text']).join('\n');
          }
        } else {
          return "Invalid data format received from server.";
        }
      } else if(response.statusCode==400) {
          return "No File is Provided";
      }else if(response.statusCode==500){
        return "Error processing file";
      }
    } on TimeoutException {
      return "Request Timeout";
    } catch (e) {
      return "Error: ${e.toString()}";
    }
    return "Failed to Extract Data";
  }
  Future<void> startListening() async {
    bool available = await speechToText.initialize(
      onStatus: (val) {
        if (val == 'done') {
          handleUserQuestion();
        }
      },
      onError: (val) => throw Exception('Speech to text error: $val'),
    );
    if (available) {
      isListening = true;
      notifyListeners();
      speechToText.listen(onResult: (val) {
        questionController.text = val.recognizedWords;
        notifyListeners();
      });
    } else {
      throw Exception('Speech to text not available');
    }
  }

  Future<void> stopListening() async {
    await speechToText.stop();
    isListening = false;
    notifyListeners();
  }

  // Handle recognized speech input as a user question
  void handleUserQuestion() {
    String question = questionController.text;
    ChatMessage userMessage = ChatMessage(
      text: question,
      user: currentUser,
      createdAt: DateTime.now(),
    );
    questionController.clear();
    onSend(userMessage);
  }
  //Copy Text to ClipBoard
  Future<void > copyMessage(String message) async{
    Clipboard.setData(ClipboardData(text: message)).then((_){
      speak("Text Copied to ClipBoard Successfully");
    }
    );
  }
}