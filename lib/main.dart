import 'package:edu_vision/chatscreen.dart';
import 'package:edu_vision/const.dart';
import 'package:edu_vision/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:provider/provider.dart';
void main(){
  Gemini.init(apiKey: GEMINI_API_KEY,);
runApp(
  ChangeNotifierProvider(
          create: (_)=>ChatProvider(),
          child:const MyApp(),
     )
    );
   }
class MyApp extends StatelessWidget{
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Access Doc",
      theme: ThemeData.dark(),
      home: const ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}